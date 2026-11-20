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

    /// 基于 invocation 的注册:经代理发出的消息被吞掉,不崩、不入栈;基于 block 的注册同样不入栈。
    func test_invocationAndBlockRegistrationsAreSwallowed() {
        let m = CoreUndoManager(canUndo: { false }, canRedo: { false }, undo: {}, redo: {})
        let t = Target()
        XCTAssertFalse(m.isUndoRegistrationEnabled)
        let proxy = m.prepare(withInvocationTarget: t) as AnyObject
        _ = proxy.perform(#selector(Target.noop(_:)), with: nil)
        var handled = false
        m.registerUndo(withTarget: t) { _ in handled = true }
        m.setActionName("系统动作")
        XCTAssertEqual(m.undoActionName, "", "nothing may reach the system undo stack")
        XCTAssertFalse(handled)
    }
}
