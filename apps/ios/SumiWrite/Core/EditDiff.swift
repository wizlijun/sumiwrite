import Foundation

/// 旧可见文本上的一次替换;`range` 为 UTF-16 范围。
struct TextEdit: Equatable {
    let range: NSRange
    let replacement: String
}

/// 只比较可见文本,按字素求公共前缀与后缀;不涉及 Markdown 源码。
enum EditDiff {
    /// `caret` 是新文本里视图编辑后的 UTF-16 光标。给了它,差异就锚在光标左侧:先求后缀,后缀不越过光标;
    /// 再在剩下的部分求前缀。这样在相同字符的连续段里(叠词、连续空行),插入或删除落在用户的光标处,
    /// 不会被推到这一段的最右端。光标在改动左侧(与差异对不上)时,结果仍是正确的差异,只是不再锚在光标上。
    /// 不给 `caret` 时先求前缀、再求后缀。
    static func between(_ old: String, _ new: String, caret: Int? = nil) -> TextEdit? {
        if old == new { return nil }
        let a = Array(old), b = Array(new)
        let limit = min(a.count, b.count)
        var prefix = 0, suffix = 0
        if let caret {
            let suffixLimit = min(limit, b.count - graphemeIndex(b, utf16: caret))
            while suffix < suffixLimit && a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
            while prefix < limit - suffix && a[prefix] == b[prefix] { prefix += 1 }
        } else {
            while prefix < limit && a[prefix] == b[prefix] { prefix += 1 }
            while suffix < limit - prefix && a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        }
        let location = a[..<prefix].reduce(0) { $0 + $1.utf16.count }
        let removed = a[prefix..<(a.count - suffix)].reduce(0) { $0 + $1.utf16.count }
        let replacement = String(b[prefix..<(b.count - suffix)])
        return TextEdit(range: NSRange(location: location, length: removed), replacement: replacement)
    }

    /// UTF-16 偏移之前有几个字素;落在字素中间时算上这个字素,超出范围时夹到两端。
    private static func graphemeIndex(_ chars: [Character], utf16 offset: Int) -> Int {
        var k = 0, u = 0
        while k < chars.count && u < offset {
            u += chars[k].utf16.count
            k += 1
        }
        return k
    }
}
