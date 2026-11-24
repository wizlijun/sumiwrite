import Foundation

/// 打字音的按键类别。由输入代理按这次的替换判出,或由实体键的按键码判出;不涉及 Markdown。
enum KeyKind: Equatable {
    case key, space, enter, delete

    /// manifest 里对应的 role 名。
    var role: String {
        switch self {
        case .key: "key"
        case .space: "space"
        case .enter: "enter"
        case .delete: "delete"
        }
    }
}
