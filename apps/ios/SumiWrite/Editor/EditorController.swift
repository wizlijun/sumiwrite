import SwiftUI
import UIKit

/// 编辑面:文本视图、编辑区外顶部的状态条与菜单按钮、键盘避让、聚焦打字、保存接线。
/// 文字的增删、粘贴、撤销都经 `PageModel` 交给内核;样式来自内核的样式段,经 `Styler` 映射。
final class EditorController: UIViewController, UITextViewDelegate {
    let textView = SumiTextView()
    /// `nil`、`保存失败` 或 `打不开纸页`。
    private(set) var statusText: String?
    private(set) var prefs: EditorPrefs

    private let page: CorePage?
    /// 强引用:`PageModel` 只弱持有它的 sink,这里不留住它,保存就会悄悄丢掉。
    private let persistence: PagePersistence?
    private let model: PageModel?
    private let prefsStore: PrefsStore
    private let selectionStore: SelectionStore
    private let sound: TypingSoundPlaying?

    private let statusBar = UIView()
    private let statusLabel = UILabel()
    private let menuButton = UIButton(type: .system)
    private let container = UIView()
    private let fadeMask = CAGradientLayer()

    private var tracker = FocusTypingTracker()
    /// 文本视图上一次的文字;打字音拿它与新文字比较。每次文字变化后都刷新(含程序设置、撤销、粘贴)。
    private var lastText = ""
    /// 程序正在改文字或选区;这期间的代理回调不算用户动作。
    private var applyingProgrammaticChange = false
    /// 用户输入改了文字、`textViewDidChange` 还没到。UITextView 先发选区变更再发文字变更,
    /// 这期间的选区变更是输入带出来的,不算挪光标(ios.md §3.2)。
    private var inputPending = false
    /// 内核结果落到编辑面后光标所在处;紧随其后、与之相符的选区变更同样不算挪光标。
    private var expectedSelection: NSRange?
    private var storageObserver: NSObjectProtocol?
    private var verticalArrowPending = false
    private var focusPresented = false
    private var faded = false
    private var idleTimer: Timer?
    private var pendingInsetReset = false
    private var didInitialScroll = false

    private static let statusBarHeight: CGFloat = 44
    private static let focusEnter: CFTimeInterval = 0.2
    private static let focusIdle: TimeInterval = 10
    private static let focusRestore: CFTimeInterval = 1.2

    init(open: OpenResult, prefs: PrefsStore, selection: SelectionStore, sound: TypingSoundPlaying?) {
        prefsStore = prefs
        selectionStore = selection
        self.sound = sound
        self.prefs = prefs.load()
        switch open {
        case .ready(let p, let pg):
            persistence = p
            page = pg
            model = PageModel(page: pg, sink: p)
            statusText = nil
        case .failed(let message):
            persistence = nil
            page = nil
            model = nil
            statusText = message
        }
        super.init(nibName: nil, bundle: nil)
        persistence?.onFailure = { [weak self] message in self?.saveFailed(message) }
        textView.coreUndoManager = CoreUndoManager(
            canUndo: { [weak self] in self?.historyAvailable(redo: false) ?? false },
            canRedo: { [weak self] in self?.historyAvailable(redo: true) ?? false },
            undo: { [weak self] in self?.performHistory(redo: false) },
            redo: { [weak self] in self?.performHistory(redo: true) })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let storageObserver { NotificationCenter.default.removeObserver(storageObserver) }
    }

    // MARK: 视图

