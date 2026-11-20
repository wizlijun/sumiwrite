import UIKit

/// iPhone Duo 的转轴与折痕(ios.md §3.7):把 `UIHingeInteraction` 加到视图上,转轴每次变化都调 `onChange`。
/// 没有转轴的机型上 `hinge` 一直是 nil,判定因此永远不进入半折。
@available(iOS 27.1, *)
final class DeskObserver {
    private(set) var hinge: HingeState?
    private var interaction: UIHingeInteraction?

    init(view: UIView, onChange: @escaping () -> Void) {
        let interaction = UIHingeInteraction { [weak self] _, update in
            self?.hinge = update.hinge.map { Self.state($0.status) }
            onChange()
        }
        self.interaction = interaction
        view.addInteraction(interaction)
    }

    /// 视图坐标里激活的折痕保留区。
    func divisions(in view: UIView) -> [CGRect] {
        view.reservedRegions(kind: .division).filter(\.isActive).map(\.frame)
    }

    private static func state(_ status: UIHinge.Status) -> HingeState {
        switch status {
        case .closed: return .closed
        case .partiallyOpen: return .partiallyOpen
        case .fullyOpen: return .fullyOpen
        default: return .unknown
        }
    }
}
