import Combine
import UIKit
import VoiceKit
import VoiceKitUI

/// 按住说话(ios.md §3.8)在 Sumi 一侧的宿主:持有 VoiceKit 的 `VoiceInput` 与 `VoiceHold`,把落地交给编辑面,
/// 把提示交给外壳的提示条,把音频会话交还打字音。识别、松手的选择与绘制都在 VoiceKit 里。
@MainActor
final class VoiceHost: ObservableObject, VoiceSink {
    /// 「识别语言跟随系统」只提示一次,记在这里。
    static let languageHintKey = "voice.languageHintShown"
    /// 整理后的文字落地时的提示,显示 1.5 s(ios.md §3.8「AI 整理」)。
    static let tidiedNotice = "已用 AI 整理"
    static let restoredNotice = "上次没插入的语音已放回本页末尾"

    let voice: VoiceInput
    private(set) lazy var hold = VoiceHold(voice: voice, sink: self)
    /// AI 整理(ios.md §3.8「AI 整理」);会话就是纸页,`sid` 是纸页 id。
    private(set) var tidy: VoiceTidy!
    /// 要显示的提示与它是否带「去设置」;外壳用自己的提示条显示。
    var onNotice: ((String, VoiceSettings) -> Void)?

    private weak var controller: EditorController?
    private let prefs: PrefsModel
    private let sound: TypingSound?
    private let defaults: UserDefaults
    private var overlay: VoiceOverlayView?
    private var card: TidyCardView?
    /// 整理中与整理好、还没落地的字,按纸页 id 存在 Application Support/voice-held(ios.md §3.8「AI 整理」)。
    private let held: TidyHeld
    /// 这次落地没能插入(纸页换了、组字中、不可写)或被收起的字:紧跟着的 `held(sid, nil)` 把它留下,而不是删掉。
    private var unlanded: String?
    private var bag = Set<AnyCancellable>()
    /// 打字音让出了会话,还没收回。
    private var yielded = false
    /// 麦克风按钮上的手指按着(手势还没结束或被取消),而且这次按下还没结束。
    private var fingerDown = false
    /// 当前这次触摸的起点,用来认出同一个手势:按下已结束(`voiceDidEnd`)而手指还没抬起时,它后来的移动不再开始新的一次;
    /// 手势无声无息地没了,下一次触摸的起点不同,照样能开始。
    private var fingerStart: CGPoint?
    /// VoiceOver 双击开始的一次说话还没结束。
    private var accessibilityOn = false
    /// 这次说话收起了软键盘,还没换回(ios.md §3.8「软键盘」)。
    private var keyboardHidden = false
    /// 这次说话的字落进了纸页:结束时编辑面取得焦点。
    private var landed = false

