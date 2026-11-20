import CoreGraphics

// iPhone Duo 半折打字(ios.md §3.7)的纯判定:不依赖 iOS 27.1 的类型,所以在任何系统上都能编译和单测。

/// 转轴状态;对应 iOS 27.1 的 `UIHinge.Status`。
enum HingeState {
    case unknown, closed, partiallyOpen, fullyOpen
}

enum DeskPosture {
    /// 半折布局的折痕顶(`bounds` 所在坐标系);不在半折布局时为 nil。
    /// 转轴半开,且有一条横向、落在视图里的折痕保留区,才算半折;拿不到转轴(`hinge` 为 nil)的机型永远是 nil。
    static func foldTop(hinge: HingeState?, divisions: [CGRect], bounds: CGRect) -> CGFloat? {
        guard hinge == .partiallyOpen else { return nil }
        return divisions.first {
            $0.height > 0 && $0.width > $0.height
                && $0.maxX > bounds.minX && $0.minX < bounds.maxX
                && $0.minY > bounds.minY && $0.minY < bounds.maxY
        }?.minY
    }
}
