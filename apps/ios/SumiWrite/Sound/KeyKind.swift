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

    /// 没有变化时返回 `nil`。按 UTF-16 求公共前缀与后缀,不建数组、不分配;耗时随文字长度线性但无额外内存。
    static func classify(before: String, after: String) -> KeyKind? {
        let a = before.utf16, b = after.utf16
        var ai = a.startIndex, bi = b.startIndex
        while ai != a.endIndex, bi != b.endIndex, a[ai] == b[bi] {
            ai = a.index(after: ai)
            bi = b.index(after: bi)
        }
        var ae = a.endIndex, be = b.endIndex
        while ae != ai, be != bi {
            let ap = a.index(before: ae), bp = b.index(before: be)
            guard a[ap] == b[bp] else { break }
            ae = ap
            be = bp
        }
        if ai == ae && bi == be { return nil }
        if bi == be { return .delete }
        let added = b[bi..<be]
        if added.last == 0x0A { return .enter }
        if added.count == 1, added.first == 0x20 { return .space }
        return .key
    }
}
