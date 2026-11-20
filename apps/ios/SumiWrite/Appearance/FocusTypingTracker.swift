import Foundation

/// 聚焦打字:2 秒滑动窗口内累计 4 次有效输入进入聚焦;移动光标或滚动退出,
/// 之后第一个真实输入立即回到聚焦。
struct FocusTypingTracker {
    static let window: TimeInterval = 2
    static let threshold = 4

    private var inputs: [TimeInterval] = []
    private var resumeOnNextInput = false
    private(set) var isFocused = false

    @discardableResult
    mutating func recordInput(at t: TimeInterval) -> Bool {
        if resumeOnNextInput {
            resumeOnNextInput = false
            inputs = [t]
            isFocused = true
            return true
        }
        inputs.append(t)
        inputs.removeAll { t - $0 > Self.window }
        if inputs.count >= Self.threshold { isFocused = true }
        return isFocused
    }

    mutating func userMovedCaretOrScrolled() {
        if isFocused { resumeOnNextInput = true }
        isFocused = false
        inputs.removeAll()
    }

    mutating func reset() {
        inputs.removeAll()
        resumeOnNextInput = false
        isFocused = false
    }
}
