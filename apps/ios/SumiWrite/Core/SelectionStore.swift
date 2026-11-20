import Foundation

/// 光标锚点:由内核编码,存入 UserDefaults;解析失败时回到文末。
struct SelectionStore {
    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults, key: String = "sumi.selection") {
        self.defaults = defaults
        self.key = key
    }

    func save(page: CorePage, range: NSRange) {
        guard let data = try? page.anchorSelection(
            revision: page.revision(), start: UInt32(range.location), length: UInt32(range.length))
        else { return }
        defaults.set(data, forKey: key)
    }

    func restore(page: CorePage) -> NSRange {
        let end = NSRange(location: page.rendered().text.utf16.count, length: 0)
        guard let data = defaults.data(forKey: key),
              let r = try? page.resolveSelection(encoded: data) else { return end }
        return NSRange(location: Int(r.start), length: Int(r.length))
    }
}
