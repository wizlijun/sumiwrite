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
    /// 最近一次交给内核 `applyEdit` 的可见区间替换;只供测试读取。
    private(set) var lastSubmitted: TextEdit?

    init(page: CorePage, sink: CommitSink?,
         clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.page = page
        self.sink = sink
        self.clock = clock
        self.rendered = page.rendered()
    }

    /// 正文的 Markdown 原文(内核的 `body()`);编辑面上的文字是去掉标记后的可见文本。
    var markdown: String { page.body() }

    var canUndo: Bool { page.canUndo() }
    var canRedo: Bool { page.canRedo() }

    /// `caret` 是视图在这次编辑后的真实光标(UTF-16)。差异锚在它的左侧;内核接受且正文与视图一致时,
    /// 结果光标就是它,不从差异推算。
    func userEdited(visible: String, composing: Bool, caret: Int) -> EditOutcome {
        if composing { return .unchanged }
        if !isWritable { return reject(caret: caret) }
        guard let diff = EditDiff.between(rendered.text, visible, caret: caret) else { return .unchanged }
        // 拖放、写作工具等不经 `insertText` 的路径也可能带进 CR;交给内核前统一为 LF,视图随后按内核结果对齐。
        let edit = TextEdit(range: diff.range, replacement: LineEndings.lf(diff.replacement))
        do {
            let commit = try page.applyEdit(
                revision: rendered.revision, start: UInt32(edit.range.location),
                length: UInt32(edit.range.length), replacement: edit.replacement, atMs: clock())
            lastSubmitted = edit
            let shown = commit.rendered.text
            let newCaret = shown.utf16.elementsEqual(visible.utf16) ? caret : Self.map(caret, from: visible, to: shown)
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
                length: UInt32(range.length), markdown: LineEndings.lf(markdown), atMs: clock())
            // 选区之后的可见文字不变:光标落在它前面,不靠差异推算(差异在重复字符处会右偏)。
            let tail = rendered.text.utf16.count - NSMaxRange(range)
            return accept(commit, caret: max(range.location, commit.rendered.text.utf16.count - tail))
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

    /// 内核的结果与视图不同(例如换行被统一)时,把视图光标搬到内核文本上:改动之前不动,之后按长度差平移,
    /// 落在改动之内就放到改动末尾。
    private static func map(_ caret: Int, from visible: String, to shown: String) -> Int {
        guard let fix = EditDiff.between(visible, shown) else { return caret }
        if caret < fix.range.location { return caret }
        if caret >= NSMaxRange(fix.range) { return caret + fix.replacement.utf16.count - fix.range.length }
        return fix.range.location + fix.replacement.utf16.count
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