    override func viewDidLoad() {
        super.viewDidLoad()
        buildViews()
        applyPrefs()
        loadPage()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyInterfaceStyle()
        if textView.isEditable && !textView.isFirstResponder { _ = textView.becomeFirstResponder() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = container.bounds
        CATransaction.commit()
        layoutTextInsets()
        if focusPresented {
            setFocusInsets()
            centerCaret(animated: false)
        }
        updateFade(duration: 0)
        if !didInitialScroll && textView.bounds.height > 0 {
            didInitialScroll = true
            textView.layoutIfNeeded()
            textView.scrollRangeToVisible(textView.selectedRange)
        }
    }

    private func buildViews() {
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        let safe = view.safeAreaLayoutGuide

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)
        view.addSubview(container)
        statusBar.addSubview(statusLabel)
        statusBar.addSubview(menuButton)

        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.adjustsFontForContentSizeCategory = true
        menuButton.setImage(UIImage(systemName: "textformat.size"), for: .normal)
        menuButton.accessibilityLabel = "外观"
        menuButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)

        NSLayoutConstraint.activate([
            statusBar.topAnchor.constraint(equalTo: safe.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: Self.statusBarHeight),
            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 16),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -8),
            menuButton.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -8),
            menuButton.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),
            container.topAnchor.constraint(equalTo: statusBar.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
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
        textView.prepareSurface()
        textView.pasteHandler = { [weak self] in self?.paste($0) }
        textView.onVerticalArrow = { [weak self] in self?.verticalArrowPending = true }
        container.addSubview(textView)

        storageObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: textView.textStorage, queue: nil
        ) { [weak self] note in
            guard let self, !self.applyingProgrammaticChange,
                  let storage = note.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
            self.inputPending = true
        }

        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        container.layer.mask = fadeMask
    }

    private func loadPage() {
        statusLabel.text = statusText
        guard let model, let page else {
            textView.isEditable = false
            return
        }
        programmatic {
            textView.textStorage.setAttributedString(NSAttributedString(string: model.rendered.text, attributes: baseAttributes))
            restyle()
            textView.selectedRange = clamped(selectionStore.restore(page: page))
        }
    }

    // MARK: 外观

    private var baseFont: UIFont { prefs.font.uiFont(size: CGFloat(prefs.fontSize)) }
    private var baseAttributes: [NSAttributedString.Key: Any] { Styler.base(prefs: prefs, baseFont: baseFont) }

    /// 校验、应用并持久化;超出范围的值不接受。
    func updatePrefs(_ p: EditorPrefs) {
        guard let ok = p.validated(), ok != prefs else { return }
        prefs = ok
        _ = prefsStore.save(ok)
        applyPrefs()
    }

    private func applyPrefs() {
        let theme = prefs.theme
        view.backgroundColor = theme.background
        statusBar.backgroundColor = theme.background
        statusLabel.textColor = theme.foreground
        menuButton.tintColor = theme.foreground
        textView.keyboardAppearance = theme.isDark ? .dark : .light
        textView.caretView.color = theme.foreground
        textView.caretView.motion = prefs.caretMotion
        textView.selectionColor = theme.selection
        textView.handleColor = theme.foreground
        textView.tintSelectionViews()
        // 组字中不重设属性;下一次被接受的输入会重设。
        if textView.markedTextRange == nil { programmatic { restyle() } }
        if !prefs.focusTyping { leaveFocus() }
        sound?.preferencesChanged(prefs)
        applyInterfaceStyle()
        view.setNeedsLayout()
        textView.updateCaret()
    }

    /// 系统状态栏与设置弹层跟随主题的明暗。
    private func applyInterfaceStyle() {
        view.window?.overrideUserInterfaceStyle = prefs.theme.isDark ? .dark : .light
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

    @objc private func openSettings() {
        let settings = SettingsView(prefs: prefs) { [weak self] in self?.updatePrefs($0) }
        let host = UIHostingController(rootView: settings)
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(host, animated: true)
    }

    // MARK: 输入

    func textViewDidChange(_ textView: UITextView) {
        guard let model, !applyingProgrammaticChange else { return }
        inputPending = false
        let composing = textView.markedTextRange != nil
        let visible = textView.text ?? ""
        if model.isWritable, textView.isEditable { sound?.play(before: lastText, after: visible) }
        lastText = visible
        let sel = textView.selectedRange
        let caret = sel.location == NSNotFound ? (visible as NSString).length : NSMaxRange(sel)
        switch model.userEdited(visible: visible, composing: composing, caret: caret) {
        case .unchanged:
            // 拼音预编辑也算真实输入(04「聚焦打字」),但不提交、不重设。
            if composing { noteInput() }
        case .accepted(let rendered, let caret):
            show(rendered, caret: caret)
            noteInput()
        case .rejected(let rendered, let caret):
            reset(to: rendered, caret: caret)
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        self.textView.updateCaret()
        self.textView.tintSelectionViews()
        guard !applyingProgrammaticChange, !inputPending, textView.markedTextRange == nil else { return }
        if let expected = expectedSelection, textView.selectedRange == expected {
            expectedSelection = nil
            return
        }
        expectedSelection = nil
        if verticalArrowPending {
            // 聚焦状态下按上、下方向键,当前行仍保持居中。
            verticalArrowPending = false
            if focusPresented { centerCaret(animated: true) }
            return
        }
        userMovedCaretOrScrolled()
    }

    private func paste(_ markdown: String) {
        guard let model, textView.markedTextRange == nil else { return }
        let range = textView.selectedRange
        guard range.location != NSNotFound else { return }
        switch model.paste(markdown: markdown, range: range) {
        case .unchanged: break
        case .accepted(let rendered, let caret): show(rendered, caret: caret)
        case .rejected(let rendered, let caret): reset(to: rendered, caret: caret)
        }
    }

    // MARK: 撤销与重做

    private func historyAvailable(redo: Bool) -> Bool {
        guard let model, model.isWritable, textView.markedTextRange == nil else { return false }
        return redo ? model.canRedo : model.canUndo
    }

    private func performHistory(redo: Bool) {
        guard let model, textView.markedTextRange == nil else { return }
        switch redo ? model.redo() : model.undo() {
        case .unchanged: break
        case .accepted(let rendered, let caret): show(rendered, caret: caret)
        case .rejected(let rendered, _):
            // 内核在拒绝时不知道光标;保留当前选区,只夹到文本长度内。
            let length = (rendered.text as NSString).length
            let sel = textView.selectedRange
            reset(to: rendered, caret: sel.location == NSNotFound ? length : min(sel.location, length))
        }
        if focusPresented { centerCaret(animated: true) }
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
        expectedSelection = textView.selectedRange
    }

    /// 被拒绝:整段重置为内核文本。
    private func reset(to rendered: RenderedText, caret: Int) {
        programmatic {
            textView.textStorage.setAttributedString(NSAttributedString(string: rendered.text, attributes: baseAttributes))
            restyle()
            textView.selectedRange = clamped(NSRange(location: caret, length: 0))
        }
        expectedSelection = nil
    }

    private func programmatic(_ body: () -> Void) {
        let was = applyingProgrammaticChange
        applyingProgrammaticChange = true
        body()
        applyingProgrammaticChange = was
        lastText = textView.text ?? ""
        textView.updateCaret()
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
        statusLabel.text = message
        leaveFocus()
        textView.updateCaret()
    }

    /// 退到后台:先存光标锚点,再在后台任务里把写队列做完并落检查点。
    func sceneDidEnterBackground() {
        guard let page, let persistence else { return }
        let sel = textView.selectedRange
        if sel.location != NSNotFound { selectionStore.save(page: page, range: clamped(sel)) }
        let app = UIApplication.shared
        var task = UIBackgroundTaskIdentifier.invalid
        let finish = {
            guard task != .invalid else { return }
            app.endBackgroundTask(task)
            task = .invalid
        }
        task = app.beginBackgroundTask(withName: "sumi.checkpoint", expirationHandler: finish)
        persistence.flushAndCheckpoint(page: page) { _ in finish() }
    }

    // MARK: 聚焦打字

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    private var canFocus: Bool {
        prefs.focusTyping && textView.isEditable && (model?.isWritable ?? false)
    }

    private func noteInput() {
        guard canFocus else { return }
        guard tracker.recordInput(at: CACurrentMediaTime()) else { return }
        if !focusPresented { enterFocus() }
        if !faded { setFaded(true, duration: Self.focusEnter) }
        restartIdleTimer()
        centerCaret(animated: true)
    }

    private func userMovedCaretOrScrolled(resetInsetsNow: Bool = true) {
        tracker.userMovedCaretOrScrolled()
        exitFocus(resetInsetsNow: resetInsetsNow)
    }

    /// 退出并清掉计数(偏好关闭、只读、保存失败)。
    private func leaveFocus() {
        tracker.reset()
        exitFocus(resetInsetsNow: true)
    }

    private func enterFocus() {
        focusPresented = true
        setFocusInsets()
    }

    private func exitFocus(resetInsetsNow: Bool) {
        idleTimer?.invalidate()
        idleTimer = nil
        textView.lockedOffsetY = nil
        if faded { setFaded(false, duration: Self.focusEnter) }
        guard focusPresented else { return }
        focusPresented = false
        if resetInsetsNow { resetInsets() } else { pendingInsetReset = true }
    }

    /// 上下各留半个视区,首行与末行也能居中。
    private func setFocusInsets() {
        let half = (container.bounds.height / 2).rounded()
        let inset = UIEdgeInsets(top: half, left: 0, bottom: half, right: 0)
        if textView.contentInset != inset { textView.contentInset = inset }
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

    /// 当前行固定在视区中线;按屏幕像素取整,重复居中落在同一位置。
    private func centerCaret(animated: Bool) {
        guard focusPresented, let end = textView.selectedTextRange?.end else { return }
        textView.layoutIfNeeded()
        let caret = textView.caretRect(for: end)
        guard caret.height > 0, !caret.isNull, !caret.isInfinite else { return }
        let h = textView.bounds.height
        let minY = -textView.contentInset.top
        let maxY = max(minY, textView.contentSize.height + textView.contentInset.bottom - h)
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        let y = (min(max(caret.midY - h / 2, minY), maxY) * scale).rounded() / scale
        textView.lockedOffsetY = y
        guard abs(textView.contentOffset.y - y) >= 0.5 / scale else { return }
        if animated && !reduceMotion {
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
            self?.setFaded(false, duration: Self.focusRestore)
        }
    }

    private func setFaded(_ on: Bool, duration: CFTimeInterval) {
        faded = on
        updateFade(duration: duration)
    }

    /// 上下文按与中线的距离逐级渐隐:相邻一行约 55%,每远一行再乘 0.55,再乘距离平方衰减的边缘系数(04)。
    private func updateFade(duration: CFTimeInterval) {
        let steps = 96
        let height = max(container.bounds.height, 1)
        let center = height / 2
        let line = baseFont.lineHeight * CGFloat(prefs.lineSpacing)
        var colors: [CGColor] = []
        var locations: [NSNumber] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let d = abs(height * t - center)
            var alpha: CGFloat = 1
            if faded && d > line / 2 {
                let edge = max(0, 1 - pow(d / center, 2))
                alpha = pow(0.55, d / line) * edge
            }
            colors.append(UIColor(white: 0, alpha: alpha).cgColor)
            locations.append(NSNumber(value: Double(t)))
        }
        let from = fadeMask.presentation()?.colors ?? fadeMask.colors
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.locations = locations
        fadeMask.colors = colors
        CATransaction.commit()
        guard duration > 0, !reduceMotion, let from else { return }
        let anim = CABasicAnimation(keyPath: "colors")
        anim.fromValue = from
        anim.toValue = colors
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fadeMask.add(anim, forKey: "fade")
    }

    // MARK: 滚动

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userMovedCaretOrScrolled(resetInsetsNow: false)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { resetInsetsIfPending() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { resetInsetsIfPending() }

    private func resetInsetsIfPending() {
        if pendingInsetReset && !focusPresented { resetInsets() }
    }
}
