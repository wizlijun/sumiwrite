import XCTest
@testable import SumiWrite

final class PageModelTests: XCTestCase {
    private final class Sink: CommitSink {
        var commits: [EditCommit] = []
        func committed(_ commit: EditCommit, page: CorePage) { commits.append(commit) }
    }

    private func make() throws -> (PageModel, CorePage, Sink) {
        let page = try CorePage.create(pageId: newPageId())
        let sink = Sink()
        return (PageModel(page: page, sink: sink), page, sink)
    }

    private func text(_ o: EditOutcome) -> String? {
        switch o {
        case .accepted(let r, _), .rejected(let r, _): return r.text
        case .unchanged: return nil
        }
    }

    func test_typingCommitsOnceAndRenders() throws {
        let (m, page, sink) = try make()
        let o = m.userEdited(visible: "你好", composing: false, caret: 2)
        guard case .accepted(let r, let caret) = o else { return XCTFail("\(o)") }
        XCTAssertEqual(r.text, "你好")
        XCTAssertEqual(caret, 2)
        XCTAssertEqual(sink.commits.count, 1)
        XCTAssertEqual(page.revision(), 1)
    }

    func test_composingTextIsNeverSubmitted() throws {
        let (m, page, sink) = try make()
        XCTAssertEqual(m.userEdited(visible: "n", composing: true, caret: 1), .unchanged)
        XCTAssertEqual(m.userEdited(visible: "ni", composing: true, caret: 2), .unchanged)
        XCTAssertEqual(sink.commits.count, 0)
        guard case .accepted = m.userEdited(visible: "你", composing: false, caret: 1) else { return XCTFail() }
        XCTAssertEqual(sink.commits.count, 1)
        XCTAssertEqual(page.body(), "你")
    }

    func test_literalMarkdownIsEscaped() throws {
        let (m, page, _) = try make()
        _ = m.userEdited(visible: "# a", composing: false, caret: 3)
        XCTAssertEqual(page.body(), "\\# a")
        XCTAssertEqual(m.rendered.text, "# a")
    }

    func test_pasteMarkdownRendersHeading() throws {
        let (m, _, _) = try make()
        let o = m.paste(markdown: "# 标题", range: NSRange(location: 0, length: 0))
        guard case .accepted = o else { return XCTFail("\(o)") }
        XCTAssertTrue(m.rendered.text.hasPrefix("标题"))
        XCTAssertFalse(m.rendered.text.contains("#"))
        XCTAssertEqual(m.rendered.spans.filter { $0.heading == 1 }.count, 1)
    }

    func test_editInsideProtectedBlockIsRejectedAndReset() throws {
        let (m, _, sink) = try make()
        _ = m.paste(markdown: "```\ncode\n```", range: NSRange(location: 0, length: 0))
        let before = m.rendered.text
        let count = sink.commits.count
        let ns = before as NSString
        let r = ns.range(of: "code")
        XCTAssertNotEqual(r.location, NSNotFound)
        let mid = r.location + 2
        let edited = ns.replacingCharacters(in: NSRange(location: mid, length: 0), with: "x")
        let o = m.userEdited(visible: edited, composing: false, caret: mid + 1)
        guard case .rejected(let rt, _) = o else { return XCTFail("\(o)") }
        XCTAssertEqual(rt.text, before)
        XCTAssertEqual(m.rendered.text, before)
        XCTAssertEqual(sink.commits.count, count)
    }

    func test_staleRevisionIsRejectedAndReset() throws {
        let (m, page, _) = try make()
        _ = try page.applyEdit(revision: page.revision(), start: 0, length: 0, replacement: "zz", atMs: 1)
        let o = m.userEdited(visible: "q", composing: false, caret: 1)
        guard case .rejected(let rt, _) = o else { return XCTFail("\(o)") }
        XCTAssertEqual(rt.text, page.rendered().text)
        XCTAssertEqual(m.rendered.text, "zz")
    }

