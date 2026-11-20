import AVFoundation
import Foundation

/// 打字音。会话为 `.ambient` + `.mixWithOthers`,所以跟随静音开关、不打断别的音频。
/// 引擎启动与样本加载都在后台队列;`play` 在输入路径上只取锁、挑节点、排一个缓冲,失败即无声。
final class TypingSound: TypingSoundPlaying {
    private struct Slot: Hashable {
        let pack: SoundPack
        let kind: KeyKind
    }

    private struct Bank {
        var buffers: [AVAudioPCMBuffer] = []
        var players: [AVAudioPlayerNode] = []
        var next = 0
    }

    private static let playersPerKind = 4

    private let bundle: Bundle
    private let prefs: () -> EditorPrefs
    private let queue = DispatchQueue(label: "sumi.typingsound", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private var observers: [NSObjectProtocol] = []

    /// 以下三项由 `lock` 保护:后台队列写,`play` 读。
    private let lock = NSLock()
    private var ready = false
    private var banks: [Slot: Bank] = [:]
    private var played = 0

    /// 实际排进缓冲的 `play` 次数;只供测试读取。
    var playedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return played
    }

    init(bundle: Bundle, prefs: @escaping () -> EditorPrefs) {
        self.bundle = bundle
        self.prefs = prefs
        queue.async { [weak self] in self?.setUp() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            switch raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
            case .began: self?.setReady(false)
            case .ended: self?.restart()
            default: break
            }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.setReady(false)
            self?.restart()
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        engine.stop()
    }

    func play(before: String, after: String) {
        let p = prefs()
        guard p.typingSound, let kind = KeyKind.classify(before: before, after: after) else { return }
        lock.lock()
        defer { lock.unlock() }
        let slot = Slot(pack: p.soundPack, kind: kind)
        guard ready, var bank = banks[slot], !bank.buffers.isEmpty, !bank.players.isEmpty else { return }
        let player = bank.players[bank.next % bank.players.count]
        bank.next += 1
        banks[slot] = bank
        player.scheduleBuffer(bank.buffers.randomElement()!, at: nil, options: .interrupts)
        played += 1
    }

    // MARK: 后台

    private func setUp() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: .mixWithOthers)
            let manifest = try SoundManifest.load(from: bundle.bundleURL.appendingPathComponent("sounds"))
            var loaded: [Slot: Bank] = [:]
            for pack in SoundPack.allCases {
                for kind in [KeyKind.key, .space, .enter, .delete] {
                    if let bank = makeBank(manifest.files(pack: pack, kind: kind)) { loaded[Slot(pack: pack, kind: kind)] = bank }
                }
            }
            guard !loaded.isEmpty else { return }
            lock.lock(); banks = loaded; lock.unlock()
            try session.setActive(true)
            try engine.start()
            startPlayers()
            setReady(true)
        } catch {
            setReady(false)
        }
    }

    /// 同一 role 的文件取第一个文件的格式;格式不同的文件跳过。
    private func makeBank(_ files: [String]) -> Bank? {
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
        lock.lock()
        let nodes = banks.values.flatMap(\.players)
        lock.unlock()
        for n in nodes { n.play() }
    }

    private func setReady(_ value: Bool) {
        lock.lock(); ready = value; lock.unlock()
    }

    private func restart() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                if !self.engine.isRunning { try self.engine.start() }
                self.startPlayers()
                self.setReady(true)
            } catch {
                self.setReady(false)
            }
        }
    }
}
