import Foundation
import os

enum LibraryOpenResult {
    case ready(PageLibrary, PagePersistence, CorePage)
    case failed(String)
}

/// 纸页库:顺序、废纸篓状态、摘要与修改时间都在内核目录里,这里只排调用顺序并记住当前页。
@MainActor
final class PageLibrary: ObservableObject {
    private static let log = Logger(subsystem: "app.sumiwrite", category: "library")
    static let currentKey = "sumi.currentPage"

    @Published private(set) var pages: [PageInfo]
    @Published private(set) var currentID: String

    private let persistence: PagePersistence
    private let defaults: UserDefaults

    private init(persistence: PagePersistence, defaults: UserDefaults, pages: [PageInfo], currentID: String) {
        self.persistence = persistence
        self.defaults = defaults
        self.pages = pages
        self.currentID = currentID
    }

    static func open(directory: URL, defaults: UserDefaults) -> LibraryOpenResult {
        let unreadable = LibraryOpenResult.failed("打不开纸页")
        let file = directory.appendingPathComponent("page.sqlite3")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let persistence = PagePersistence(store: try CoreStore.open(path: file.path))
            let (page, pages): (CorePage, [PageInfo]) = try persistence.perform { store in
                var infos = try store.pages()
                let live = infos.filter { !$0.deleted }
                let saved = defaults.string(forKey: currentKey)
                if let id = live.first(where: { $0.id == saved })?.id ?? live.first?.id {
                    return (try store.loadFresh(pageId: id), infos)
                }
                let created = try store.createPage(after: infos.last?.id, opId: UUID().uuidString)
                infos = try store.pages()
                return (created, infos)
            }
            let library = PageLibrary(persistence: persistence, defaults: defaults,
                                      pages: pages, currentID: page.pageId())
            defaults.set(library.currentID, forKey: currentKey)
            library.migrateLegacySelection()
            return .ready(library, persistence, page)
        } catch {
            log.error("open failed: \(String(describing: error))")
            return unreadable
        }
    }

    /// M1 只有一个全局光标键;迁到当前页的按页键,已有按页键就不覆盖,旧键一律清掉。
    private func migrateLegacySelection() {
        let legacy = SelectionStore.defaultPrefix
        guard let data = defaults.data(forKey: legacy) else { return }
        let perPage = "\(legacy).\(currentID)"
        if defaults.object(forKey: perPage) == nil { defaults.set(data, forKey: perPage) }
        defaults.removeObject(forKey: legacy)
    }

    // MARK: 派生

    /// 目录顺序。
    var live: [PageInfo] { pages.filter { !$0.deleted } }

    /// 按修改时间从新到旧,没有时间的排最后。
    var trash: [PageInfo] {
        pages.enumerated().filter { $0.element.deleted }
            .sorted { a, b in
                switch (a.element.modifiedMs, b.element.modifiedMs) {
                case let (x?, y?) where x != y: return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.offset < b.offset
                }
            }
            .map(\.element)
    }

    var position: (index: Int, count: Int) {
        let l = live
        return ((l.firstIndex { $0.id == currentID } ?? 0) + 1, l.count)
    }

    func refresh() {
        if let fresh = try? persistence.read({ try $0.pages() }) { pages = fresh }
    }

    // MARK: 翻页

    func open(_ id: String) -> CorePage? {
        guard id != currentID, live.contains(where: { $0.id == id }) else { return nil }
        return switchTo(mutating: false) { store in try store.loadFresh(pageId: id) }
    }

    func next() -> CorePage? {
        let l = live
        guard let i = l.firstIndex(where: { $0.id == currentID }) else { return nil }
        return i + 1 < l.count ? open(l[i + 1].id) : newPage()
    }

    func prev() -> CorePage? {
        let l = live
        guard let i = l.firstIndex(where: { $0.id == currentID }), i > 0 else { return nil }
        return open(l[i - 1].id)
    }

    /// 在当前页之后新建一页并打开。
    func newPage() -> CorePage? {
        let after = currentID
        return switchTo { store in try store.createPage(after: after, opId: UUID().uuidString) }
    }

    // MARK: 废纸篓

    /// 删当前页时,目标取其后第一张,没有就取前一张,都没有就新建;目标先备好,再标删除(01 §3.3)。
    /// 只有当前页变了才返回目标页。
    func moveToTrash(_ id: String) -> CorePage? {
        guard live.contains(where: { $0.id == id }) else { return nil }
        if id != currentID {
            _ = switchTo { store in try store.setDeleted(pageId: id, deleted: true); return nil }
            return nil
        }
        let l = live
        let i = l.firstIndex { $0.id == id } ?? 0
        return switchTo { store in
            let target: CorePage
            if i + 1 < l.count { target = try store.loadFresh(pageId: l[i + 1].id) }
            else if i > 0 { target = try store.loadFresh(pageId: l[i - 1].id) }
            else { target = try store.createPage(after: id, opId: UUID().uuidString) }
            try store.setDeleted(pageId: id, deleted: true)
            return target
        }
    }

    func restore(_ id: String) {
        _ = switchTo { store in try store.setDeleted(pageId: id, deleted: false); return nil }
    }

    /// 在持久化队列上执行一次操作,随后重读目录;若产出了目标页就切过去。出错则当前页不变,返回 nil。
    private func switchTo(mutating: Bool = true, _ body: (CoreStore) throws -> CorePage?) -> CorePage? {
        do {
            let run: (CoreStore) throws -> (CorePage?, [PageInfo]) = { store in
                (try body(store), try store.pages())
            }
            // 纯切页只读,读失败不连累写路径;变更走 perform,写入失败后被拒。
            let (page, infos) = mutating ? try persistence.perform(run) : try persistence.read(run)
            pages = infos
            if let page {
                currentID = page.pageId()
                defaults.set(currentID, forKey: Self.currentKey)
            }
            return page
        } catch {
            Self.log.error("library change failed: \(String(describing: error))")
            return nil
        }
    }
}