    func test_undoRedoForwardToCore() throws {
        let (m, page, sink) = try make()
        XCTAssertEqual(m.undo(), .unchanged)
        _ = m.userEdited(visible: "a", composing: false, caret: 1)
        _ = m.userEdited(visible: "ab", composing: false, caret: 2)
        XCTAssertEqual(m.canUndo, page.canUndo())
        guard case .accepted(let u, let uc) = m.undo() else { return XCTFail() }
        XCTAssertEqual(u.text, "a"); XCTAssertEqual(uc, 1)
        XCTAssertEqual(m.canRedo, page.canRedo())
        guard case .accepted(let r, let rc) = m.redo() else { return XCTFail() }
        XCTAssertEqual(r.text, "ab"); XCTAssertEqual(rc, 2)
        XCTAssertEqual(sink.commits.count, 4)
    }

    func test_notWritableRejects() throws {
        let (m, _, sink) = try make()
        m.isWritable = false
        guard case .rejected = m.userEdited(visible: "a", composing: false, caret: 1) else { return XCTFail() }
        XCTAssertEqual(sink.commits.count, 0)
    }

    // MARK: 重复字符处的编辑锚在视图光标上(终审 I-1)

    /// 先把正文打成 `start`,再把视图改成 `visible`、光标在 `caret`;断言交给内核的区间与结果光标。
    private func check(_ start: String, _ visible: String, caret: Int, sent: TextEdit,
                       file: StaticString = #filePath, line: UInt = #line) throws {
        let (m, page, _) = try make()
        guard case .accepted = m.userEdited(visible: start, composing: false, caret: start.utf16.count) else {
            return XCTFail("setup rejected", file: file, line: line)
        }
        let o = m.userEdited(visible: visible, composing: false, caret: caret)
        guard case .accepted(let r, let c) = o else { return XCTFail("\(o)", file: file, line: line) }
        XCTAssertEqual(m.lastSubmitted, sent, file: file, line: line)
        XCTAssertEqual(r.text, visible, file: file, line: line)
        XCTAssertEqual(page.body(), visible, file: file, line: line)
        XCTAssertEqual(c, caret, file: file, line: line)
    }

    private func edit(_ l: Int, _ n: Int, _ r: String) -> TextEdit {
        TextEdit(range: NSRange(location: l, length: n), replacement: r)
    }

    func test_enterAtParagraphEndBeforeBlankLine() throws {
        try check("a\n\nb", "a\n\n\nb", caret: 2, sent: edit(1, 0, "\n"))
    }

    func test_typingDoubledCharacter() throws {
        try check("谢", "谢谢", caret: 2, sent: edit(1, 0, "谢"))
        try check("谢谢", "谢谢谢", caret: 2, sent: edit(1, 0, "谢"))
    }

    func test_backspaceInsideBlankLines() throws {
        try check("a\n\n\nb", "a\n\nb", caret: 2, sent: edit(2, 1, ""))
    }

    func test_backspaceOnDoubledCharacter() throws {
        try check("谢谢谢", "谢谢", caret: 1, sent: edit(1, 1, ""))
    }

    func test_emojiNextToRepeatedCharacter() throws {
        try check("😀aa", "😀aaa", caret: 4, sent: edit(3, 0, "a"))
        try check("😀😀", "😀😀😀", caret: 4, sent: edit(2, 0, "😀"))
        try check("😀😀😀", "😀😀", caret: 2, sent: edit(2, 2, ""))
    }

    /// 粘贴的结果光标落在粘贴内容之后,不因重复字符右偏。
    func test_pasteAfterSameCharacterKeepsCaretAfterPaste() throws {
        let (m, _, _) = try make()
        _ = m.userEdited(visible: "aa", composing: false, caret: 2)
        let o = m.paste(markdown: "a", range: NSRange(location: 1, length: 0))
        guard case .accepted(let r, let c) = o else { return XCTFail("\(o)") }
        XCTAssertEqual(r.text, "aaa")
        XCTAssertEqual(c, 2)
    }
}
