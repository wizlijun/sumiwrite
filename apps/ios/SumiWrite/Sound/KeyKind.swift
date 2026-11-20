import Foundation

/// 打字音的按键类别。只按可见文本的前后差异粗分,不涉及 Markdown。
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

    /// 没有变化时返回 `nil`。
    static func classify(before: String, after: String) -> KeyKind? {
        guard let edit = EditDiff.between(before, after) else { return nil }
        let added = edit.replacement
        if added.hasSuffix("\n") { return .enter }
        if added == " " { return .space }
        if added.isEmpty { return .delete }
        // 拼音退格:预编辑文字被替换成它自己更短的前缀。
        let removed = (before as NSString).substring(with: edit.range)
        if added.count < removed.count && removed.hasPrefix(added) { return .delete }
        return .key
    }
}
