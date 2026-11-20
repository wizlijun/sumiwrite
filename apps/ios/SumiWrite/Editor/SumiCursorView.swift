import UIKit

/// 取代系统细光标的主题色竖线。宽 = 字号/11,限 2–3 pt;高 = ascender 到 descender。
/// breathing:4 秒一轮,2 秒渐暗、2 秒渐亮,最低约 0.25。连续输入不重启相位。
final class SumiCursorView: UIView, UITextCursorView {
    var isBlinking: Bool = false   // 系统闪烁不用,用自己的呼吸
    func resetBlinkAnimation() {}  // 故意不重启相位

    var color: UIColor = .white { didSet { backgroundColor = color } }
    var breathing = true { didSet { if oldValue != breathing { applyAnimation() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = color
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyAnimation()
    }

    private func applyAnimation() {
        layer.removeAnimation(forKey: "breath")
        guard breathing, window != nil else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1.0
        a.toValue = 0.25
        a.duration = 2
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.isRemovedOnCompletion = false
        layer.add(a, forKey: "breath")
    }
}
