import UIKit

/// 可替换的按键入口(给今后的外接键盘输入法 RimeKit 留的口)。返回 `true` 表示这次按键已被处理。
protocol KeyPressHandling: AnyObject {
    func handle(_ presses: Set<UIPress>, event: UIPressesEvent?, phase: UIPress.Phase) -> Bool
}

/// 自绘光标:主题色竖线,对无障碍隐藏。呼吸动画只在显示时运行;挪位置不重启相位。
final class CaretView: UIView {
    private static let breathKey = "sumi.breath"

    var color: UIColor = .white { didSet { backgroundColor = color } }
    var motion: CaretMotion = .breathing { didSet { if oldValue != motion { restartAnimation() } } }
    /// 是否应当显示;隐藏时停掉动画。
    var isShown = false {
        didSet {
            guard oldValue != isShown else { return }
            isHidden = !isShown
            restartAnimation()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isHidden = true
        backgroundColor = color
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restartAnimation()
    }

    private func restartAnimation() {
        layer.removeAnimation(forKey: Self.breathKey)
        guard motion == .breathing, isShown, window != nil else { return }
        let steps = 40
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = (0...steps).map { CaretMetrics.opacity(at: CaretMetrics.period * Double($0) / Double(steps)) }
        a.keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
        a.duration = CaretMetrics.period
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        layer.add(a, forKey: Self.breathKey)
    }
}

/// TextKit 2 正文视图:隐藏系统光标并自绘、聚焦时的滚动锁、按键入口与粘贴。
/// 文字的增删、撤销都由 `EditorController` 经内核完成,这里不做。
final class SumiTextView: UITextView {
    let caretView = CaretView()
    /// 注入的内核撤销;`UITextView` 自带的撤销栈因此不生效。
    var coreUndoManager: CoreUndoManager?
    var pressHandler: KeyPressHandling?
    /// 收到要粘贴的字符串;组字中、剪贴板没有字符串时不会调用。
    var pasteHandler: ((String) -> Void)?
    var pasteboard: UIPasteboard = .general
    /// 硬件键盘的上、下方向键(未被 `pressHandler` 接走时)。
    var onVerticalArrow: (() -> Void)?
    /// 选区相关的系统视图要跟随的颜色(选区底色、拖柄)。
    var selectionColor: UIColor = .clear
    var handleColor: UIColor = .clear

    /// 聚焦打字时锁定的纵向偏移。非 nil 时,系统自发的滚动(插入后滚到光标、内容尺寸变化时的校正)
    /// 一律钉回这里;手指拖动、减速期间不钉(ios.md §3.3)。
    var lockedOffsetY: CGFloat?

    private var userScrolling: Bool { isTracking || isDragging || isDecelerating }

    /// 不用 `init(usingTextLayoutManager:)`:那是 Objective-C 工厂方法,绕过 Swift 存储属性的初始化。
    /// 文本容器传 nil 时,iOS 16 起默认就是 TextKit 2。
    init() {
        super.init(frame: .zero, textContainer: nil)
        // 写作工具的就地会话会和程序化的重排样式打架,「还原」又依赖已被挡掉的系统撤销栈;只留面板模式。
        if #available(iOS 18, *) { writingToolsBehavior = .limited }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var undoManager: UndoManager? { coreUndoManager ?? super.undoManager }

    /// 装上自绘光标并隐藏系统光标;由控制器在建视图时调用一次。
    func prepareSurface() {
        tintColor = .clear
        if caretView.superview !== self { addSubview(caretView) }
    }

    // MARK: 滚动锁

    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set {
            if let y = lockedOffsetY, !userScrolling { super.contentOffset = CGPoint(x: newValue.x, y: y) }
            else { super.contentOffset = newValue }
        }
    }

    override func setContentOffset(_ offset: CGPoint, animated: Bool) {
        if let y = lockedOffsetY, !userScrolling {
            super.setContentOffset(CGPoint(x: offset.x, y: y), animated: false)
        } else {
            super.setContentOffset(offset, animated: animated)
        }
    }

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        if lockedOffsetY != nil && !userScrolling { return }
        super.scrollRectToVisible(rect, animated: animated)
    }

