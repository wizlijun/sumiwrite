import RimeKit
import RimeKitUI
import UIKit

// 实体键盘的内嵌输入法(ios.md §3.6)里 Sumi Write 这一侧不依赖编辑面状态的部分:宿主名、候选行样式、
// 吞下的按键算哪种打字音、候选行要盖住的「下一行」在哪。接线(按键、焦点、切页前上屏、候选行摆放)在
// `EditorController`。

extension RimeHost {
    /// 用户目录、部署时显示的名字都用应用名。
    static var sumiWrite: RimeHost { .app(named: "Sumi Write") }
}

extension RimeCandidateBar.Style {
    /// 与正文同字体同字号;字色取主题前景,次要文字是前景的 65%,高亮用主题强调色(主题没有强调色,用前景),
    /// 底色取主题背景。
    static func sumi(_ prefs: EditorPrefs) -> Self {
        let fg = prefs.theme.foreground
        return Self(font: prefs.font.uiFont(size: CGFloat(prefs.fontSize)), text: fg,
                    muted: fg.withAlphaComponent(0.65), highlight: fg, background: prefs.theme.background)
    }
}

extension KeyKind {
    /// 被内嵌输入法吞下的按键响哪种音:按键码分空格、回车、退格,其余算普通键;修饰键不响(返回 nil)。
    static func of(_ press: UIPress) -> KeyKind? {
        guard let key = press.key else { return .key }
        switch key.keyCode {
        case .keyboardSpacebar: return .space
        case .keyboardReturnOrEnter, .keypadEnter, .keyboardReturn: return .enter
        case .keyboardDeleteOrBackspace, .keyboardDeleteForward: return .delete
        case .keyboardLeftShift, .keyboardRightShift, .keyboardLeftControl, .keyboardRightControl,
             .keyboardLeftAlt, .keyboardRightAlt, .keyboardLeftGUI, .keyboardRightGUI, .keyboardCapsLock:
            return nil
        default: return .key
        }
    }
}

extension UITextView {
    /// 光标所在行的下一行的顶边(文本视图内容坐标)。先确保光标处已排版(TextKit 2 是懒排版,未排版处的位置是估计值)。
    /// 光标在没有排版行的位置(文末换行之后的空行)时,按所在片段的底边加 `pitch` 推算。
    func lineTopBelowCaret(pitch: CGFloat) -> CGFloat? {
        guard let end = selectedTextRange?.end, let tlm = textLayoutManager, let tcm = tlm.textContentManager
        else { return nil }
        let at = offset(from: beginningOfDocument, to: end)
        let doc = tcm.documentRange
        // 文末的位置没有自己的片段:用最后一个字所在的片段(含文末换行后的那一行)。
        guard let loc = tcm.location(doc.location, offsetBy: max(0, at - (at > 0 && end == endOfDocument ? 1 : 0)))
        else { return nil }
        let probe = NSTextRange(location: loc, end: tcm.location(loc, offsetBy: 1)) ?? NSTextRange(location: loc)
        tlm.ensureLayout(for: probe)
        let caret = caretRect(for: end)
        guard caret.height > 0, !caret.isNull, !caret.isInfinite else { return nil }
        let inset = textContainerInset.top
        guard let frag = tlm.textLayoutFragment(for: loc) else { return caret.minY + pitch }
        let frame = frag.layoutFragmentFrame
        let local = caret.midY - inset - frame.minY
        let lines = frag.textLineFragments
        if local >= frame.height {
            // 光标在片段之下(文末换行后的空行,片段里没有它):那一行从片段底边开始。
            return frame.maxY + pitch + inset
        }
        if let i = lines.firstIndex(where: { local < $0.typographicBounds.maxY }), i + 1 < lines.count {
            return frame.minY + lines[i + 1].typographicBounds.minY + inset
        }
        // 片段的最后一行:下一行是下一个片段的顶边(没有下一个片段时就是这个片段的底边)。
        var next: CGFloat?
        tlm.enumerateTextLayoutFragments(from: frag.rangeInElement.endLocation, options: [.ensuresLayout]) { f in
            if f !== frag { next = f.layoutFragmentFrame.minY }
            return false
        }
        return (next ?? frame.maxY) + inset
    }
}

/// 包住宿主交给适配器的输入法:引擎的更新正在落进文字时 `landing` 大于 0。宿主据此分辨一次文字变化
/// 是引擎自己的上屏(如失去活跃时),还是系统输入(ios.md §3.6「打字音」)。其余调用原样转交。
final class RimeLandingProbe: RimeInputDriving {
    private let base: RimeInputDriving
    private(set) var landing = 0
    private var handler: ((RimeUpdate) -> Void)?

    init(_ base: RimeInputDriving) {
        self.base = base
        base.onUpdate = { [weak self] update in
            guard let self else { return }
            landing += 1
            defer { landing -= 1 }
            handler?(update)
        }
    }

    var onUpdate: ((RimeUpdate) -> Void)? {
        get { handler }
        set { handler = newValue }
    }

    var onStatus: ((RimeStatus) -> Void)? {
        get { base.onStatus }
        set { base.onStatus = newValue }
    }

    var status: RimeStatus { base.status }
    var ascii: Bool { base.ascii }
    func setActive(_ on: Bool) { base.setActive(on) }
    func handlePress(_ press: UIPress, began: Bool) -> Bool { base.handlePress(press, began: began) }
    func select(_ index: Int) { base.select(index) }
    func page(next: Bool) { base.page(next: next) }
    func flush() { base.flush() }
    func interrupt() { base.interrupt() }
    func clear() { base.clear() }
    func setAscii(_ on: Bool) { base.setAscii(on) }
}
