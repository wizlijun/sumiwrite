import AVFoundation
import Foundation
import UIKit

/// 打字音。会话为 `.playback` + `.mixWithOthers`,所以不受静音键影响、不打断别的音频(ios.md §3.4)。
/// 引擎、节点与样本都只在声音队列上动;`play` 在输入路径上只读偏好、取锁看一眼就绪标志,失败即无声。
///
/// - 打字音关着时不建引擎;打开设置或第一次需要发声时才建,并且只加载选中的音色。
/// - 打断结束、回到前台、引擎配置变化时重新激活会话并启动引擎;媒体服务重置时从头重建引擎与节点。
/// - 由输入触发的启动失败后,`retryInterval` 内不再由输入重试;由事件触发的失败稍后再试一次。
final class TypingSound: TypingSoundPlaying {
    private struct Bank {
        var buffers: [AVAudioPCMBuffer] = []
        var players: [AVAudioPlayerNode] = []
        var next = 0
    }

    private enum Trigger { case input, event, retry }

    private enum SetUpError: Error { case noSamples }

    private static let playersPerKind = 4
    private static let kinds: [KeyKind] = [.key, .space, .enter, .delete]
    private static let retryInterval: TimeInterval = 1

    private let bundle: Bundle
    private let prefs: () -> EditorPrefs
    private let center: NotificationCenter
    private let queue = DispatchQueue(label: "sumi.typingsound", qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []

    /// 以下只在 `queue` 上读写。
    private var engine: AVAudioEngine?
    private var loadedPack: SoundPack?
    private var banks: [KeyKind: Bank] = [:]
    /// 想要的音色;`nil` 表示打字音关着。
    private var wanted: SoundPack?
    private var lastInputFailure: Date?
    /// 收到打断 `.began` 后为真;这期间输入与稍后重试都不启动,等 `.ended`、回到前台、媒体服务重置或偏好变化。
    private var interrupted = false
    private var retryPending = false
    /// 语音输入借走了会话(`.record`):这期间什么都不激活,等 `reclaimSession`(ios.md §3.7「音频」)。
    private var yielded = false

    /// 以下由 `lock` 保护:声音队列写,`play` 与测试读。
    private let lock = NSLock()
    private var ready = false
    private var played = 0
    private var attempts = 0
    private var rebuilds = 0

    /// 实际排进缓冲的 `play` 次数;只供测试读取。
    var playedCount: Int { locked { played } }
    /// 尝试激活会话、启动引擎的次数;只供测试读取。
    var startAttempts: Int { locked { attempts } }
    /// 因媒体服务重置而从头重建的次数;只供测试读取。
    var rebuildCount: Int { locked { rebuilds } }
    /// 当前建好的引擎所加载的音色;没有引擎时为 `nil`。只供测试读取。
    var builtPack: SoundPack? { queue.sync { engine == nil ? nil : loadedPack } }

    init(bundle: Bundle, prefs: @escaping () -> EditorPrefs, center: NotificationCenter = .default) {
        self.bundle = bundle
        self.prefs = prefs
        self.center = center
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            switch raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
            case .began: self?.interrupt()
            case .ended: self?.restart()
            default: break
            }
        })
        // 系统不保证每个打断都配一个 `.ended`;回到前台时再试一次。
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.restart()
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            self?.rebuild()
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] note in
            let source = (note.object as AnyObject?).map(ObjectIdentifier.init)
            self?.queue.async { [weak self] in
                guard let self, let engine = self.engine, source == ObjectIdentifier(engine) else { return }
                self.setReady(false)
                self.activate(.event)
            }
        })
    }

    deinit {
        for o in observers { center.removeObserver(o) }
        engine?.stop()
    }

    /// 输入路径上只读偏好;引擎没就绪时在声音队列上按需启动,分类与排缓冲也都在声音队列上做。
    func play(before: String, after: String, kind: KeyKind?) {
        let p = prefs()
        guard p.typingSound else { return }
        let pack = p.soundPack
        queue.async { [weak self] in
            guard let self else { return }
            self.wanted = pack
            if !self.isReady || self.loadedPack != pack { self.activate(.input) }
            self.schedule(before: before, after: after, kind: kind)
        }
    }

    /// 偏好变化:关掉就停引擎并放掉节点;打开或换音色就按选中的音色重建。
    func preferencesChanged(_ p: EditorPrefs) {
        let pack: SoundPack? = p.typingSound ? p.soundPack : nil
        queue.async { [weak self] in
            guard let self else { return }
            self.wanted = pack
            if pack == nil {
                self.teardown(stop: true)
            } else if !self.isReady || self.loadedPack != pack {
                self.activate(.event)
            }
        }
    }

    /// 语音输入开始前调用:会话要交给录音,这期间输入、打断结束、引擎配置变化都不去把会话改回 `.playback`。
    func yieldSession() {
        setReady(false)
        queue.async { [weak self] in self?.yielded = true }
    }

    /// 语音输入用完会话之后调用:重新配置 `.playback` + `.mixWithOthers`,重启引擎与播放节点。
    /// 打断(来电)还没结束时不抢,等 `.ended` 或回到前台。
    func reclaimSession() {
        setReady(false)
        queue.async { [weak self] in
            guard let self else { return }
            self.yielded = false
            if !self.interrupted { self.activate(.event) }
        }
    }

    /// 等声音队列排空;只供测试。
    func waitUntilIdle() { queue.sync {} }

    // MARK: 声音队列

    func play(kind: KeyKind) {
        let p = prefs()
        guard p.typingSound else { return }
        let pack = p.soundPack
        queue.async { [weak self] in
            guard let self else { return }
            self.wanted = pack
            if !self.isReady || self.loadedPack != pack { self.activate(.input) }
            self.schedule(kind)
        }
    }

    private func schedule(before: String, after: String, kind hint: KeyKind?) {
        // 文字没变不发声;变了以输入代理判出的种类为准。
        guard let kind = KeyKind.classify(before: before, after: after).map({ hint ?? $0 }) else { return }
        schedule(kind)
    }

    private func schedule(_ kind: KeyKind) {
        guard let engine, engine.isRunning, isReady,
              var bank = banks[kind], !bank.buffers.isEmpty, !bank.players.isEmpty else { return }
        let player = bank.players[bank.next % bank.players.count]
        bank.next += 1
        banks[kind] = bank
        player.scheduleBuffer(bank.buffers.randomElement()!, at: nil, options: .interrupts)
        locked { played += 1 }
    }

    private func interrupt() {
        setReady(false)
        queue.async { [weak self] in self?.interrupted = true }
    }

    private func restart() {
        queue.async { [weak self] in
            self?.interrupted = false
            self?.activate(.event)
        }
    }

    /// 媒体服务重置后旧的引擎与节点全部失效:丢掉它们(不再调用),再从头建。
    private func rebuild() {
        queue.async { [weak self] in
            guard let self else { return }
            self.locked { self.rebuilds += 1 }
            self.interrupted = false
            self.teardown(stop: false)
            self.activate(.event)
        }
    }

    /// 按 `wanted` 激活会话、必要时建引擎并启动;任何失败都只是无声。
    private func activate(_ trigger: Trigger) {
        guard let pack = wanted, !yielded else { return }
        if trigger != .event && interrupted { return }
        if trigger == .input, let t = lastInputFailure, Date().timeIntervalSince(t) < Self.retryInterval { return }
        locked { attempts += 1 }
        do {
            if engine == nil || loadedPack != pack { try build(pack) }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
            guard let engine else { throw SetUpError.noSamples }
            if !engine.isRunning { try engine.start() }
            startPlayers()
            setReady(engine.isRunning)
        } catch {
            setReady(false)
        }
        guard !isReady else {
            lastInputFailure = nil
            return
        }
        switch trigger {
        case .input:
            lastInputFailure = Date()
        case .event where !retryPending:
            retryPending = true
            queue.asyncAfter(deadline: .now() + Self.retryInterval) { [weak self] in
                guard let self else { return }
                self.retryPending = false
                if !self.isReady { self.activate(.retry) }
            }
        case .event, .retry:
            break
        }
    }

    /// 只加载选中的音色;一种按键都没加载成功就不留引擎。
    private func build(_ pack: SoundPack) throws {
        teardown(stop: true)
        let manifest = try SoundManifest.load(from: bundle.bundleURL.appendingPathComponent("sounds"))
        let e = AVAudioEngine()
        var loaded: [KeyKind: Bank] = [:]
        for kind in Self.kinds {
            if let bank = makeBank(manifest.files(pack: pack, kind: kind), engine: e) { loaded[kind] = bank }
        }
        guard !loaded.isEmpty else { throw SetUpError.noSamples }
        engine = e
        banks = loaded
        loadedPack = pack
    }

    private func teardown(stop: Bool) {
        setReady(false)
        if stop { engine?.stop() }
        engine = nil
        banks = [:]
        loadedPack = nil
    }

    /// 同一 role 的文件取第一个文件的格式;格式不同的文件跳过。
    private func makeBank(_ files: [String], engine: AVAudioEngine) -> Bank? {
        let dir = bundle.bundleURL.appendingPathComponent("sounds")
        var bank = Bank()
        var format: AVAudioFormat?
        for file in files {
            guard let f = try? AVAudioFile(forReading: dir.appendingPathComponent(file)),
                  format == nil || f.processingFormat == format,
                  let buffer = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
                  (try? f.read(into: buffer)) != nil else { continue }
            format = f.processingFormat
            bank.buffers.append(buffer)
        }
        guard let format, !bank.buffers.isEmpty else { return nil }
        for _ in 0..<Self.playersPerKind {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            bank.players.append(node)
        }
        return bank
    }

    private func startPlayers() {
        // 节点在引擎停着时 `play()` 会抛出无法捕获的异常,所以只在引擎运行时启动。
        guard let engine, engine.isRunning else { return }
        for n in banks.values.flatMap(\.players) { n.play() }
    }

    private var isReady: Bool { locked { ready } }

    private func setReady(_ value: Bool) { locked { ready = value } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}
