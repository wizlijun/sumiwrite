import CoreGraphics

enum CaretMetrics {
    /// 宽度为字号 / 11,限制在 2...3 pt。
    static func width(fontSize: CGFloat) -> CGFloat {
        min(3, max(2, fontSize / 11))
    }
}
