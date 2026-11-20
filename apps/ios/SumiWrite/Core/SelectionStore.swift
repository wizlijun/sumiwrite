import Foundation

/// 光标锚点:由内核编码,按页存入 UserDefaults;解析失败时回到文末。
struct SelectionStore {
    static let defaultPrefix = "sumi.selection"
    let defaults: UserDefaults
    let prefix: String

    init(defaults: UserDefaults, prefix: String = SelectionStore.defaultPrefix) {
        self.defaults = defaults
        self.prefix = prefix
    }

    /// 每页一个键。
    private func key(_ page: CorePage) -> String { "\(prefix).\(page.pageId())" }

    func save(page: CorePage, range: NSRange) {
        guard let data = try? page.anchorSelection(
            revision: page.revision(), start: UInt32(range.location), length: UInt32(range.length))
        else { return }
        defaults.set(data, forKey: key(page))
    }

    func restore(page: CorePage) -> NSRange {
        let end = NSRange(location: page.rendered().text.utf16.count, length: 0)
        guard let data = defaults.data(forKey: key(page)),
              let r = try? page.resolveSelection(encoded: data) else { return end }
        return NSRange(location: Int(r.start), length: Int(r.length))
    }
}
