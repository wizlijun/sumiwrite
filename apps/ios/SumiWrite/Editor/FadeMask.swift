import CoreGraphics
import Foundation

/// 聚焦打字的上下文渐隐:相邻一行约 55%,每远一行再乘 0.55,再乘距离平方衰减的边缘系数;
/// 中线上下半行内不淡(04「聚焦打字」)。
enum FadeMask {
    static func opacity(distance d: CGFloat, lineHeight lh: CGFloat, height H: CGFloat) -> CGFloat {
        guard d > lh / 2 else { return 1 }
        let edge = max(0, 1 - pow(d / (H / 2), 2))
        return pow(0.55, d / lh) * edge
    }
}
