import XCTest
@testable import SumiWrite

final class PagePersistenceTests: XCTestCase {
    private var dirs: [URL] = []

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("sumi-\(UUID().uuidString)")
        dirs.append(d)
        return d
    }

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        dirs = []
        super.tearDown()
    }

    private func openReady(_ dir: URL) throws -> (PagePersistence, CorePage) {
        guard case .ready(let p, let page) = PagePersistence.open(directory: dir) else {
            XCTFail("open failed"); throw CocoaError(.fileReadUnknown)
        }
        return (p, page)
    }

    func test_firstOpenCreatesAndCommitsInitialPage() throws {
        let dir = tempDir()
        let (p, page) = try openReady(dir)
        p.waitUntilIdle()
        let other = try CoreStore.open(path: dir.appendingPathComponent("page.sqlite3").path)
        XCTAssertEqual(try other.pageIds(), [page.pageId()])
    }

    func test_reopenRestoresTypedText() throws {
        let dir = tempDir()
        let (p, page) = try openReady(dir)
        let m = PageModel(page: page, sink: p)
        _ = m.userEdited(visible: "第一行", composing: false, caret: 3)
        _ = m.userEdited(visible: "第一行\n😀", composing: false, caret: 5)
        p.waitUntilIdle()
        let (p2, page2) = try openReady(dir)
        withExtendedLifetime(p2) {
            XCTAssertEqual(page2.body(), page.body())
            XCTAssertEqual(page2.revision(), page.revision())
        }
    }

    func test_checkpointRunsAfterQueuedDeltas() throws {
        let dir = tempDir()
        let (p, page) = try openReady(dir)
        let failed = expectation(description: "onFailure")
        failed.isInverted = true
        p.onFailure = { _ in failed.fulfill() }
        let m = PageModel(page: page, sink: p)
        var text = ""
        for i in 0..<20 {
            text += "字\(i)"
            _ = m.userEdited(visible: text, composing: false, caret: text.utf16.count)
        }
        let done = expectation(description: "completion")
        p.flushAndCheckpoint(page: page) { ok in
            XCTAssertTrue(ok)
            XCTAssertTrue(Thread.isMainThread)
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        wait(for: [failed], timeout: 0.3)
        let (p2, page2) = try openReady(dir)
        withExtendedLifetime(p2) { XCTAssertEqual(page2.body(), page.body()) }
    }

    func test_staleCheckpointIsSkippedNotFailure() throws {
        let dir = tempDir()
        let (p, page) = try openReady(dir)
        let failed = expectation(description: "onFailure")
        failed.isInverted = true
        p.onFailure = { _ in failed.fulfill() }
        _ = try page.applyEdit(revision: page.revision(), start: 0, length: 0, replacement: "x", atMs: 1)
        let done = expectation(description: "completion")
        p.flushAndCheckpoint(page: page) { ok in
            XCTAssertTrue(ok)
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        wait(for: [failed], timeout: 0.3)
    }

    func test_deltaFailureStopsWritesAndReports() throws {
        let dir = tempDir()
        let (p, page) = try openReady(dir)
        let failed = expectation(description: "onFailure")
        var messages: [String] = []
        p.onFailure = { messages.append($0); failed.fulfill() }
        // Injected failure: revision jumps head+5, which the core rejects with StaleRevision.
        let fake = EditCommit(revision: page.revision() + 5, update: Data([1, 2, 3]), rendered: page.rendered())
        p.committed(fake, page: page)
        wait(for: [failed], timeout: 10)
        let m = PageModel(page: page, sink: p)
        _ = m.userEdited(visible: "之后", composing: false, caret: 2)
        _ = m.userEdited(visible: "之后again", composing: false, caret: 7)
        p.waitUntilIdle()
        let spin = expectation(description: "spin")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { spin.fulfill() }
        wait(for: [spin], timeout: 5)
        XCTAssertEqual(messages, ["保存失败"])
        let (p2, page2) = try openReady(dir)
        withExtendedLifetime(p2) { XCTAssertFalse(page2.body().contains("之后")) }
    }

    func test_corruptStoreIsLeftUntouchedAndReadOnly() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("page.sqlite3")
        let garbage = Data((0..<64).map { UInt8(($0 * 37 + 11) & 0xff) })
        try garbage.write(to: file)
        let result = PagePersistence.open(directory: dir)
        guard case .failed(let msg) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(msg, "打不开纸页")
        XCTAssertEqual(try Data(contentsOf: file), garbage)
    }
}
