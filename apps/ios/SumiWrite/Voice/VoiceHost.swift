import Combine
import UIKit
import VoiceKit
import VoiceKitUI

/// 按住说话(ios.md §3.7)在 Sumi 一侧的宿主:持有 VoiceKit 的 `VoiceInput` 与 `VoiceHold`,把落地交给编辑面,
/// 把提示交给外壳的提示条,把音频会话交还打字音。识别、松手的选择与绘制都在 VoiceKit 里。
@MainActor
final class VoiceHost: ObservableObject, VoiceSink {
    /// 「识别语言跟随系统」只提示一次,记在这里。
    static let languageHintKey = "voice.languageHintShown"

    let voice: VoiceInput
    private(set) lazy var hold = VoiceHold(voice: voice, sink: self)
    /// 要显示的提示与它是否带「去设置」;外壳用自己的提示条显示。
    var onNotice: ((String, VoiceSettings) -> Void)?

    private weak var controller: EditorController?
    private let prefs: PrefsModel
    private let sound: TypingSound?
    private let defaults: UserDefaults
    private var overlay: VoiceOverlayView?
    private var bag = Set<AnyCancellable>()
    /// 打字音让出了会话,还没收回。
    private var yielded = false
    /// 麦克风按钮上的手指按着(手势还没结束或被取消)。
    private var fingerDown = false
    /// VoiceOver 双击开始的一次说话还没结束。
    private var accessibilityOn = false

    /// 以后接 AI 整理时在末尾加带默认值的参数。
    init(controller: EditorController, prefs: PrefsModel, sound: TypingSound? = nil, defaults: UserDefaults = .standard,
         engine: SpeechEngine = SystemSpeechEngine(), permissions: SpeechPermissions = SystemSpeechPermissions()) {
        self.controller = controller
        self.prefs = prefs
        self.sound = sound
        self.defaults = defaults
        voice = VoiceInput(engine: engine, permissions: permissions)
        voice.restoreAudio = { [weak self] in self?.reclaimAudio() }
        hold.languageHintDue = { [weak self] in
            guard let self else { return false }
            return !self.defaults.bool(forKey: Self.languageHintKey)
        }
        hold.languageHintShown = { [weak self] in
            guard let self else { return }
            self.defaults.set(true, forKey: Self.languageHintKey)
        }
        // `$prefs` 在 willSet 时发值:用发来的值。
        prefs.$prefs
            .sink { [weak self] p in self?.overlay?.style = .sumi(p) }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.overlay?.style = .sumi(self.prefs.prefs)
            }
            .store(in: &bag)
    }

    /// 把 `VoiceOverlayView` 铺满整个窗口、放在最上层(在编辑面与底栏之上);它不接触点。
    /// 它的坐标就是窗口坐标,所以按下时的手指位置用 `.global`。
    func attach(to window: UIWindow) {
        if let overlay, overlay.window === window {
            window.bringSubviewToFront(overlay)
            return
        }
        overlay?.removeFromSuperview()
        let o = VoiceOverlayView(hold: hold, voice: voice, style: .sumi(prefs.prefs))
        o.frame = window.bounds
        o.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(o)
        overlay = o
    }

    // MARK: 麦克风按钮

    /// 手指按下或移动;`point` 是窗口坐标(`DragGesture` 的 `.global`)。
    func finger(at point: CGPoint) {
        if fingerDown {
            hold.move(to: point)
            return
        }
        fingerDown = true
        guard let window = controller?.viewIfLoaded?.window else { return }
        attach(to: window)
        let stage = window.bounds.size
        // 麦克风在底栏右端:圆盘向左上长开。
        Task { await hold.down(thumb: point, stage: stage, right: true) }
    }

    /// 手指松开:按当前的选择插入、插入原话或取消。
    func fingerUp() {
        guard fingerDown else { return }
        fingerDown = false
        Task { await hold.up() }
    }

    /// 系统抢走了触点(手势被取消)、来电、退到后台:按取消处理,已说出的字不插入。
    func interrupt() {
        fingerDown = false
        accessibilityOn = false
        Task { await hold.cancel() }
    }

    /// 手势结束时若没走到 `fingerUp`(被系统取消),当作打断。
    func fingerGone() {
        if fingerDown { interrupt() }
    }

    /// VoiceOver:双击开始,再双击结束(插入)。没有手指,不画圆盘,只画气泡。
    func accessibilityToggle() {
        if accessibilityOn {
            accessibilityOn = false
            Task { await hold.finish(.send) }
            return
        }
        accessibilityOn = true
        if let window = controller?.viewIfLoaded?.window { attach(to: window) }
        Task {
            await hold.start()
            // 被拒绝、请求授权、没能开始:下一次双击重新开始。
            if !hold.holding { accessibilityOn = false }
        }
    }

    /// 「去设置」:语音权限与识别语言都只能在系统设置里改,iOS 只开得到本应用的设置页。
    func openSettings(_ settings: VoiceSettings) {
        guard settings != .none, let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 提示条显示多久(秒):VoiceKit 给的时长;带「去设置」时至少 4 s。
    static func noticeLife(_ text: String, settings: VoiceSettings) -> Double {
        let c = voiceHintLife(text).components
        let life = Double(c.seconds) + Double(c.attoseconds) / 1e18
        return settings == .none ? life : max(life, 4)
    }

    // MARK: VoiceSink

    func voiceWillStart() -> String? {
        guard let controller else { return "这一页现在不能写" }
        if let refused = controller.voiceWillStart() { return refused }
        // 录音要把会话切到 `.record`:这期间打字音不去改回来。
        sound?.yieldSession()
        yielded = true
        return nil
    }

    func voiceInsert(_ text: String, pick: VoicePick) {
        controller?.insertVoice(text)
    }

    func voiceNotice(_ text: String, settings: VoiceSettings) {
        onNotice?(text, settings)
    }

    func voiceDidEnd(_ pick: VoicePick?) {
        accessibilityOn = false
        // 没走到录音(请求授权、被拒绝、轻点)时不会有 `restoreAudio`:在这里收回。
        if yielded { reclaimAudio() }
    }

    private func reclaimAudio() {
        yielded = false
        sound?.reclaimSession()
    }
}