    // MARK: 光标

    override func caretRect(for position: UITextPosition) -> CGRect {
        let r = super.caretRect(for: position)
        guard r.height > 0, !r.isNull, !r.isInfinite else { return r }
        let attrs = caretAttributes(at: offset(from: beginningOfDocument, to: position))
        guard let f = attrs[.font] as? UIFont else { return r }
        let height = f.ascender - f.descender
        let ps = attrs[.paragraphStyle] as? NSParagraphStyle
        var top = r.minY, box = r.height
        // TextKit 2 空行(空段落、文末换行后的那一行)的光标框把行距算在上方,字形在框的下部;
        // 有字的行行距在下方。空行的框顶下移一个行距(ios.md §3.3)。
        let spacing = ps?.lineSpacing ?? 0
        let multiple = ps?.lineHeightMultiple ?? 0
        let multipleExtra = multiple > 1 ? f.lineHeight * (multiple - 1) : 0
        if spacing > 0.5 && r.height >= f.lineHeight + multipleExtra + spacing - 0.5 {
            top += spacing
            box -= spacing
        }
        // 行高倍数加出的高度,TextKit 2 每一行都放在字形上方。
        top += multipleExtra
        box -= multipleExtra
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        let y = ((top + max(0, (box - height) / 2)) * scale).rounded() / scale
        return CGRect(x: r.minX, y: y, width: CaretMetrics.width(fontSize: f.pointSize), height: height)
    }

    /// 光标所在处的字体与段落样式:优先取同一行里光标前的字,其次光标后的字,空行用 typingAttributes。
    private func caretAttributes(at offset: Int) -> [NSAttributedString.Key: Any] {
        let s = textStorage
        let ns = s.string as NSString
        if offset > 0, offset <= s.length, ns.character(at: offset - 1) != 0x0A {
            return s.attributes(at: offset - 1, effectiveRange: nil)
        }
        if offset < s.length, ns.character(at: offset) != 0x0A {
            return s.attributes(at: offset, effectiveRange: nil)
        }
        return typingAttributes
    }

    /// 按当前选区摆放自绘光标:有焦点、可编辑、选区为空时显示。
    func updateCaret() {
        guard caretView.superview === self else { return }
        let range = selectedRange
        guard isFirstResponder, isEditable, range.location != NSNotFound, range.length == 0,
              let end = selectedTextRange?.end else {
            caretView.isShown = false
            return
        }
        let r = caretRect(for: end)
        guard r.height > 0, !r.isNull, !r.isInfinite else {
            caretView.isShown = false
            return
        }
        if caretView.frame != r { caretView.frame = r }
        bringSubviewToFront(caretView)
        caretView.isShown = true
    }

    /// 系统光标随 tintColor 透明;选区底色与拖柄另外着色。
    func tintSelectionViews() {
        for case let display as UITextSelectionDisplayInteraction in interactions {
            display.highlightView.tintColor = selectionColor
            for handle in display.handleViews { handle.tintColor = handleColor }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCaret()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        updateCaret()
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        updateCaret()
        return ok
    }

    // MARK: 粘贴

    /// 换行先统一为 LF(04「粘贴」),内核不收 CR。
    override func paste(_ sender: Any?) {
        guard markedTextRange == nil, let s = pasteboard.string else { return }
        pasteHandler?(LineEndings.lf(s))
    }

    /// 键盘、听写等直接插入的文字同样把 CR 统一为 LF,视图与内核保持一致。
    override func insertText(_ text: String) {
        super.insertText(LineEndings.lf(text))
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return markedTextRange == nil && isEditable && pasteboard.hasStrings
        }
        return super.canPerformAction(action, withSender: sender)
    }

    // MARK: 按键入口

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let h = pressHandler, h.handle(presses, event: event, phase: .began) { return }
        if presses.contains(where: { [.keyboardUpArrow, .keyboardDownArrow].contains($0.key?.keyCode) }) {
            onVerticalArrow?()
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let h = pressHandler, h.handle(presses, event: event, phase: .ended) { return }
        super.pressesEnded(presses, with: event)
    }
}
