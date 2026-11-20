import Combine
import os
import UIKit

/// 编辑面:文本视图、自绘光标、键盘避让、聚焦打字、硬件键盘命令、保存接线。
/// 文字的增删、粘贴、撤销都经 `PageModel` 交给内核;样式来自内核的样式段,经 `Styler` 映射。
/// 交互细节照搬原型(设计 §5.3)。
final class EditorController: UIViewController, UITextViewDelegate {
    let textView = SumiTextView()
    /// 硬件键盘命令与「正在打字」;由外壳接。
    var onCommand: ((EditorCommand) -> Void)?
    /// 时钟;测试注入。
    var now: () -> Date = { Date() }
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
    /// `shouldChangeTextIn` 判出的按键种类,随后的 `textViewDidChange` 交给打字音。
    private var pendingKind: KeyKind?

    /// 文本视图上一次的文字;打字音拿它与新文字比较。每次文字变化后都刷新(含程序设置、撤销、粘贴)。
    private var lastText = ""
    /// 程序正在改文字或选区;这期间的代理回调不算用户动作。
    private var applyingProgrammaticChange = false
    private var didInitialScroll = false

    private static let focusEnter: CFTimeInterval = 0.2
    private static let focusIdle: TimeInterval = 10
    private static let focusRestore: CFTimeInterval = 1.2

    /// `persistence` 或 `page` 为 nil 表示打开失败,编辑面只读。
    init(persistence: PagePersistence?, page: CorePage?, prefs: PrefsModel, selection: SelectionStore,
         sound: TypingSoundPlaying?) {
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
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    /// 组字中不切页。
    var canSwitchPage: Bool { textView.markedTextRange == nil }

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
            container.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
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

    override func viewDidLayoutSubviews() {
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
    }

    /// 整段重设属性:先上基础样式,再按内核的样式段(已是互不重叠的平铺段)依次叠加。
    private func restyle() {
        let storage = textView.textStorage
        let base = baseAttributes
        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))
        if let r = model?.rendered, r.text == storage.string {
            for (range, attrs) in Styler.attributes(for: r, prefs: prefs, baseFont: baseFont) {
                storage.addAttributes(attrs, range: range)
            }
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
        keyPressed(kind)
        return true
    }

    private func keyPressed(_ kind: KeyKind) {
        pendingKind = kind
        inEdit = true
        onCommand?(.typing)
        DispatchQueue.main.async { [weak self] in self?.afterEdit() }
    }

    private func afterEdit() {
        if focusMode { centerCaret(animated: true) }
        inEdit = false
        // 代理放行了但文字没变(如文首退格):不把这次的种类留给下一次改动。
        pendingKind = nil
    }

    func textViewDidChange(_ textView: UITextView) {
        guard let model, !applyingProgrammaticChange else { return }
        let composing = textView.markedTextRange != nil
        let visible = textView.text ?? ""
        if model.isWritable, textView.isEditable { sound?.play(before: lastText, after: visible, kind: pendingKind) }
        pendingKind = nil
        lastText = visible
        let sel = textView.selectedRange
        let caret = sel.location == NSNotFound ? (visible as NSString).length : NSMaxRange(sel)
        switch model.userEdited(visible: visible, composing: composing, caret: caret) {
        case .unchanged:
            // 拼音预编辑也算真实输入(04「聚焦打字」),但不提交、不重设。
            if composing { registerInput() }
        case .accepted(let rendered, let caret):
            show(rendered, caret: caret)
            registerInput()
        case .rejected(let rendered, let caret):
            reset(to: rendered, caret: caret)
        }
        markEdited()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !applyingProgrammaticChange, textView.markedTextRange == nil else { return }
        // 外置键盘下,选区通知会晚于文字变更到达;紧随输入的选区变化不算「挪光标」。
        let followsEdit = textView.selectedRange == editSelection
            || now().timeIntervalSince(lastEditTime) < 0.5
        if inEdit || arrowNav || followsEdit {
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
        applyingProgrammaticChange = was
        lastText = textView.text ?? ""
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
        guard textView.contentInset != .zero else { return }
        let y = textView.contentOffset.y
        textView.contentInset = .zero
        let maxY = max(0, textView.contentSize.height - textView.bounds.height)
        let target = min(max(y, 0), maxY)
        if target != y { textView.setContentOffset(CGPoint(x: 0, y: target), animated: !reduceMotion) }
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
        if focusMode { exitFocus(resetInsetsNow: false) }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { resetInsetsIfPending() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { resetInsetsIfPending() }

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
