import XCTest
@testable import SumiWrite

final class CoreUndoManagerTests: XCTestCase {
    private final class Target: NSObject {
        @objc func noop(_ sender: Any?) {}
    }

    func test_forwardsUndoRedoAndQueries() {
        var undos = 0, redos = 0
        var undoable = false
        let m = CoreUndoManager(canUndo: { undoable }, canRedo: { true },
                                undo: { undos += 1 }, redo: { redos += 1 })
        XCTAssertFalse(m.canUndo)
        undoable = true
        XCTAssertTrue(m.canUndo)
        XCTAssertTrue(m.canRedo)
        m.undo()
        m.redo()
        XCTAssertEqual(undos, 1)
        XCTAssertEqual(redos, 1)
    }

    func test_registrationsAreIgnored() {
        var undos = 0
        let m = CoreUndoManager(canUndo: { false }, canRedo: { false },
                                undo: { undos += 1 }, redo: {})
        let t = Target()
        m.beginUndoGrouping()
        m.registerUndo(withTarget: t, selector: #selector(Target.noop(_:)), object: nil)
        m.endUndoGrouping()
        m.removeAllActions()
        m.removeAllActions(withTarget: t)
        XCTAssertFalse(m.canUndo)
        XCTAssertFalse(m.canRedo)
        XCTAssertEqual(undos, 0)
    }
}
