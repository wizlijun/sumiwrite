import CoreGraphics
import Foundation

enum CaretMetrics {
    static let period: TimeInterval = 4
    static let minOpacity: CGFloat = 0.25

    /// 宽度为字号 / 11,限制在 2...3 pt。
    static func width(fontSize: CGFloat) -> CGFloat {
        min(3, max(2, fontSize / 11))
    }

    /// 周期 4 秒:前 2 秒从 1 余弦缓动降到 minOpacity,后 2 秒升回 1。
    static func opacity(at t: TimeInterval) -> CGFloat {
        let phase = t.truncatingRemainder(dividingBy: period) / period
        let k = (1 + cos(2 * Double.pi * phase)) / 2
        return minOpacity + (1 - minOpacity) * CGFloat(k)
    }
}
