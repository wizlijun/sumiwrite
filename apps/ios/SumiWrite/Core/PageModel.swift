import Foundation

/// 每次被接受的事务提交后通知(任务 5 实现持久化)。
protocol CommitSink: AnyObject {
    func committed(_ commit: EditCommit, page: CorePage)
}

enum EditOutcome: Equatable {
    case unchanged
    case accepted(RenderedText, caret: Int)
    case rejected(RenderedText, caret: Int)
}

/// 内核支撑的编辑模型:差异、转义、事务与撤销都由内核完成。
final class PageModel {
    private let page: CorePage
    private weak var sink: CommitSink?
    private let clock: () -> Int64
    private(set) var rendered: RenderedText
    var isWritable = true

    init(page: CorePage, sink: CommitSink?,
         clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.page = page
        self.sink = sink
        self.clock = clock
        self.rendered = page.rendered()
    }

    var canUndo: Bool { page.canUndo() }
    var canRedo: Bool { page.canRedo() }

    func userEdited(visible: String, composing: Bool, caret: Int) -> EditOutcome {
        if composing { return .unchanged }
        if !isWritable { return reject(caret: caret) }
        guard let edit = EditDiff.between(rendered.text, visible) else { return .unchanged }
        do {
            let commit = try page.applyEdit(
                revision: rendered.revision, start: UInt32(edit.range.location),
                length: UInt32(edit.range.length), replacement: edit.replacement, atMs: clock())
            var newCaret = edit.range.location + edit.replacement.utf16.count
            if commit.rendered.text != visible, let fix = EditDiff.between(visible, commit.rendered.text) {
                newCaret = fix.range.location + fix.replacement.utf16.count
            }
            return accept(commit, caret: newCaret)
        } catch {
            return reject(caret: caret)
        }
    }

    func paste(markdown: String, range: NSRange) -> EditOutcome {
        if !isWritable { return reject(caret: range.location) }
        do {
            let commit = try page.pasteMarkdown(
                revision: rendered.revision, start: UInt32(range.location),
                length: UInt32(range.length), markdown: markdown, atMs: clock())
            return accept(commit, caret: changeEnd(rendered.text, commit.rendered.text, fallback: range.location))
        } catch {
            return reject(caret: range.location)
        }
    }

    func undo() -> EditOutcome { history { try page.undo(atMs: clock()) } }
    func redo() -> EditOutcome { history { try page.redo(atMs: clock()) } }

    private func history(_ step: () throws -> EditCommit?) -> EditOutcome {
        if !isWritable { return reject(caret: 0) }
        do {
            guard let commit = try step() else { return .unchanged }
            return accept(commit, caret: changeEnd(rendered.text, commit.rendered.text, fallback: 0))
        } catch {
            return reject(caret: 0)
        }
    }

    private func changeEnd(_ old: String, _ new: String, fallback: Int) -> Int {
        guard let d = EditDiff.between(old, new) else { return fallback }
        return d.range.location + d.replacement.utf16.count
    }

    private func accept(_ commit: EditCommit, caret: Int) -> EditOutcome {
        rendered = commit.rendered
        sink?.committed(commit, page: page)
        return .accepted(rendered, caret: min(max(caret, 0), rendered.text.utf16.count))
    }

    private func reject(caret: Int) -> EditOutcome {
        rendered = page.rendered()
        return .rejected(rendered, caret: min(max(caret, 0), rendered.text.utf16.count))
    }
}
