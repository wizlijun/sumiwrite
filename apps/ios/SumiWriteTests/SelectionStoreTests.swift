import XCTest
@testable import SumiWrite

final class SelectionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() {
        super.setUp()
        suite = "sumi.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func page(_ text: String) throws -> CorePage {
        let p = try CorePage.create(pageId: newPageId())
        if !text.isEmpty { _ = try p.applyEdit(revision: p.revision(), start: 0, length: 0, replacement: text, atMs: 1) }
        return p
    }

    func test_roundTripsCaret() throws {
        let p = try page("abc😀def")
        let s = SelectionStore(defaults: defaults)
        s.save(page: p, range: NSRange(location: 5, length: 0))
        XCTAssertEqual(s.restore(page: p), NSRange(location: 5, length: 0))
    }

    func test_rangeSelectionRoundTrips() throws {
        // (1,3) ends at offset 4, inside the emoji's surrogate pair, so use plain text here.
        let p = try page("abcdef")
        let s = SelectionStore(defaults: defaults)
        s.save(page: p, range: NSRange(location: 1, length: 3))
        XCTAssertEqual(s.restore(page: p), NSRange(location: 1, length: 3))
    }

    func test_foreignOrGarbageAnchorFallsBackToEnd() throws {
        let a = try page("abcdef")
        let b = try page("xy")
        let s = SelectionStore(defaults: defaults)
        s.save(page: a, range: NSRange(location: 3, length: 0))
        XCTAssertEqual(s.restore(page: b), NSRange(location: 2, length: 0))
        defaults.set(Data("garbage".utf8), forKey: "sumi.selection")
        XCTAssertEqual(s.restore(page: b), NSRange(location: 2, length: 0))
    }

    func test_missingAnchorFallsBackToEnd() throws {
        let p = try page("abc")
        XCTAssertEqual(SelectionStore(defaults: defaults).restore(page: p), NSRange(location: 3, length: 0))
    }
}
