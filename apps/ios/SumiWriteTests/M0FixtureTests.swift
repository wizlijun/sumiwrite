import XCTest
@testable import SumiWrite

/// M0 验收:Swift 只驱动 FFI,期望值来自 golden.json 或测试自己关闭前取的快照。
final class M0FixtureTests: XCTestCase {
    private struct RustFixture: Decodable {
        let pageId: String
        let epoch: UInt32
        let base: String
        let updates: [String]
        let full: String
    }

    private func rustFixture() throws -> RustFixture {
        try JSONDecoder().decode(RustFixture.self, from: Data(contentsOf: Fixtures.url("yrs-v1.json")))
    }

    private func bytes(_ b64: String) throws -> Data {
        try XCTUnwrap(Data(base64Encoded: b64))
    }

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }

    func test_coreLoads() {
        XCTAssertTrue(coreVersion().hasPrefix("sumi-ios-ffi "))
    }

    func test_rustFixtureForward() throws {
        let f = try rustFixture()
        let page = try CorePage.loadState(pageId: f.pageId, epoch: f.epoch, clientId: 999, state: bytes(f.base))
        for u in f.updates { try page.applyRemote(update: bytes(u)) }
        XCTAssertEqual(try page.snapshot().golden, Fixtures.golden()["rust_forward"])
    }

    func test_rustFixtureReverse() throws {
        let f = try rustFixture()
        let page = try CorePage.loadState(pageId: f.pageId, epoch: f.epoch, clientId: 998, state: bytes(f.base))
        for u in f.updates.reversed() { try page.applyRemote(update: bytes(u)) }
        XCTAssertEqual(try page.snapshot().golden, Fixtures.golden()["rust_reverse"])
    }

    func test_rustFixtureFull() throws {
        let f = try rustFixture()
        let page = try CorePage.loadState(pageId: f.pageId, epoch: f.epoch, clientId: 997, state: bytes(f.full))
        XCTAssertEqual(try page.snapshot().golden, Fixtures.golden()["rust_full"])
    }

    func test_yjsFixture() throws {
        struct YjsFixture: Decodable { let base: String; let update: String }
        let f = try JSONDecoder().decode(YjsFixture.self, from: Data(contentsOf: Fixtures.url("yjs-v1.json")))
        let want = try XCTUnwrap(Fixtures.golden()["yjs"])
        let page = try CorePage.loadState(pageId: want.page_id, epoch: want.epoch, clientId: 996, state: bytes(f.base))
        try page.applyRemote(update: bytes(f.update))
        XCTAssertEqual(try page.snapshot().golden, want)
    }

    func test_readsDesktopStore() throws {
        let db = try tempDir().appendingPathComponent("desktop.sqlite3")
        try FileManager.default.copyItem(at: Fixtures.url("desktop.sqlite3"), to: db)
        let store = try CoreStore.open(path: db.path)
        let ids = try store.pageIds()
        XCTAssertEqual(ids.count, 1)
        let page = try store.loadFresh(pageId: ids[0])
        XCTAssertEqual(try page.snapshot().golden, Fixtures.golden()["desktop"])
    }

    func test_iosWritesAndReopens() throws {
        let db = try tempDir().appendingPathComponent("ios.sqlite3").path
        let pageId = newPageId()
        var store: CoreStore? = try CoreStore.open(path: db)
        let page = try CorePage.create(pageId: pageId)
        try store!.commitInitial(page: page, opId: "op-0")
        var ms: Int64 = 1_763_700_000_000
        var n = 1
        func edit(_ text: String) throws {
            let at = UInt32(page.body().utf16.count)
            let c = try page.applyEdit(revision: page.revision(), start: at, length: 0, replacement: text, atMs: ms)
            try store!.commitDelta(pageId: pageId, epoch: page.epoch(), revision: c.revision, opId: "op-\(n)", update: c.update)
            ms += 1000; n += 1
        }
        for t in ["中文", "😀", "e\u{301}"] { try edit(t) }
        try store!.checkpoint(page: page)
        try edit("\n尾")
        let before = try page.snapshot()
        store = nil

        let reopened = try CoreStore.open(path: db)
        XCTAssertEqual(try reopened.pageIds(), [pageId])
        let after = try reopened.loadFresh(pageId: pageId).snapshot()
        XCTAssertEqual(after.golden, before.golden)
    }

    func test_errorsAreCatchable() throws {
        let page = try CorePage.create(pageId: newPageId())
        let c = try page.applyEdit(revision: page.revision(), start: 0, length: 0, replacement: "😀", atMs: 1_763_700_000_000)
        XCTAssertThrowsError(try page.applyEdit(revision: c.revision &- 1, start: 0, length: 0, replacement: "x", atMs: 1_763_700_001_000)) {
            guard case CoreError.StaleRevision = $0 else { return XCTFail("got \($0)") }
        }
        // "😀" 占两个 UTF-16 单元,在中间(偏移 1)编辑
        XCTAssertThrowsError(try page.applyEdit(revision: page.revision(), start: 1, length: 0, replacement: "x", atMs: 1_763_700_002_000)) {
            guard case CoreError.InvalidOffset = $0 else { return XCTFail("got \($0)") }
        }
    }
}