    /// `endpoint` 为 nil:读 `TidyEndpointStore`(钥匙串);测试注入,不碰钥匙串。`heldDir` 为 nil:Application Support/voice-held。
    init(controller: EditorController, prefs: PrefsModel, sound: TypingSound? = nil, defaults: UserDefaults = .standard,
         engine: SpeechEngine = SystemSpeechEngine(), permissions: SpeechPermissions = SystemSpeechPermissions(),
         api: LlmApi = LlmApi(), endpoint: (() -> LlmEndpoint)? = nil, heldDir: URL? = nil) {
        self.controller = controller
        self.prefs = prefs
        self.sound = sound
        self.defaults = defaults
        held = TidyHeld { heldDir ?? Self.heldDirectory() }
        voice = VoiceInput(engine: engine, permissions: permissions)
        let endpoint = endpoint ?? { TidyEndpointStore.shared.endpoint }
        tidy = VoiceTidy(
            sid: controller.pageID ?? "",
            endpoint: endpoint, api: api,
            allowed: { [weak prefs] _ in (prefs?.prefs.voiceTidy ?? false) && endpoint().configured },
            edit: { [weak self] sid, text, ai in self?.land(sid, text, ai) },
            keep: { [weak self] _, text in self?.unlanded = text },
            held: { [weak self] sid, text in self?.keepHeld(sid, text) })
        // 只有「插入」整理;「原话」从不整理(ios.md §3.8「AI 整理」)。
        hold.tidy = { [weak self] text, pick, at in
            guard let self, pick == .send, let id = self.controller?.pageID else { return false }
            self.tidy.moveTo(id)
            self.card?.tail = !self.hold.keyboard
            return self.tidy.begin(text, pick, at: at)
        }
        hold.wouldTidy = { [weak self] text in
            guard let self else { return false }
            return self.hold.pick == .send && self.tidy.would(text)
        }
        hold.prefetch = { [weak self] text in self?.tidy.prefetch(text) }
        controller.voiceTidyBusy = { [weak self] in self?.tidyBusy ?? false }
        controller.onVoiceTidyKey = { [weak self] in self?.landTidy() }
        controller.onPageShown = { [weak self] id in self?.restoreHeld(id) }
        voice.restoreAudio = { [weak self] in self?.reclaimAudio() }
        hold.languageHintDue = { [weak self] in
            guard let self else { return false }
            return !self.defaults.bool(forKey: Self.languageHintKey)
        }
        hold.languageHintShown = { [weak self] in
            guard let self else { return }
            self.defaults.set(true, forKey: Self.languageHintKey)
        }
        controller.onVoiceKey = { [weak self] phase in self?.key(phase) }
        // 开始录音:收起软键盘(ios.md §3.8「软键盘」)。`$holding` 在 willSet 时发值:用发来的值。
        hold.$holding
            .sink { [weak self] holding in
                guard let self, holding else { return }
                self.landed = false
                self.keyboardHidden = true
                self.controller?.hideKeyboardForVoice()
            }
            .store(in: &bag)
        // 整理卡收起(落地、还原、出错提示):换回软键盘。落地的字在同一轮里插入,所以下一轮再看。
        tidy.$phase
            .sink { [weak self] phase in
                guard phase != .tidying, phase != .ready else { return }
                DispatchQueue.main.async { self?.settleKeyboard() }
            }
            .store(in: &bag)
        controller.voiceKeyReady = { [weak self] in self?.idle ?? false }
        // `$prefs` 在 willSet 时发值:用发来的值。
        prefs.$prefs
            .sink { [weak self] p in
                self?.overlay?.style = .sumi(p)
                self?.card?.style = .sumi(p)
            }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.overlay?.style = .sumi(self.prefs.prefs)
                self.card?.style = .sumi(self.prefs.prefs)
            }
            .store(in: &bag)
    }

    /// 把 `VoiceOverlayView` 铺满整个窗口、放在最上层(在编辑面与底栏之上);它不接触点。
    /// 它的坐标就是窗口坐标,所以按下时的手指位置用 `.global`。整理卡同样铺满、在它之上,只有卡本身接触点。
    func attach(to window: UIWindow) {
        if let overlay, let card, overlay.window === window {
            window.bringSubviewToFront(overlay)
            window.bringSubviewToFront(card)
            return
        }
        overlay?.removeFromSuperview()
        card?.removeFromSuperview()
        let o = VoiceOverlayView(hold: hold, voice: voice, style: .sumi(prefs.prefs))
        o.frame = window.bounds
        o.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(o)
        overlay = o
        let c = TidyCardView(tidy: tidy, style: .sumi(prefs.prefs))
        c.frame = window.bounds
        c.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(c)
        card = c
    }

    // MARK: AI 整理

    /// 整理卡还在(整理中或整理好、还没落地)。
    var tidyBusy: Bool { tidy.phase == .tidying || tidy.phase == .ready }

    /// 卡上的字立刻落地:整理好了插入整理后的字,还没好插入原话。按键、再按住说话、切页、开概览或设置、退到后台之前调用。
    func landTidy() {
        guard tidyBusy else { return }
        tidy.sendNow()
        // 切页、开概览或设置、退到后台时落地:不为它取得焦点、弹出软键盘;按键时编辑面本来就有焦点。
        landed = false
    }

    /// 说话与整理卡都结束后换回软键盘:字落了地就让编辑面取得焦点(没接实体键盘时软键盘展开),否则回到说话前。
    private func settleKeyboard() {
        guard idle, !tidyBusy, keyboardHidden || landed else { return }
        controller?.restoreKeyboardAfterVoice(landed: landed)
        keyboardHidden = false
        landed = false
    }

    /// 落地分两步:先插原话,再换成整理后的文字(各算一次编辑,一次撤销回到原话)。插不进去就留在 `held` 里。
    private func land(_ sid: AnyHashable, _ text: String, _ ai: VoiceAi?) {
        guard let controller, let id = sid as? String, id == controller.pageID else {
            unlanded = text
            return
        }
        if let refused = controller.insertVoice(ai?.original ?? text) {
            unlanded = text
            onNotice?(refused, .none)
            return
        }
        landed = true
        guard let ai else { return }
        if controller.replaceVoice(original: ai.original, with: ai.result) { onNotice?(Self.tidiedNotice, .none) }
    }

    /// VoiceTidy 的 `held`:等着的字存进这一页的文件;落地后(nil)删掉,没能落地的留下。
    private func keepHeld(_ sid: AnyHashable, _ text: String?) {
        let left = unlanded
        unlanded = nil
        guard let id = sid as? String, !id.isEmpty else { return }
        held.set(id, text ?? left)
    }

    /// 打开一页时(启动、切页):这一页上次留下没插入的语音接到页末。整理卡正为这一页等着时不动。
    func restoreHeld(_ id: String? = nil) {
        guard let controller, let id = id ?? controller.pageID else { return }
        if tidyBusy && tidy.sid == AnyHashable(id) { return }
        guard let text = held.take(id) else { return }
        if let refused = controller.appendVoice(text) {
            held.set(id, text)
            onNotice?(refused, .none)
            return
        }
        onNotice?(Self.restoredNotice, .none)
    }

    private static func heldDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("voice-held", isDirectory: true)
    }

    // MARK: 麦克风按钮

    /// 手指按下或移动;`point` 与这次触摸的起点 `start` 是窗口坐标(`DragGesture` 的 `.global`)。
    func finger(at point: CGPoint, start: CGPoint) {
        if start == fingerStart {
            if fingerDown { hold.move(to: point) }
            return
        }
        fingerStart = start
        // 键盘说话中按到麦克风:取消那次说话,不插入,也不开始新的一次。
        if keyboardHolding {
            Task { await hold.cancel() }
            return
        }
        fingerDown = true
        landTidy()
        guard let window = controller?.viewIfLoaded?.window else { return }
        attach(to: window)
        let stage = window.bounds.size
        // 麦克风在底栏右端:圆盘向左上长开。
        Task { await hold.down(thumb: point, stage: stage, right: true) }
    }

    /// 手指松开:按当前的选择插入、插入原话或取消。
    func fingerUp() {
        fingerStart = nil
        if keyboardHolding {
            Task { await hold.cancel() }
            return
        }
        guard fingerDown else { return }
        fingerDown = false
        Task { await hold.up() }
    }

    /// 系统抢走了触点(手势被取消)、来电、退到后台:按取消处理,已说出的字不插入。
    func interrupt() {
        fingerDown = false
        fingerStart = nil
        accessibilityOn = false
        // 离开前台时按着的键可能等不到松开:门限也忘掉它们(rapp 的 resign)。
        controller?.voiceKeyResign()
        Task { await hold.cancel() }
    }

    /// 手势结束时若没走到 `fingerUp`(被系统取消),当作打断。
    func fingerGone() {
        if fingerDown { interrupt() } else { fingerStart = nil }
    }

    /// 长按右 ⌥ 的一次说话正在录音。
    private var keyboardHolding: Bool { hold.keyboard && hold.holding }

    /// VoiceOver:双击开始,再双击结束(插入)。没有手指,不画圆盘,只画气泡。
    func accessibilityToggle() {
        if accessibilityOn {
            accessibilityOn = false
            Task { await hold.finish(.send) }
            return
        }
        accessibilityOn = true
        landTidy()
        if let window = controller?.viewIfLoaded?.window { attach(to: window) }
        Task {
            await hold.start()
            // 被拒绝、请求授权、没能开始:下一次双击重新开始。
            if !hold.holding { accessibilityOn = false }
        }
    }

    // MARK: 实体键盘(长按右 ⌥)

    /// 没有别的说话在进行:手指、VoiceOver、上一次说话都结束了。
    private var idle: Bool {
        !fingerDown && !accessibilityOn && !hold.holding && voice.phase == .idle
    }

    /// 编辑面的门限给出的阶段(ios.md §3.8「入口」)。键盘路径没有圆盘,只画气泡与 `keyboardHint`。
    private func key(_ phase: VoiceKeyPhase) {
        switch phase {
        case .start:
            landTidy()
            if let window = controller?.viewIfLoaded?.window { attach(to: window) }
            Task {
                await hold.start()
                // 被拒绝、请求授权、没能开始:门限吞掉余下的键,直到右 ⌥ 松开(rapp `voiceEnd`)。
                if !hold.holding { controller?.voiceKeyEnded() }
            }
        case .release: Task { await hold.finish(.send) }
        case .cancel: Task { await hold.finish(.cancel) }
        case .edit: Task { await hold.finish(.edit) }
        }
    }

    /// 「去设置」:语音权限与识别语言都只能在系统设置里改,iOS 只开得到本应用的设置页。
    func openSettings(_ settings: VoiceSettings) {
        guard settings != .none, let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 提示条显示多久(秒):VoiceKit 给的时长;带「去设置」时至少 4 s。
    static func noticeLife(_ text: String, settings: VoiceSettings) -> Double {
        if text == tidiedNotice { return 1.5 }
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
        // 说话期间系统输入法开始了组字:不插入,提示。
        if let refused = controller?.insertVoice(text) { onNotice?(refused, .none) } else { landed = true }
    }

    func voiceNotice(_ text: String, settings: VoiceSettings) {
        onNotice?(text, settings)
    }

    func voiceDidEnd(_ pick: VoicePick?) {
        accessibilityOn = false
        // 手指的这次按下结束了(包括手势无声无息地没了、5 分钟上限):不再算按着,下一次触摸能开始。
        if !hold.keyboard { fingerDown = false }
        // 键盘的这次从别处结束(5 分钟上限、打断):门限吞掉余下的键,直到右 ⌥ 松开。
        controller?.voiceKeyEnded()
        // 没走到录音(请求授权、被拒绝、轻点)时不会有 `restoreAudio`:在这里收回。
        if yielded { reclaimAudio() }
        // 整理卡接走了字时等卡收起再换回(`tidy.$phase`)。
        DispatchQueue.main.async { [weak self] in self?.settleKeyboard() }
    }

    private func reclaimAudio() {
        yielded = false
        sound?.reclaimSession()
    }
}
