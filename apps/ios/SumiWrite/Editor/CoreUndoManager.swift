import Foundation

/// 把撤销与重做转发给内核;`UITextView` 自带的注册一律不记,系统撤销栈因此不生效。
/// 三指手势、摇一摇和 ⌘Z / ⇧⌘Z 都经由文本视图的 `undoManager` 走到这里。
final class CoreUndoManager: UndoManager {
    private let canUndoQuery: () -> Bool
    private let canRedoQuery: () -> Bool
    private let performUndo: () -> Void
    private let performRedo: () -> Void

    init(canUndo: @escaping () -> Bool, canRedo: @escaping () -> Bool,
         undo: @escaping () -> Void, redo: @escaping () -> Void) {
        canUndoQuery = canUndo
        canRedoQuery = canRedo
        performUndo = undo
        performRedo = redo
        super.init()
        groupsByEvent = false
        // 关闭注册:基于 invocation 与基于 block 的注册(后者无法在 Swift 里重写)都由系统实现直接丢弃。
        disableUndoRegistration()
    }

    override var canUndo: Bool { canUndoQuery() }
    override var canRedo: Bool { canRedoQuery() }
    override func undo() { performUndo() }
    override func redo() { performRedo() }

    override func registerUndo(withTarget target: Any, selector: Selector, object anObject: Any?) {}
    /// 交回系统代理:注册已关闭,经它发出的消息被系统实现吞掉。不能返回 self——
    /// 那样代理收到的下一条消息会因 unrecognized selector 让进程崩溃。
    override func prepare(withInvocationTarget target: Any) -> Any {
        super.prepare(withInvocationTarget: target)
    }
    override func beginUndoGrouping() {}
    override func endUndoGrouping() {}
    override func removeAllActions() {}
    override func removeAllActions(withTarget target: Any) {}
}
