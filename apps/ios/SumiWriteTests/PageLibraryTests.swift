import XCTest
@testable import SumiWrite

@MainActor
final class PageLibraryTests: XCTestCase {
    private var dirs: [URL] = []
    private var suites: [String] = []

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        for s in suites { UserDefaults().removePersistentDomain(forName: s) }
        dirs = []
        suites = []
        super.tearDown()
    }

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("sumi-lib-\(UUID().uuidString)")
        dirs.append(d)
        return d
    }

    private func freshDefaults() -> UserDefaults {
        let name = "sumi.lib.test.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func open(_ dir: URL, _ defaults: UserDefaults) throws -> (PageLibrary, PagePersistence, CorePage) {
        guard case .ready(let lib, let p, let page) = PageLibrary.open(directory: dir, defaults: defaults) else {
            XCTFail("open failed"); throw CocoaError(.fileReadUnknown)
        }
        return (lib, p, page)
    }

    /// 依次在当前页之后新建,得到 [A, B, C],当前页为 C。
    private func threePages(_ lib: PageLibrary) throws -> [String] {
        XCTAssertNotNil(lib.newPage())
        XCTAssertNotNil(lib.newPage())
        let ids = lib.live.map(\.id)
        XCTAssertEqual(ids.count, 3)
        return ids
    }

    func test_firstLaunchCreatesOnePage() throws {
        let (lib, _, page) = try open(tempDir(), freshDefaults())
        XCTAssertEqual(lib.position.index, 1)
        XCTAssertEqual(lib.position.count, 1)
        XCTAssertEqual(lib.live.count, 1)
        XCTAssertEqual(lib.currentID, page.pageId())
    }

    func test_nextOnLastCreatesAndPrevOnFirstStays() throws {
        let (lib, _, _) = try open(tempDir(), freshDefaults())
        XCTAssertNotNil(lib.next())
        XCTAssertEqual(lib.position.index, 2)
        XCTAssertEqual(lib.position.count, 2)
        XCTAssertNotNil(lib.prev())
        XCTAssertEqual(lib.position.index, 1)
        XCTAssertEqual(lib.position.count, 2)
        XCTAssertNil(lib.prev())
        XCTAssertEqual(lib.position.index, 1)
        XCTAssertEqual(lib.position.count, 2)
    }

    func test_newPageInsertsAfterCurrent() throws {
        let (lib, p, a) = try open(tempDir(), freshDefaults())
        let b = try XCTUnwrap(lib.newPage())
        XCTAssertNotNil(lib.open(a.pageId()))
        let c = try XCTUnwrap(lib.newPage())
        let fromCore = try p.perform { try $0.pages() }.filter { !$0.deleted }.map(\.id)
        XCTAssertEqual(lib.live.map(\.id), fromCore)
        XCTAssertEqual(lib.live.first?.id, a.pageId())
        let expected = c.pageId() < b.pageId() ? 1 : 2
        XCTAssertEqual(lib.live.firstIndex { $0.id == c.pageId() }, expected)
    }

    func test_trashCurrentGoesToNextThenPrev() throws {
        let (lib, _, _) = try open(tempDir(), freshDefaults())
        let ids = try threePages(lib)
        XCTAssertNotNil(lib.open(ids[1]))
        let toC = lib.moveToTrash(ids[1])
        XCTAssertEqual(toC?.pageId(), ids[2])
        XCTAssertEqual(lib.currentID, ids[2])
        let toA = lib.moveToTrash(ids[2])
        XCTAssertEqual(toA?.pageId(), ids[0])
        XCTAssertEqual(lib.currentID, ids[0])
        XCTAssertEqual(lib.trash.count, 2)
    }

    func test_trashOtherPageKeepsCurrent() throws {
        let (lib, _, _) = try open(tempDir(), freshDefaults())
        let ids = try threePages(lib)
        XCTAssertNil(lib.moveToTrash(ids[0]))
        XCTAssertEqual(lib.currentID, ids[2])
        XCTAssertEqual(lib.live.map(\.id), [ids[1], ids[2]])
    }

    func test_trashOnlyPageCreatesBlank() throws {
        let (lib, _, a) = try open(tempDir(), freshDefaults())
        let fresh = try XCTUnwrap(lib.moveToTrash(a.pageId()))
        XCTAssertNotEqual(fresh.pageId(), a.pageId())
        XCTAssertEqual(lib.currentID, fresh.pageId())
        XCTAssertEqual(lib.position.index, 1)
        XCTAssertEqual(lib.position.count, 1)
        XCTAssertEqual(lib.trash.count, 1)
    }

    func test_restoreReturnsToOriginalSlot() throws {
        let (lib, _, _) = try open(tempDir(), freshDefaults())
        let ids = try threePages(lib)
        XCTAssertNil(lib.moveToTrash(ids[1]))
        XCTAssertEqual(lib.live.map(\.id), [ids[0], ids[2]])
        lib.restore(ids[1])
        XCTAssertEqual(lib.live.map(\.id), ids)
        XCTAssertTrue(lib.trash.isEmpty)
    }

    func test_currentPageRestoredAcrossOpen() throws {
        let dir = tempDir(), d = freshDefaults()
        var bID = ""
        do {
            let (lib, p, a) = try open(dir, d)
            let b = try XCTUnwrap(lib.newPage())
            bID = b.pageId()
            XCTAssertNotEqual(bID, a.pageId())
            p.waitUntilIdle()
        }
        let (lib2, _, page) = try open(dir, d)
        XCTAssertEqual(lib2.currentID, bID)
        XCTAssertEqual(page.pageId(), bID)
    }

    func test_opensMigratedSinglePage() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seed = try CoreStore.open(path: dir.appendingPathComponent("page.sqlite3").path)
        let page = try CorePage.create(pageId: newPageId())
        try seed.commitInitial(page: page, opId: UUID().uuidString)
        let commit = try page.applyEdit(revision: page.revision(), start: 0, length: 0, replacement: "旧", atMs: 1)
        try seed.commitDelta(pageId: page.pageId(), epoch: page.epoch(), revision: commit.revision,
                             opId: UUID().uuidString, update: commit.update)
        // M1 的单页光标键:迁移后应落到这一页的按页键上。
        let legacy = try page.anchorSelection(revision: page.revision(), start: 0, length: 0)
        let defaults = freshDefaults()
        defaults.set(legacy, forKey: "sumi.selection")
        let (lib, _, current) = try open(dir, defaults)
        XCTAssertEqual(lib.position.index, 1)
        XCTAssertEqual(lib.position.count, 1)
        XCTAssertEqual(current.pageId(), page.pageId())
        XCTAssertEqual(current.body(), "旧")
        XCTAssertEqual(SelectionStore(defaults: defaults).restore(page: current),
                       NSRange(location: 0, length: 0))
        XCTAssertNil(defaults.data(forKey: "sumi.selection"))
    }

    func test_legacySelectionDoesNotOverwritePerPageKey() throws {
        let dir = tempDir()
        let defaults = freshDefaults()
        let (lib, p, a) = try open(dir, defaults)
        p.waitUntilIdle()
        _ = try a.applyEdit(revision: a.revision(), start: 0, length: 0, replacement: "旧文", atMs: 1)
        let store = SelectionStore(defaults: defaults)
        store.save(page: a, range: NSRange(location: 1, length: 0))
        defaults.set(Data([1, 2, 3]), forKey: "sumi.selection")
        _ = lib
        let (_, _, again) = try open(dir, defaults)
        XCTAssertEqual(again.pageId(), a.pageId())
        XCTAssertEqual(store.restore(page: a), NSRange(location: 1, length: 0))
        XCTAssertNil(defaults.data(forKey: "sumi.selection"))
    }

    func test_failedWriteBlocksCatalogMutations() throws {
        let (lib, p, a) = try open(tempDir(), freshDefaults())
        XCTAssertThrowsError(try p.perform { _ in throw CoreError.StaleRevision })
        XCTAssertNil(lib.newPage())
        XCTAssertNil(lib.moveToTrash(a.pageId()))
        XCTAssertEqual(lib.live.count, 1)
        XCTAssertTrue(lib.trash.isEmpty)
        let ids = try p.read { try $0.pageIds() }
        XCTAssertEqual(ids, [a.pageId()])
    }
}
