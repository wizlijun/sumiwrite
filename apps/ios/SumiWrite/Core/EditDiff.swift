import Foundation

/// 旧可见文本上的一次替换;`range` 为 UTF-16 范围。
struct TextEdit: Equatable {
    let range: NSRange
    let replacement: String
}

/// 只比较可见文本,在 UTF-16 上求公共前缀与后缀,再把两端退到两边都是字素边界的位置;不涉及 Markdown 源码。
/// 不建字素数组:长页上每一键都要算一次,按字素切分全文是那一键里最贵的一段(ios.md §3.3「每一键的代价」)。
enum EditDiff {
    /// `caret` 是新文本里视图编辑后的 UTF-16 光标。给了它,差异就锚在光标左侧:先求后缀,后缀不越过光标;
    /// 再在剩下的部分求前缀。这样在相同字符的连续段里(叠词、连续空行),插入或删除落在用户的光标处,
    /// 不会被推到这一段的最右端。光标在改动左侧(与差异对不上)时,结果仍是正确的差异,只是不再锚在光标上。
    /// 不给 `caret` 时先求前缀、再求后缀。
    static func between(_ old: String, _ new: String, caret: Int? = nil) -> TextEdit? {
        let a = Array(old.utf16), b = Array(new.utf16)
        if a == b { return nil }
        let limit = min(a.count, b.count)
        var prefix = 0, suffix = 0
        if let caret {
            // 光标落在字素中间时算上这个字素,超出范围时夹到两端。
            var at = min(max(caret, 0), b.count)
            while !isBoundary(new, at, count: b.count) { at += 1 }
            suffix = snapSuffix(old, new, a, b, commonSuffix(a, b, limit: min(limit, b.count - at)))
            prefix = snapPrefix(old, new, a.count, b.count, commonPrefix(a, b, limit: limit - suffix))
        } else {
            prefix = snapPrefix(old, new, a.count, b.count, commonPrefix(a, b, limit: limit))
            suffix = snapSuffix(old, new, a, b, commonSuffix(a, b, limit: limit - prefix))
        }
        let replacement = String(decoding: b[prefix..<(b.count - suffix)], as: UTF16.self)
        return TextEdit(range: NSRange(location: prefix, length: a.count - suffix - prefix), replacement: replacement)
    }

    private static func commonPrefix(_ a: [UInt16], _ b: [UInt16], limit: Int) -> Int {
        var n = 0
        while n < limit && a[n] == b[n] { n += 1 }
        return n
    }

    private static func commonSuffix(_ a: [UInt16], _ b: [UInt16], limit: Int) -> Int {
        var n = 0
        while n < limit && a[a.count - 1 - n] == b[b.count - 1 - n] { n += 1 }
        return n
    }

    /// 退到两边都是字素边界的位置:相同的码元前缀里,字素的切分也相同。
    private static func snapPrefix(_ old: String, _ new: String, _ na: Int, _ nb: Int, _ n: Int) -> Int {
        var n = n
        while n > 0 && !(isBoundary(old, n, count: na) && isBoundary(new, n, count: nb)) { n -= 1 }
        return n
    }

    private static func snapSuffix(_ old: String, _ new: String, _ a: [UInt16], _ b: [UInt16], _ n: Int) -> Int {
        var n = n
        while n > 0 && !(isBoundary(old, a.count - n, count: a.count) && isBoundary(new, b.count - n, count: b.count)) {
            n -= 1
        }
        return n
    }

    /// UTF-16 偏移是否落在字素边界上(两端算)。
    private static func isBoundary(_ s: String, _ offset: Int, count: Int) -> Bool {
        if offset <= 0 || offset >= count { return true }
        return s.utf16.index(s.utf16.startIndex, offsetBy: offset).samePosition(in: s) != nil
    }
}
