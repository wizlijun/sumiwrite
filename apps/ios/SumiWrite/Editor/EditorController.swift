import Combine
import GameController
import os
import RimeKitUI
import UIKit
import VoiceKit

/// 编辑面:文本视图、自绘光标、键盘避让、聚焦打字、硬件键盘命令、保存接线。
/// 文字的增删、粘贴、撤销都经 `PageModel` 交给内核;样式来自内核的样式段,经 `Styler` 映射。
/// 交互细节照搬原型(设计 §5.3)。
final class EditorController: UIViewController, UITextViewDelegate {
    let textView = SumiTextView()
    /// 硬件键盘命令与「正在打字」;由外壳接。
    var onCommand: ((EditorCommand) -> Void)?
    /// 时钟;测试注入。
    var now: () -> Date = { Date() }
    /// 长按右 ⌥ 门限的时钟(开机以来的秒数,改系统时间不影响它);测试注入。
    var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// `nil`、`保存失败` 或 `打不开纸页`。
    private(set) var statusText: String? {
        didSet { if statusText != oldValue { onStatusChange?(statusText) } }
    }
    /// `statusText` 变化时通知外壳显示。
    var onStatusChange: ((String?) -> Void)?
    /// 最近一次应用的偏好(来自 `PrefsModel`)。
    private(set) var prefs: EditorPrefs

    private var page: CorePage?
    /// 强引用:`PageModel` 只弱持有它的 sink,这里不留住它,保存就会悄悄丢掉。
    private let persistence: PagePersistence?
    private var model: PageModel?
    private let prefsModel: PrefsModel
    private let selectionStore: SelectionStore
    private let sound: TypingSoundPlaying?
    /// 实体键盘的内嵌输入法(ios.md §3.6);没接输入法时为 nil,编辑面照旧只走系统输入。
    private(set) var rimeAdapter: RimeTextViewAdapter?
    /// 大于 0:正在调适配器(按键、上屏、焦点变化),这期间文字变化不按文字另响打字音。
    private var rimeQuiet = 0
    /// 大于 0:这期间的上屏不算打字(不发声、不发 typing、不进聚焦打字),如切页前、变成只读时。
    private var rimeAside = 0
    /// 大于 0:正在处理候选行上的点按(选字、翻页),引擎随之上屏算一次打字。
    private var rimeTap = 0
    /// 被内嵌输入法吞下、还没松开的键;按住时引擎自己连发的上屏算打字。
    private var rimeHeld = Set<ObjectIdentifier>()
    private var rimeProbe: RimeLandingProbe?

    /// 实体键盘长按右 ⌥ 说话的门限(ios.md §3.8「入口」):每个按键在内嵌输入法之前先过它。
    private(set) var voiceKeys = VoiceKeyGate()
    /// 门限给出的阶段(开始、松开插入、取消、插入原话);由 `VoiceHost` 接。
    var onVoiceKey: ((VoiceKeyPhase) -> Void)?
    /// 宿主现在能开始一次说话(没有别的说话在进行)。没接宿主时为 nil,右 ⌥ 照常往下传。
    var voiceKeyReady: (() -> Bool)?
    /// 门限吞下、还在等长按的右 ⌥ 按下;放行(flush)时补交给内嵌输入法与系统。
    private var voiceKeyHeld: UIPress?
    /// 右 ⌥ 按住 `VoiceKeyGate.holdDelay` 后喂门限 `.elapsed`。
    private var voiceKeyTimer: DispatchWorkItem?
    /// AI 整理卡还在(ios.md §3.8「AI 整理」):按下任何键之前先调 `onVoiceTidyKey` 让卡上的字落地。由 `VoiceHost` 接。
    var voiceTidyBusy: (() -> Bool)?
    var onVoiceTidyKey: (() -> Void)?
    /// 换到另一页之后(`show(page:)`),带新页的 id;`VoiceHost` 在这里放回上次没插入的语音。
    var onPageShown: ((String) -> Void)?
    /// `insertVoice` 刚插入的那段(插入后的位置),给紧接着的 `replaceVoice` 用。
    private var voiceSpan: NSRange?

    private let container = UIView()
    private let cursorView = SumiCursorView()
    private let fadeMask = CAGradientLayer()
    private var bag = Set<AnyCancellable>()
    private static let log = Logger(subsystem: "SumiWrite", category: "editor")

    // 聚焦打字状态
    private var tracker = FocusTypingTracker()
    private var focusMode = false
    private var faded = false
    private var inEdit = false
    private var arrowNav = false
    private var pendingInsetReset = false
    private var idleTimer: Timer?
    private var lastCaretLine: CGFloat = -1
    private var lastEditTime = Date.distantPast
    private var editSelection = NSRange(location: NSNotFound, length: 0)
    /// 这次改动已由 `shouldChangeTextIn` 处理过打字音;不经代理的改动(内嵌输入法上屏、听写)由 `textViewDidChange` 补响。
    private var delegateSaw = false
    /// 程序正在改文字或选区;这期间的代理回调不算用户动作。
    private var applyingProgrammaticChange = false
    private var didInitialScroll = false

    private static let focusEnter: CFTimeInterval = 0.2
    private static let focusIdle: TimeInterval = 10
    private static let focusRestore: CFTimeInterval = 1.2

