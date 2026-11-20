import XCTest
@testable import SumiWrite

final class FocusTypingTrackerTests: XCTestCase {
    private func feed(_ t: inout FocusTypingTracker, _ times: [TimeInterval]) -> [Bool] {
        times.map { t.recordInput(at: $0) }
    }

    func test_entersOnFourthInputWithinTwoSeconds() {
        var t = FocusTypingTracker()
        XCTAssertEqual(feed(&t, [0, 0.5, 1.0, 1.5]), [false, false, false, true])
        XCTAssertTrue(t.isFocused)
    }

    func test_slidingWindowDropsOldInputs() {
        var t = FocusTypingTracker()
        XCTAssertEqual(feed(&t, [0, 1.9, 2.1, 2.2]), [false, false, false, false])
        XCTAssertTrue(t.recordInput(at: 2.3))
    }

    func test_caretMoveExitsAndNextInputReturnsImmediately() {
        var t = FocusTypingTracker()
        _ = feed(&t, [0, 0.5, 1.0, 1.5])
        t.userMovedCaretOrScrolled()
        XCTAssertFalse(t.isFocused)
        XCTAssertTrue(t.recordInput(at: 10))
    }

    func test_resetRequiresAccumulatingAgain() {
        var t = FocusTypingTracker()
        _ = feed(&t, [0, 0.5, 1.0, 1.5])
        t.reset()
        XCTAssertFalse(t.isFocused)
        XCTAssertEqual(feed(&t, [2, 2.1, 2.2, 2.3]), [false, false, false, true])
    }
}
