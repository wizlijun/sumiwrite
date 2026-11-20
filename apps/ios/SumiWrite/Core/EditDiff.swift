import Foundation

/// 旧可见文本上的一次替换;`range` 为 UTF-16 范围。
struct TextEdit: Equatable {
    let range: NSRange
    let replacement: String
}

/// 只比较可见文本,按字素求公共前缀与后缀;不涉及 Markdown 源码。
enum EditDiff {
    static func between(_ old: String, _ new: String) -> TextEdit? {
        if old == new { return nil }
        let a = Array(old), b = Array(new)
        let limit = min(a.count, b.count)
        var prefix = 0
        while prefix < limit && a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix && a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        let location = a[..<prefix].reduce(0) { $0 + $1.utf16.count }
        let removed = a[prefix..<(a.count - suffix)].reduce(0) { $0 + $1.utf16.count }
        let replacement = String(b[prefix..<(b.count - suffix)])
        return TextEdit(range: NSRange(location: location, length: removed), replacement: replacement)
    }
}