    /// `persistence` 或 `page` 为 nil 表示打开失败,编辑面只读。`rime` 是进程里唯一的内嵌输入法,
    /// 「内/系」的选择记在 `rimeDefaults`。
    init(persistence: PagePersistence?, page: CorePage?, prefs: PrefsModel, selection: SelectionStore,
         sound: TypingSoundPlaying?, rime: RimeInputDriving? = nil, rimeDefaults: UserDefaults = .standard) {
        prefsModel = prefs
        selectionStore = selection
        self.sound = sound
        self.prefs = prefs.prefs
        if let persistence, let page {
            self.persistence = persistence
            self.page = page
            model = PageModel(page: page, sink: persistence)
            statusText = nil
        } else {
            self.persistence = nil
            self.page = nil
            model = nil
            statusText = "打不开纸页"
        }
        super.init(nibName: nil, bundle: nil)
        self.persistence?.onFailure = { [weak self] message in self?.saveFailed(message) }
        textView.coreUndoManager = makeUndoManager()
        textView.pressHandler = self
        if let rime { attachRime(rime, defaults: rimeDefaults) }
        // 失焦时门限忘掉按着的键(说话中就取消);点按正文:等长按时右 ⌥ 算修饰键,说话中取消(rapp 的 pointer)。
        let rimeFocus = textView.onFocusChange
        textView.onFocusChange = { [weak self] focused in
            if !focused { self?.voiceKeyResign() }
            rimeFocus?(focused)
        }
        let rimeTouch = textView.onTouchBegan
        textView.onTouchBegan = { [weak self] modifiers in
            self?.voiceKeyFeed(.pointer)
            rimeTouch?(modifiers)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    /// 系统输入法组字中不切页;内置输入法的组字可以,切之前由 `prepareToSwitch` 上屏。
    var canSwitchPage: Bool { textView.markedTextRange == nil || rimeAdapter?.isComposing == true }

    /// 切页、开总览、开设置之前调用:内置输入法的组字按原文上屏进内核(不发打字音)。
    func prepareToSwitch() {
        aside { rimeAdapter?.flush() }
    }

    /// 设置面板「复制全文」的按钮是否置灰;面板每次重算都问,所以不跨 FFI。
    var pageIsEmpty: Bool { textView.textStorage.length == 0 }

    /// 设置面板「复制全文」:正文的 Markdown 原文(ios.md §3.5.1)。内置输入法的组字先上屏;系统输入法组字中返回 nil。
    func pageTextForCopy() -> String? {
        prepareToSwitch()
        guard canSwitchPage else { return nil }
        return model?.markdown ?? ""
    }

    /// 「已复制 N 字」的 N:可见文本的字符数,不算转义用的 `\`。
    var pageCharacterCount: Int { textView.text.count }

    // MARK: 语音输入(ios.md §3.8)

    /// 纸页可写:麦克风按钮可用。打开失败、保存失败时为 false。
    var voiceAvailable: Bool { model?.isWritable == true && textView.isEditable }

    /// 每次按下、开始识别之前:系统输入法组字中、纸页不可写时返回要提示的话;否则内置输入法的组字先按原文上屏
    /// (同切页前,不发打字音),返回 nil。
    func voiceWillStart() -> String? {
        if !canSwitchPage { return "请先完成输入" }
        if !voiceAvailable { return "这一页现在不能写" }
        prepareToSwitch()
        return nil
    }

    /// 语音的结果:替换选区,经 `PageModel.userEdited` 交给内核(按键入的文字转义,`#`、`*` 不成标记)。
    /// 结构同 `paste`:不经文本视图的输入代理、不播打字音;算一次编辑(聚焦打字、保存),之后把光标滚进视野。
    /// 说话期间内置输入法又开始组字:先按原文上屏。插不进去(系统输入法组字中、纸页不可写)时返回要提示的话。
    @discardableResult
    func insertVoice(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        guard let model, model.isWritable else { return "这一页现在不能写" }
        prepareToSwitch()
        guard textView.markedTextRange == nil else { return "请先完成输入" }
        let range = textView.selectedRange
        // 没有选区:字没进纸页,交回提示,调用方留着它(TidyHeld)。
        guard range.location != NSNotFound else { return "这一页现在不能写" }
        let visible = ((textView.text ?? "") as NSString).replacingCharacters(in: clamped(range), with: text)
        let start = clamped(range).location
        let caret = start + (text as NSString).length
        voiceSpan = nil
        switch model.userEdited(visible: visible, composing: false, caret: caret) {
        case .unchanged: return nil
        case .accepted(let rendered, let caret):
            show(rendered, caret: caret)
            registerInput()
            if caret >= start { voiceSpan = NSRange(location: start, length: caret - start) }
        case .rejected(let rendered, let caret):
            // 内核没收下:字没进纸页,交回提示,调用方留着它(TidyHeld)。
            reset(to: rendered, caret: caret)
            return "这一页现在不能写"
        }
        markEdited()
        revealCaret()
        return nil
    }

    /// AI 整理落地的第二步(ios.md §3.8「AI 整理」):把 `insertVoice` 刚插入的原话换成整理后的文字,单独算一次编辑,
    /// 所以一次撤销回到原话。那段已经不是 `original`(中间改过字)、内核没收下时什么也不换,返回 false。
    @discardableResult
    func replaceVoice(original: String, with text: String) -> Bool {
        guard let span = voiceSpan, let model, model.isWritable, textView.markedTextRange == nil else { return false }
        voiceSpan = nil
        let current = (textView.text ?? "") as NSString
        guard NSMaxRange(span) <= current.length, current.substring(with: span) == original else { return false }
        let visible = current.replacingCharacters(in: span, with: text)
        let caret = span.location + (text as NSString).length
        switch model.userEdited(visible: visible, composing: false, caret: caret) {
        case .unchanged: return false
        case .accepted(let rendered, let caret): show(rendered, caret: caret)
        case .rejected(let rendered, let caret):
            reset(to: rendered, caret: caret)
            return false
        }
        markEdited()
        revealCaret()
        return true
    }

    /// 上次没插入的语音放回本页末尾(ios.md §3.8「AI 整理」):前面有字时先另起一行。算一次编辑,光标随之到文末。
    /// 插不进去时返回要提示的话。
    @discardableResult
    func appendVoice(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        guard let model, model.isWritable else { return "这一页现在不能写" }
        prepareToSwitch()
        guard textView.markedTextRange == nil else { return "请先完成输入" }
        let current = textView.text ?? ""
        let joined = current.isEmpty || current.hasSuffix("\n") ? current + text : current + "\n" + text
        let caret = (joined as NSString).length
        switch model.userEdited(visible: joined, composing: false, caret: caret) {
        case .unchanged: return nil
        case .accepted(let rendered, let caret): show(rendered, caret: caret)
        case .rejected(let rendered, let caret):
            reset(to: rendered, caret: caret)
            return "这一页现在不能写"
        }
        markEdited()
        revealCaret()
        return nil
    }

    /// 当前纸页的 id;打不开纸页时为 nil。
    var pageID: String? { page?.pageId() }

    /// 门限计时到点:右 ⌥ 一直单独按着就开始说话。测试直接调用,不等 0.3 s。
    func voiceKeyElapsed() {
        voiceKeyTimer?.cancel()
        voiceKeyTimer = nil
        voiceKeyFeed(.elapsed)
    }

    /// 编辑面失去键盘(失焦、离开前台):门限忘掉按着的键,说话中就取消;吞下的右 ⌥ 不再交出去。
    /// rapp gui/macos/Runner/SessionPlugin.swift 的 resign 观察者。
    func voiceKeyResign() {
        voiceKeyFeed(.resign)
        voiceKeyHeld = nil
        voiceKeyTimer?.cancel()
        voiceKeyTimer = nil
    }

    /// 一次说话从别处结束了(5 分钟上限、打断、没能开始):门限吞掉之后的键,直到右 ⌥ 松开。rapp `voiceEnd`。
    func voiceKeyEnded() {
        _ = voiceKeys.handle(.ended, at: uptime(), ready: false)
    }

    /// 开始录音时收起软键盘(ios.md §3.8「软键盘」):换上一块空的输入视图,文本视图仍是第一响应者,
    /// 选区、焦点与实体键盘的按键都不变。接着实体键盘时没有软键盘可收,不动。
    func hideKeyboardForVoice() {
        guard textView.isFirstResponder, textView.inputView == nil, GCKeyboard.coalesced == nil else { return }
        textView.inputView = UIView(frame: .zero)
        textView.reloadInputViews()
    }

    /// 语音结束(ios.md §3.8「软键盘」):换回系统键盘。`landed` 为 true(字落进了纸页)时编辑面取得焦点:
    /// 没接实体键盘时软键盘随之展开,接着时系统不弹软键盘。为 false(取消、没听清、没能插入)时回到说话前的样子。
    func restoreKeyboardAfterVoice(landed: Bool) {
        if textView.inputView != nil {
            textView.inputView = nil
            textView.reloadInputViews()
        }
        if landed, voiceAvailable, !textView.isFirstResponder { textView.becomeFirstResponder() }
    }

    // MARK: 视图

    override func viewDidLoad() {
        super.viewDidLoad()

        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            keyboardBottom,
        ])

        textView.frame = container.bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.backgroundColor = .clear
        textView.delegate = self
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = true
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInsetAdjustmentBehavior = .never
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.inlinePredictionType = .no
        textView.onArrow = { [weak self] in self?.arrowNav = true }
        textView.pasteHandler = { [weak self] in self?.paste($0) }
        container.addSubview(textView)

        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        container.layer.mask = fadeMask

        // 候选行是文本视图的兄弟、在最上层,不在渐隐遮罩里;点按不会被文本视图的手势接走。
        if let bar = rimeAdapter?.bar { view.addSubview(bar) }

        loadPage()

        // `$prefs` 在 willSet 时发值,所以用发来的值而不是回读模型;订阅时先发一次当前值。
        prefsModel.$prefs
            .sink { [weak self] p in
                guard let self, let ok = p.validated() else { return }
                self.prefs = ok
                self.applyPrefs()
            }
            .store(in: &bag)

        installCursor()

        if #available(iOS 27.1, *) {
            let observer = DeskObserver(view: view) { [weak self] in self?.updateDesk(inLayout: false) }
            desk = observer
            deskProbe = { [weak self, unowned observer] in
                guard let self else { return nil }
                // 只在转轴半开时才查折痕:没有转轴的机型上每次布局都不多做一次查询。
                let divisions = observer.hinge == .partiallyOpen ? observer.divisions(in: self.view) : []
                return DeskPosture.foldTop(hinge: observer.hinge, divisions: divisions, bounds: self.view.bounds)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installCursor()
        focusEditor()
        if ProcessInfo.processInfo.arguments.contains("-SumiDemo") { runDemo() }
    }

    /// 仅供模拟器自测:按真实输入路径逐字敲入一段文字,用来检查排版、聚焦与渐隐。
    private func runDemo() {
        let lines = [
            "夜里十一点，窗外的雨还没有停。",
            "I keep the lamp low and the page quiet.",
            "这一页只写今天想清楚的一件事：先把交接文档写完，再动代码。",
            "Typewriter mode keeps the current line in the middle.",
            "上下文一行一行地淡出去，只留下正在写的这一行。",
            "The cursor breathes, slowly, like someone thinking.",
            "明天再看这一页，也许会改掉一半。",
            "But tonight it is enough to have written it down.",
            "最后一行，写在屏幕正中间。",
        ]
        let text = Array(lines.joined(separator: "\n"))
        var i = 0
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, i < text.count else { t.invalidate(); return }
                self.textView.insertText(String(text[i]))
                i += 1
            }
        }
    }

    // MARK: iPhone Duo 半折打字(ios.md §3.7)

    /// 普通布局:正文区底边贴键盘顶边。半折时停用,换成下面两条。
    private lazy var keyboardBottom = container.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
    /// 半折:正文区底边贴折痕顶……
    private lazy var foldBottom: NSLayoutConstraint = {
        let c = container.bottomAnchor.constraint(equalTo: view.topAnchor)
        c.priority = UILayoutPriority(999)
        return c
    }()
    /// ……但不低于键盘顶边。
    private lazy var keyboardCap = container.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor)
    /// `DeskObserver`;存成 `AnyObject` 免得整个类带上 iOS 27.1 的可用性。其他机型与旧系统上为 nil。
    private var desk: AnyObject?
    /// 当前该用的折痕顶(编辑面坐标),nil 表示普通布局。iOS 27.1 起由 `DeskObserver` 提供;
    /// 旧系统上为 nil,半折代码整段不跑。测试换成固定值,在没有转轴的模拟器上验证半折布局。
    var deskProbe: (() -> CGFloat?)?
    /// 当前的折痕顶(编辑面坐标);不在半折布局时为 nil。
    private(set) var deskFoldTop: CGFloat?
    /// 进出半折时通知外壳画底座:折痕顶的窗口 y 坐标,离开半折时为 nil。
    var onDeskChange: ((CGFloat?) -> Void)?

    /// 转轴变化时(`inLayout` 为 false)动画到新布局;布局过程中(旋转、换窗口大小)只换约束,随下一遍布局到位。
    func updateDesk(inLayout: Bool) {
        guard let deskProbe else { return }
        let top = deskProbe()
        switch (deskFoldTop, top) {
        case (nil, nil): return
        case let (old?, new?) where abs(old - new) < 0.5: return
        default: break
        }
        let entering = deskFoldTop == nil
        deskFoldTop = top
        if let top {
            foldBottom.constant = top
            keyboardBottom.isActive = false
            NSLayoutConstraint.activate([foldBottom, keyboardCap])
        } else {
            NSLayoutConstraint.deactivate([foldBottom, keyboardCap])
            keyboardBottom.isActive = true
        }
        if inLayout {
            view.setNeedsLayout()
        } else if reduceMotion || view.window == nil {
            view.layoutIfNeeded()
        } else {
            UIView.animate(withDuration: 0.25, delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
                self.view.layoutIfNeeded()
            }
        }
        if top != nil && entering { focusEditor() }
        onDeskChange?(top.map { view.convert(CGPoint(x: 0, y: $0), to: nil).y })
    }

    override func viewDidLayoutSubviews() {
        updateDesk(inLayout: true)
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = container.bounds
        CATransaction.commit()
        layoutTextInsets()
        if focusMode {
            setFocusInsets()
            updateFade(duration: 0)
            centerCaret(animated: false)
        } else {
            updateFade(duration: 0)
        }
        if !didInitialScroll && textView.bounds.height > 0 {
            didInitialScroll = true
            textView.layoutIfNeeded()
            textView.scrollRangeToVisible(textView.selectedRange)
        }
        placeRimeBar(reveal: false)
    }

    func focusEditor() {
        if textView.isEditable && !textView.isFirstResponder { textView.becomeFirstResponder() }
    }

    private func loadPage() {
        guard let model, let page else {
            textView.isEditable = false
            return
        }
        programmatic {
            textView.textStorage.setAttributedString(NSAttributedString(string: model.rendered.text, attributes: baseAttributes))
            restyle()
            // 启动时恢复上次的光标(spec §1);切页另见 `show(page:)`。
            textView.selectedRange = clamped(selectionStore.restore(page: page))
        }
    }

    // MARK: 光标

    private func installCursor() {
        guard let sel = textView.interactions.compactMap({ $0 as? UITextSelectionDisplayInteraction }).first else {
            Self.log.error("UITextSelectionDisplayInteraction not found")
            return
        }
        if sel.cursorView !== cursorView { sel.cursorView = cursorView }
    }

    // MARK: 外观

    private var baseFont: UIFont { prefs.font.uiFont(size: CGFloat(prefs.fontSize)) }
    private var baseAttributes: [NSAttributedString.Key: Any] { Styler.base(prefs: prefs, baseFont: baseFont) }
    private var lineHeight: CGFloat { baseFont.lineHeight * CGFloat(prefs.lineSpacing) }

    private func applyPrefs() {
        let theme = prefs.theme
        view.backgroundColor = theme.background
        textView.tintColor = theme.foreground
        textView.keyboardAppearance = theme.isDark ? .dark : .light
        cursorView.color = theme.foreground
        cursorView.breathing = prefs.caretMotion == .breathing
        sound?.preferencesChanged(prefs)
        rimeAdapter?.bar.style = .sumi(prefs)
        rimeAdapter?.switchShortcut = prefs.switchShortcut
        setVoiceHotkey(prefs.voiceKey ? .standard : .off)

        // 组字中不重设属性;下一次被接受的输入会重设。
        if textView.markedTextRange == nil {
            let sel = textView.selectedRange
            programmatic {
                restyle()
                if sel.location != NSNotFound { textView.selectedRange = clamped(sel) }
            }
        }

        if !prefs.focusTyping && focusMode { exitFocus() }
        view.setNeedsLayout()
        // 字号变了,候选行的高度、位置和底部留白跟着变;适配器不会因为换样式而通知。
        placeRimeBar(reveal: false)
    }

    /// 重设属性:全文应有的属性是基础样式再按内核的样式段(已是互不重叠的平铺段)依次叠加;先在副本上算出来,
    /// 只对与 textStorage 现有属性不同的区段 `setAttributes`。结果与全文重设相同,TextKit 2 只作废真正变了的段落
    /// (ios.md §3.3「TextKit 2 的估算高度」)。换主题、字体、字号时每段都不同,就是全文重设。
    private func restyle() {
        let storage = textView.textStorage
        let base = baseAttributes
        let whole = NSRange(location: 0, length: storage.length)
        let target = NSMutableAttributedString(string: storage.string, attributes: base)
        if let r = model?.rendered, r.text == target.string {
            for (range, attrs) in Styler.attributes(for: r, prefs: prefs, baseFont: baseFont) {
                target.addAttributes(attrs, range: range)
            }
        }
        storage.beginEditing()
        target.enumerateAttributes(in: whole) { attrs, range, _ in
            var current = NSRange(location: NSNotFound, length: 0)
            let have = storage.attributes(at: range.location, longestEffectiveRange: &current, in: range)
            if current == range, (have as NSDictionary).isEqual(to: attrs) { return }
            storage.setAttributes(attrs, range: range)
        }
        storage.endEditing()
        textView.typingAttributes = base
    }

    /// 四周留白随字号缩放(04「留白随字号缩放」),正文最大 80 列。
    private func layoutTextInsets() {
        let w = container.bounds.width, h = container.bounds.height
        guard w > 0, h > 0 else { return }
        let f = baseFont
        let s = f.pointSize / 22
        let side = min(max(16, 24 * s), w / 4)
        let vertical = min(max(20, 32 * s), h / 4)
        let column = ("0" as NSString).size(withAttributes: [.font: f]).width
        let body = min(w - 2 * side, 80 * column)
        let x = max(side, (w - body) / 2)
        let inset = UIEdgeInsets(top: vertical, left: x, bottom: vertical, right: x)
        if textView.textContainerInset != inset { textView.textContainerInset = inset }
    }

    // MARK: 纸页

    /// 换到另一页:存旧页光标,重建页面模型与撤销,光标放到文末(设计 §6),退出聚焦。
    func show(page newPage: CorePage) {
        guard let persistence else { return }
        saveSelection()
        let writable = model?.isWritable ?? true
        exitFocus(resetInsetsNow: true)
        tracker.reset()
        page = newPage
        let m = PageModel(page: newPage, sink: persistence)
        m.isWritable = writable
        model = m
        textView.coreUndoManager = makeUndoManager()
        programmatic {
            textView.textStorage.setAttributedString(NSAttributedString(string: m.rendered.text, attributes: baseAttributes))
            restyle()
            // 进入后从文末续写
            textView.selectedRange = NSRange(location: textView.textStorage.length, length: 0)
            textView.layoutIfNeeded()
            textView.scrollRangeToVisible(textView.selectedRange)
        }
        editSelection = NSRange(location: NSNotFound, length: 0)
        lastEditTime = .distantPast
        lastCaretLine = -1
        voiceSpan = nil
        onPageShown?(newPage.pageId())
    }

    private func makeUndoManager() -> CoreUndoManager {
        CoreUndoManager(
            canUndo: { [weak self] in self?.historyAvailable(redo: false) ?? false },
            canRedo: { [weak self] in self?.historyAvailable(redo: true) ?? false },
            undo: { [weak self] in self?.performHistory(redo: false) },
            redo: { [weak self] in self?.performHistory(redo: true) })
    }

    // MARK: 输入

    /// 所有用户输入(软键盘、拼音预编辑、硬件键盘)都经过这里;以此判定按键种类。粘贴另走 `paste`。
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard !applyingProgrammaticChange else { return true }
        let kind: KeyKind
        // 组字中:替换成更短、且是原拼音前缀的串 = 退格;替换成汉字 = 选字上屏,算普通键。
        let marked = textView.markedTextRange.flatMap { textView.text(in: $0) } ?? ""
        if text.isEmpty || (!marked.isEmpty && (text as NSString).length < range.length && marked.hasPrefix(text)) {
            kind = .delete
        } else if text == "\n" {
            kind = .enter
        } else if text == " " {
            kind = .space
        } else {
            kind = .key
        }
        // 记下这次输入后光标应在的位置:随后到达的选区通知若与之相符,就不算「挪光标」。
        editSelection = NSRange(location: range.location + (text as NSString).length, length: 0)
        lastEditTime = now()
        if !rimeCommitAside {
            delegateSaw = true
            keyPressed(kind)
            // 打字音在文字改动之前就排进声音队列(ios.md §3.4「发声时机」);文字不会变的不响(如文首退格)。
            if rimeQuiet == 0, model?.isWritable == true, textView.isEditable,
               range.length > 0 || !text.isEmpty,
               range.length == 0 || !Self.keepsText(textView.textStorage, range, text) {
                sound?.play(kind: kind)
            }
        }
        return true
    }

    /// 这次替换会不会原样换回同样的字;只看被替换的那一段,不复制全文。
    private static func keepsText(_ storage: NSTextStorage, _ range: NSRange, _ text: String) -> Bool {
        NSMaxRange(range) <= storage.length && (storage.string as NSString).substring(with: range) == text
    }

    private func keyPressed(_ kind: KeyKind) {
        inEdit = true
        onCommand?(.typing)
        DispatchQueue.main.async { [weak self] in self?.afterEdit() }
    }

    private func afterEdit() {
        if focusMode { centerCaret(animated: true) }
        inEdit = false
        // 代理放行了但文字没变(如文首退格):不让这次挡掉下一次不经代理的改动。
        delegateSaw = false
    }

    func textViewDidChange(_ textView: UITextView) {
        guard let model, !applyingProgrammaticChange else { return }
        let composing = textView.markedTextRange != nil
        let visible = textView.text ?? ""
        let aside = rimeCommitAside
        let saw = delegateSaw
        delegateSaw = false
        let sel = textView.selectedRange
        let caret = sel.location == NSNotFound ? (visible as NSString).length : NSMaxRange(sel)
        switch model.userEdited(visible: visible, composing: composing, caret: caret) {
        case .unchanged:
            // 拼音预编辑也算真实输入(04「聚焦打字」),但不提交、不重设。
            if composing && !aside { registerInput() }
        case .accepted(let rendered, let caret):
            // 不经代理的改动没有按下的时刻,只能在文字变了之后响;一律按普通键。
            if !saw, !aside, rimeQuiet == 0, textView.isEditable { sound?.play(kind: .key) }
            show(rendered, caret: caret)
            if !aside { registerInput() }
        case .rejected(let rendered, let caret):
            reset(to: rendered, caret: caret)
        }
        if !aside { markEdited() }
        placeRimeBar(reveal: true)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        self.textView.layoutThroughCaret()
        placeRimeBar(reveal: !applyingProgrammaticChange)
        guard !applyingProgrammaticChange, textView.markedTextRange == nil else { return }
        // 外置键盘下,选区通知会晚于文字变更到达;紧随输入的选区变化不算「挪光标」。
        let followsEdit = textView.selectedRange == editSelection
            || now().timeIntervalSince(lastEditTime) < 0.5
        // 内嵌输入法落下更新时(上屏、清掉组字、换成系统输入法)的选区变化是它挪的,不是用户:清掉组字时 UIKit
        // 不经 `shouldChangeTextIn`,光标退回组字之前,与记下的位置不符。
        let fromRime = (rimeProbe?.landing ?? 0) > 0
        if inEdit || arrowNav || followsEdit || fromRime {
            arrowNav = false
            if focusMode { DispatchQueue.main.async { [weak self] in self?.centerCaret(animated: true) } }
            return
        }
        // 用户移动了光标:回到普通页面
        if focusMode { exitFocus() }
    }

    /// 文字刚由输入、粘贴或撤销改过:随后到达的选区通知算跟着输入走。
    private func markEdited() {
        lastEditTime = now()
        editSelection = textView.selectedRange
        DispatchQueue.main.async { [weak self] in self?.afterEdit() }
    }

    private func paste(_ markdown: String) {
        guard let model, textView.markedTextRange == nil else { return }
        let range = textView.selectedRange
        guard range.location != NSNotFound else { return }
        switch model.paste(markdown: markdown, range: range) {
        case .unchanged: return
        case .accepted(let rendered, let caret): show(rendered, caret: caret)
        case .rejected(let rendered, let caret): reset(to: rendered, caret: caret)
        }
        markEdited()
        revealCaret()
    }

    /// 粘贴、撤销、重做由内核改字,`UITextView` 不会替它们把光标滚进可见区(打字时是它在插入时滚的):
    /// 不在聚焦打字时自己滚一次;聚焦时由 `afterEdit` 居中。`programmatic` 已排到光标,滚动目标是实值。
    private func revealCaret() {
        guard !focusMode else { return }
        textView.scrollRangeToVisible(textView.selectedRange)
    }

    // MARK: 撤销与重做

    private func historyAvailable(redo: Bool) -> Bool {
        guard let model, model.isWritable, textView.markedTextRange == nil else { return false }
        return redo ? model.canRedo : model.canUndo
    }

    private func performHistory(redo: Bool) {
        guard let model, textView.markedTextRange == nil else { return }
        switch redo ? model.redo() : model.undo() {
        case .unchanged: return
        case .accepted(let rendered, let caret): show(rendered, caret: caret)
        case .rejected(let rendered, _):
            // 内核在拒绝时不知道光标;保留当前选区,只夹到文本长度内。
            let length = (rendered.text as NSString).length
            let sel = textView.selectedRange
            reset(to: rendered, caret: sel.location == NSNotFound ? length : min(sel.location, length))
        }
        markEdited()
        revealCaret()
    }

    // MARK: 把内核结果放到编辑面

    /// 被接受:文字相同只重设属性;不同就按可见文本的差异(锚在结果光标上)对 textStorage 做最小替换。
    /// 文字没有替换、视图选区又已经止于结果光标时,不动选区:那就是用户的真实光标。
    private func show(_ rendered: RenderedText, caret: Int) {
        programmatic {
            let storage = textView.textStorage
            var replaced = false
            if storage.string != rendered.text,
               let edit = EditDiff.between(storage.string, rendered.text, caret: caret) {
                storage.replaceCharacters(in: edit.range,
                                          with: NSAttributedString(string: edit.replacement, attributes: baseAttributes))
                replaced = true
            }
            restyle()
            let sel = textView.selectedRange
            if replaced || sel.location == NSNotFound || NSMaxRange(sel) != caret {
                textView.selectedRange = clamped(NSRange(location: caret, length: 0))
            }
        }
    }

    /// 被拒绝:整段重置为内核文本。
    private func reset(to rendered: RenderedText, caret: Int) {
        programmatic {
            textView.textStorage.setAttributedString(NSAttributedString(string: rendered.text, attributes: baseAttributes))
            restyle()
            textView.selectedRange = clamped(NSRange(location: caret, length: 0))
        }
    }

    private func programmatic(_ body: () -> Void) {
        let was = applyingProgrammaticChange
        applyingProgrammaticChange = true
        body()
        // 这里改过文字或属性:排到光标为止,ios.md §3.3「TextKit 2 的估算高度」。
        textView.layoutThroughCaret()
        applyingProgrammaticChange = was
    }

    private func clamped(_ r: NSRange) -> NSRange {
        let length = textView.textStorage.length
        guard r.location != NSNotFound else { return NSRange(location: length, length: 0) }
        let start = min(max(r.location, 0), length)
        return NSRange(location: start, length: min(max(r.length, 0), length - start))
    }

    // MARK: 保存

    private func saveFailed(_ message: String) {
        model?.isWritable = false
        textView.isEditable = false
        // 只读的编辑面不接内嵌输入法:组字按原文结束(内核拒收,文字退回已存的样子),引擎停用。
        aside { rimeAdapter?.focusChanged(false) }
        statusText = message
        tracker.reset()
        exitFocus(resetInsetsNow: true)
    }

    private func saveSelection() {
        guard let page else { return }
        let sel = textView.selectedRange
        if sel.location != NSNotFound { selectionStore.save(page: page, range: clamped(sel)) }
    }

    /// 存光标锚点,再把写队列做完并落检查点。
    func saveNow(completion: (() -> Void)? = nil) {
        guard let page, let persistence else { completion?(); return }
        saveSelection()
        persistence.flushAndCheckpoint(page: page) { _ in completion?() }
    }

    /// 退到后台:在后台任务里做 `saveNow`。
    func sceneDidEnterBackground() {
        guard page != nil, persistence != nil else { return }
        // 失去活跃时 `RimeInput` 已自己上屏;这里再保一次,避免组字留在屏幕上没进内核。
        prepareToSwitch()
        let app = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        let finish = {
            guard task != .invalid else { return }
            app.endBackgroundTask(task)
            task = .invalid
        }
        task = app.beginBackgroundTask(withName: "sumi.checkpoint", expirationHandler: finish)
        saveNow(completion: finish)
    }

    // MARK: 聚焦打字

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    private var canFocus: Bool {
        prefs.focusTyping && textView.isEditable && (model?.isWritable ?? false)
    }

    /// 最近 2 秒内满 4 次输入,或退出后的第一次输入(primed),进入聚焦。
    private func registerInput() {
        guard canFocus else { return }
        guard tracker.recordInput(at: now().timeIntervalSinceReferenceDate) else { return }
        if !focusMode { enterFocus() }
        if focusMode {
            if !faded { setFaded(true, duration: Self.focusEnter) }
            restartIdleTimer()
        }
    }

    private func enterFocus() {
        focusMode = true
        lastCaretLine = -1
        setFocusInsets()
        centerCaret(animated: true)
    }

    /// 退出后置 primed:下一次输入立即回到聚焦。
    private func exitFocus(resetInsetsNow: Bool = true) {
        let was = focusMode
        focusMode = false
        textView.pinnedY = nil
        idleTimer?.invalidate()
        idleTimer = nil
        if was { tracker.userMovedCaretOrScrolled() }
        if faded { setFaded(false, duration: Self.focusEnter) }
        if resetInsetsNow { resetInsets() } else { pendingInsetReset = true }
    }

    /// 上下各留半个视区,首行与末行也能居中。
    private func setFocusInsets() {
        let half = container.bounds.height / 2
        let inset = UIEdgeInsets(top: half, left: 0, bottom: half, right: 0)
        if textView.contentInset != inset { textView.contentInset = inset }
    }

    private func resetInsetsIfPending() {
        if pendingInsetReset && !focusMode { resetInsets() }
    }

    private func resetInsets() {
        pendingInsetReset = false
        applyRestingInsets(animated: !reduceMotion)
    }

    /// 换成平时的留白,并把滚动位置夹回新的可滚范围。
    private func applyRestingInsets(animated: Bool) {
        let resting = restingInsets
        guard textView.contentInset != resting else { return }
        let y = textView.contentOffset.y
        textView.contentInset = resting
        let maxY = max(0, textView.contentSize.height + resting.bottom - textView.bounds.height)
        let target = min(max(y, 0), maxY)
        if target != y { textView.setContentOffset(CGPoint(x: 0, y: target), animated: animated) }
    }

    /// 当前行固定在视区垂直中线。结果按屏幕像素取整,重复居中得到同一位置。
    private func centerCaret(animated: Bool) {
        guard focusMode, let end = textView.selectedTextRange?.end else { return }
        textView.layoutIfNeeded()
        let caret = textView.caretRect(for: end)
        guard caret.height > 0, !caret.isNull, !caret.isInfinite else { return }
        let h = textView.bounds.height
        let minY = -textView.contentInset.top
        let maxY = max(minY, textView.contentSize.height + textView.contentInset.bottom - h)
        var y = min(max(caret.midY - h / 2, minY), maxY)
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        y = (y * scale).rounded() / scale
        textView.pinnedY = y
        guard abs(textView.contentOffset.y - y) >= 0.5 else { return }
        let lineChanged = lastCaretLine >= 0 && abs(caret.minY - lastCaretLine) > 1
        lastCaretLine = caret.minY
        if animated && lineChanged && !reduceMotion {
            UIView.animate(withDuration: Self.focusEnter, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) {
                self.textView.contentOffset = CGPoint(x: 0, y: y)
            }
        } else {
            textView.contentOffset = CGPoint(x: 0, y: y)
        }
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.focusIdle, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.setFaded(false, duration: Self.focusRestore) }
        }
    }

    private func setFaded(_ on: Bool, duration: CFTimeInterval) {
        faded = on
        updateFade(duration: duration)
    }

    /// 上下文按距离逐级渐隐(`FadeMask`),遮罩分 96 段。
    private func updateFade(duration: CFTimeInterval) {
        let n = 96
        let H = max(container.bounds.height, 1)
        let center = H / 2
        let lh = lineHeight
        var colors: [CGColor] = []
        var locations: [NSNumber] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let y = H * t
            let a = faded ? FadeMask.opacity(distance: abs(y - center), lineHeight: lh, height: H) : 1
            colors.append(UIColor(white: 0, alpha: a).cgColor)
            locations.append(NSNumber(value: Double(t)))
        }
        let from = fadeMask.presentation()?.colors ?? fadeMask.colors
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.locations = locations
        fadeMask.colors = colors
        CATransaction.commit()
        if duration > 0 && !reduceMotion, let from {
            let anim = CABasicAnimation(keyPath: "colors")
            anim.fromValue = from
            anim.toValue = colors
            anim.duration = duration
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fadeMask.add(anim, forKey: "fade")
        }
    }

    // MARK: 滚动

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // 按着的右 ⌥ 是这次滚动的修饰键,不再算长按(rapp gui/macos/Runner/SessionPlugin.swift:237)。
        voiceKeyFeed(.scroll)
        if focusMode { exitFocus(resetInsetsNow: false) }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { resetInsetsIfPending() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { resetInsetsIfPending() }

    /// 手指拖动时候选行只跟着走;系统自发的滚动(插入后滚到光标)之后再看要不要上滚。
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        placeRimeBar(reveal: !(scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating))
    }

    // MARK: 内嵌输入法(ios.md §3.6)

    private func attachRime(_ rime: RimeInputDriving, defaults: UserDefaults) {
        let probe = RimeLandingProbe(rime)
        rimeProbe = probe
        let adapter = RimeTextViewAdapter(textView: textView, input: probe, defaults: defaults, style: .sumi(prefs))
        rimeAdapter = adapter
        // 右端一个状态字(中 / 英 / 系),点开菜单切换;空闲时候选行只剩状态字那一块(ios.md §3.6「状态字」)。
        adapter.bar.statusMenu = true
        // 中英文之间自动加空格,规则照桌面(ios.md §3.6「中英文之间自动加空格」)。
        adapter.autoSpace = true
        adapter.onBarChange = { [weak self] in self?.placeRimeBar(reveal: true) }
        adapter.onUpdate = { [weak self] _ in self?.placeRimeBar(reveal: true) }
        let select = adapter.bar.onSelect, page = adapter.bar.onPage
        adapter.bar.onSelect = { [weak self] index in self?.tapping { select?(index) } }
        adapter.bar.onPage = { [weak self] next in self?.tapping { page?(next) } }
        // 只读时不算聚焦:引擎不启用,按键照常交给系统(打开或保存失败)。
        textView.onFocusChange = { [weak self] focused in
            guard let self else { return }
            if !focused { rimeHeld.removeAll() }
            // 失焦时按原文上屏的那次文字变化不算打字(同切页前,ios.md §3.6):走 aside,文字仍经 textViewDidChange 进内核。
            let change = { self.quietly { self.rimeAdapter?.focusChanged(focused && self.textView.isEditable) } }
            if focused { change() } else { aside(change) }
        }
        textView.onTouchBegan = { [weak self] modifiers in self?.rimeAdapter?.touchBegan(modifiers: modifiers) }
        textView.isLockedForComposition = { [weak self] in self?.rimeAdapter?.isComposing ?? false }
    }

    private func quietly(_ body: () -> Void) {
        rimeQuiet += 1
        body()
        rimeQuiet -= 1
    }

    private func aside(_ body: () -> Void) {
        rimeAside += 1
        body()
        rimeAside -= 1
    }

    private func tapping(_ body: () -> Void) {
        rimeTap += 1
        body()
        rimeTap -= 1
    }

    /// 这次文字变化是不算打字的上屏:切页前、变成只读时;或引擎自己落下的更新,而当时既没按着它吞下的键、
    /// 也不在点候选、也不在宿主调它的按键与焦点入口里(如失去活跃时引擎自己上屏)。
    private var rimeCommitAside: Bool {
        if rimeAside > 0 { return true }
        guard let probe = rimeProbe, probe.landing > 0 else { return false }
        return rimeQuiet == 0 && rimeTap == 0 && rimeHeld.isEmpty
    }

    /// 平时正文底下留出候选行的高度,光标在最后一行时也能把下一行(候选行)滚进视区。
    private var restingInsets: UIEdgeInsets {
        guard let adapter = rimeAdapter, adapter.barVisible else { return .zero }
        return UIEdgeInsets(top: 0, left: 0, bottom: barGap + RimeCandidateBar.height(for: adapter.bar.style.font),
                            right: 0)
    }

    /// 候选行与光标所在行字形下缘之间的空白:与正文两行之间的一样,正文字体行高 ×(行距设置 − 1)(ios.md §3.6
    /// 「与输入行的间距按行距算」)。
    var barGap: CGFloat { max(0, lineHeight - baseFont.lineHeight) }

    /// 候选行在光标所在行之下隔一个行距(`barGap`):左缘、宽度与正文列一致,高度随字号;位置由光标所在行算出,
    /// 所以只在光标换行时动。
    /// `reveal`:不在聚焦打字、光标所在行在视区里、而候选行会落到视区外时,先把正文上滚到候选行露全
    /// (光标在视区最后一行时就是上滚一行)。聚焦打字时光标行居中,不需要。
    private func placeRimeBar(reveal: Bool) {
        guard let bar = rimeAdapter?.bar, bar.superview != nil else { return }
        if !focusMode && !pendingInsetReset { applyRestingInsets(animated: false) }
        guard rimeAdapter?.barVisible == true, container.bounds.height > 0 else { return }
        // 先让文本视图排好版再读光标行。上屏被内核接受后改了文字和属性,TextKit 2 的排版随之作废,
        // 不排版时读到的光标行是估计值(长页、自动换行时比真实位置高出几行);按它摆放的候选行之后没有滚动、
        // 也没有更新来纠正,就停在光标行上面盖住文字(真机反馈 2026-11-20)。
        textView.layoutIfNeeded()
        let inset = textView.textContainerInset
        let height = RimeCandidateBar.height(for: bar.style.font)
        let width = max(0, textView.bounds.width - inset.left - inset.right)
        guard let bottom = textView.caretBottomAfterLayout() else { return }
        let top = bottom + barGap
        let visible = container.frame
        var y = textView.convert(CGPoint(x: 0, y: top), to: view).y
        let caretLine = textView.selectedTextRange.map { textView.convert(textView.caretRect(for: $0.end), to: view) }
        let caretVisible = caretLine.map { $0.minY >= visible.minY - 0.5 && $0.maxY <= visible.maxY + 0.5 } ?? false
        if reveal && caretVisible && !focusMode && textView.pinnedY == nil && y + height > visible.maxY + 0.5 {
            let overflow = y + height - visible.maxY
            let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
            let target = ((textView.contentOffset.y + overflow) * scale).rounded(.up) / scale
            textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: target), animated: false)
            y = textView.convert(CGPoint(x: 0, y: top), to: view).y
        }
        // 光标行滚出视区时不显示,不贴在边上盖住别的字(alpha:显隐归适配器管)。
        bar.alpha = caretVisible ? 1 : 0
        let x = textView.convert(CGPoint(x: inset.left, y: 0), to: view).x
        let frame = CGRect(x: x, y: y, width: width, height: height)
        if bar.frame != frame { bar.frame = frame }
        view.bringSubviewToFront(bar)
    }

    // MARK: 硬件键盘

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(title: "新建一页", action: #selector(cmdNew), input: "n", modifierFlags: .command),
            UIKeyCommand(title: "上一页", action: #selector(cmdPrev), input: "[", modifierFlags: .command),
            UIKeyCommand(title: "下一页", action: #selector(cmdNext), input: "]", modifierFlags: .command),
            UIKeyCommand(title: "纸页列表", action: #selector(cmdOverview), input: "l", modifierFlags: [.command, .shift]),
            UIKeyCommand(title: "设置", action: #selector(cmdAppearance), input: ",", modifierFlags: .command),
            UIKeyCommand(title: "放大字号", action: #selector(cmdBigger), input: "=", modifierFlags: .command),
            UIKeyCommand(title: "缩小字号", action: #selector(cmdSmaller), input: "-", modifierFlags: .command),
            UIKeyCommand(title: "默认字号", action: #selector(cmdResetSize), input: "0", modifierFlags: .command),
            UIKeyCommand(title: "菜单", action: #selector(cmdEscape), input: UIKeyCommand.inputEscape, modifierFlags: []),
        ]
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // 组字期间不执行应用命令,Esc 先交给输入法。
        let mine: [Selector] = [#selector(cmdNew), #selector(cmdPrev), #selector(cmdNext), #selector(cmdOverview),
                                #selector(cmdAppearance), #selector(cmdBigger), #selector(cmdSmaller),
                                #selector(cmdResetSize), #selector(cmdEscape)]
        // 内置输入法组字中,切页类命令放行(先上屏再切);字号命令与 Esc 照旧不放行。
        let switching: [Selector] = [#selector(cmdNew), #selector(cmdPrev), #selector(cmdNext),
                                     #selector(cmdOverview), #selector(cmdAppearance)]
        if switching.contains(action) { return canSwitchPage }
        // 键盘说话中,Esc 是取消:交给门限,不开菜单。
        if action == #selector(cmdEscape) && voiceKeys.recording { return false }
        if mine.contains(action) { return textView.markedTextRange == nil }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc private func cmdNew() { onCommand?(.newPage) }
    @objc private func cmdPrev() { onCommand?(.prev) }
    @objc private func cmdNext() { onCommand?(.next) }
    @objc private func cmdOverview() { onCommand?(.overview) }
    @objc private func cmdAppearance() { onCommand?(.appearance) }
    @objc private func cmdBigger() { prefsModel.bumpSize(2) }
    @objc private func cmdSmaller() { prefsModel.bumpSize(-2) }
    @objc private func cmdResetSize() { prefsModel.prefs.fontSize = EditorPrefs.defaultFontSize }
    @objc private func cmdEscape() { onCommand?(.menu) }
}

extension EditorController: KeyPressHandling {
    /// 先过长按右 ⌥ 说话的门限(ios.md §3.8),它吞下的键不再往下传;其余的再给内嵌输入法。
    /// AI 整理卡还在时,按下的键先让卡上的字落地,再照常处理。
    func unhandled(_ presses: Set<UIPress>, began: Bool) -> Set<UIPress> {
        if began && voiceTidyBusy?() == true { onVoiceTidyKey?() }
        return rimeUnhandled(voiceKeyUnhandled(presses, began: began), began: began)
    }

    /// 内嵌输入法;它吞下的每个按下的键响一声打字音(按键码分种类),由它引起的上屏、组字不另响。
    private func rimeUnhandled(_ presses: Set<UIPress>, began: Bool) -> Set<UIPress> {
        // 只读时引擎不启用(`onFocusChange`),按键原样交给系统。
        guard !presses.isEmpty, let adapter = rimeAdapter, textView.isEditable else { return presses }
        // 切换中 / 英的快捷键不算打字:不发声,不记作按着的键,组字中先上屏的那次走 aside(ios.md §3.6)。
        // 先松开修饰键、空格还按着时,系统再发的空格仍被快捷键占着,适配器也认作快捷键,同样不响。
        let shortcut = presses.filter(adapter.isSwitchShortcut)
        let typed = presses.subtracting(shortcut)
        var rest = Set<UIPress>()
        if !shortcut.isEmpty { aside { rest = adapter.unhandled(shortcut, began: began) } }
        quietly { rest.formUnion(adapter.unhandled(typed, began: began)) }
        let taken = typed.subtracting(rest)
        if began {
            rimeHeld.formUnion(taken.map(ObjectIdentifier.init))
        } else {
            rimeHeld.subtract(presses.map(ObjectIdentifier.init))
        }
        if began, model?.isWritable == true {
            for press in taken {
                if let kind = KeyKind.of(press) { sound?.play(kind: kind) }
            }
        }
        return rest
    }
}

// MARK: 长按右 ⌥ 说话(ios.md §3.8「入口」)

// 照 rapp gui/macos/Runner/SessionPlugin.swift 驱动 `VoiceKeyGate`:`route` 的门限一段、`gateFeed`、
// `setVoiceHotkey`。rapp 的 `gateSid`(哪个会话)不移植:只有一张纸页、一个宿主。
extension EditorController {
    /// rapp `route` 的门限一段:每个按键喂门限一次,arm 时记下这一键,`pass` 的往下传。
    /// iOS 不为连发再发 `pressesBegan`,所以 `isRepeat` 总是 false。
    fileprivate func voiceKeyUnhandled(_ presses: Set<UIPress>, began: Bool) -> Set<UIPress> {
        var rest = Set<UIPress>()
        for press in presses {
            guard let key = press.key else {
                rest.insert(press)
                continue
            }
            let code = Self.voiceKeyCode(key.keyCode)
            let input: VoiceGateInput = began
                ? .down(code, KeyFlags(rawValue: UInt64(key.modifierFlags.rawValue)), isRepeat: false)
                : .up(code)
            let step = voiceKeyFeed(input)
            if step.arm { voiceKeyHeld = press }
            if step.pass { rest.insert(press) }
        }
        return rest
    }

    /// 门限认的 mac 键码(`HIDKeyCodes.mac`);门限不关心的键各给一个不与 mac 键码重叠的码(256 + HID 用途),
    /// 门限只拿它们看「同时按着别的键」。
    private static func voiceKeyCode(_ usage: UIKeyboardHIDUsage) -> UInt16 {
        if let mac = HIDKeyCodes.mac(usage) { return UInt16(mac) }
        return UInt16(clamping: 256 + usage.rawValue)
    }

    /// rapp `gateFeed`:喂门限一个输入并照它的步骤做(事件本身除外)。flush 先把吞下的右 ⌥ 按下补交给内嵌输入法
    /// 与系统;arm 开计时;阶段交给 `onVoiceKey`。能开始的条件(rapp 的 `voiceOn && targetSid != nil`):
    /// 纸页可写、宿主空闲。
    @discardableResult
    fileprivate func voiceKeyFeed(_ input: VoiceGateInput) -> VoiceGateStep {
        let ready = voiceAvailable && (voiceKeyReady?() ?? false)
        let step = voiceKeys.handle(input, at: uptime(), ready: ready)
        if step.flush {
            voiceKeyTimer?.cancel()
            voiceKeyTimer = nil
            if let held = voiceKeyHeld {
                voiceKeyHeld = nil
                textView.forwardBegan(rimeUnhandled([held], began: true))
            }
        }
        if step.arm {
            voiceKeyTimer?.cancel()
            let timer = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.voiceKeyTimer = nil
                    self.voiceKeyFeed(.elapsed)
                }
            }
            voiceKeyTimer = timer
            DispatchQueue.main.asyncAfter(deadline: .now() + VoiceKeyGate.holdDelay, execute: timer)
        }
        if let phase = step.voice { onVoiceKey?(phase) }
        return step
    }

    /// rapp `setVoiceHotkey`:设置「按住右 ⌥ 说话」开关变了。真的变了才重来:丢掉计时与吞下的按下,说话中就取消。
    fileprivate func setVoiceHotkey(_ hotkey: VoiceHotkey) {
        guard hotkey != voiceKeys.hotkey else { return }
        voiceKeyTimer?.cancel()
        voiceKeyTimer = nil
        voiceKeyHeld = nil
        if let phase = voiceKeys.setHotkey(hotkey).voice { onVoiceKey?(phase) }
    }
}
