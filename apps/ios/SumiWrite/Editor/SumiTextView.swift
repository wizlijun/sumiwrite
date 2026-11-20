import UIKit

/// 可替换的按键入口(给今后的外接键盘输入法 RimeKit 留的口)。返回 `true` 表示这次按键已被处理。
protocol KeyPressHandling: AnyObject {
    func handle(_ presses: Set<UIPress>, event: UIPressesEvent?, phase: UIPress.Phase) -> Bool
}

/// TextKit 2 正文视图:聚焦时的滚动锁、光标框、按键入口与粘贴。光标本身由 `SumiCursorView` 画。
/// 文字的增删、撤销都由 `EditorController` 经内核完成,这里不做。
final class SumiTextView: UITextView {
    /// 注入的内核撤销;`UITextView` 自带的撤销栈因此不生效。
    var coreUndoManager: CoreUndoManager?
    var pressHandler: KeyPressHandling?
    /// 收到要粘贴的字符串;组字中、剪贴板没有字符串时不会调用。
    var pasteHandler: ((String) -> Void)?
    var pasteboard: UIPasteboard = .general
    /// 硬件键盘的上、下方向键(未被 `pressHandler` 接走时)。
    var onArrow: (() -> Void)?

    /// 聚焦打字时锁定的纵向偏移。非 nil 时,系统自发的滚动(插入后自动滚到光标、
    /// 内容尺寸变化时的校正)一律钉回这里;用户手指拖动不受限。
    var pinnedY: CGFloat?

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

    // MARK: 滚动锁

    override var contentOffset: CGPoint {
        get { super.contentOffset }
        set {
            if let p = pinnedY, !userScrolling { super.contentOffset = CGPoint(x: newValue.x, y: p) }
            else { super.contentOffset = newValue }
        }
    }

    override func setContentOffset(_ offset: CGPoint, animated: Bool) {
        if let p = pinnedY, !userScrolling {
            super.setContentOffset(CGPoint(x: offset.x, y: p), animated: false)
        } else {
            super.setContentOffset(offset, animated: animated)
        }
    }

    override func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        if pinnedY != nil && !userScrolling { return }
        super.scrollRectToVisible(rect, animated: animated)
    }

    // MARK: 光标

    override func caretRect(for position: UITextPosition) -> CGRect {
        let r = super.caretRect(for: position)
        guard r.height > 0, !r.isNull, !r.isInfinite else { return r }
        let at = offset(from: beginningOfDocument, to: position)
        let attrs = caretAttributes(at: at)
        guard let f = (attrs[.font] as? UIFont) ?? font else { return r }
        let w = CaretMetrics.width(fontSize: f.pointSize)
        let h = f.ascender - f.descender
        // TextKit 2 给空行(空段落、文末换行后的那一行)的光标框把行距算在了上方,
        // 字形区在框的下部;有字的行则行距在下方。把空行的框顶下移一个行距,
        // 光标就和打出第一个字之后的位置一致。
        var top = r.minY, boxH = r.height
        let spacing = (attrs[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing ?? 0
        if spacing > 0.5 && r.height >= f.lineHeight + spacing - 0.5 {
            top += spacing
            boxH -= spacing
        } else if spacing > 0.5 && isAfterTrailingNewline(at) {
            // 模拟器上文末换行后那一行的框不含行距,紧贴上一行字形;打出字后那一行要下移一个行距。
            top += spacing
        }
        var y = top + max(0, (min(boxH, f.lineHeight) - h) / 2)
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        y = (y * scale).rounded() / scale
        return CGRect(x: r.minX, y: y, width: w, height: h)
    }

    /// 光标在文末、且文末是换行:TextKit 2 的那一行是额外行片段。
    private func isAfterTrailingNewline(_ offset: Int) -> Bool {
        let s = textStorage
        return offset == s.length && offset > 0 && (s.string as NSString).character(at: offset - 1) == 0x0A
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
            onArrow?()
        }
        super.pressesBegan(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let h = pressHandler, h.handle(presses, event: event, phase: .ended) { return }
        super.pressesEnded(presses, with: event)
    }
}
