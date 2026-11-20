import XCTest
import UIKit
@testable import SumiWrite

final class EditorControllerTests: XCTestCase {
    private var dirs: [URL] = []
    private var suites: [String] = []

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        for s in suites { UserDefaults().removePersistentDomain(forName: s) }
        dirs = []
        suites = []
        super.tearDown()
    }

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("sumi-editor-\(UUID().uuidString)")
        dirs.append(d)
        return d
    }

    private func freshDefaults() -> UserDefaults {
        let name = "sumi.editor.test.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func openReady(_ dir: URL) throws -> (PagePersistence, CorePage) {
        guard case .ready(let p, let page) = PagePersistence.open(directory: dir) else {
            XCTFail("open failed"); throw CocoaError(.fileReadUnknown)
        }
        return (p, page)
    }

    private func makeController(_ dir: URL, defaults: UserDefaults? = nil) throws -> (EditorController, PagePersistence, CorePage) {
        let (p, page) = try openReady(dir)
        let d = defaults ?? freshDefaults()
        let c = EditorController(open: .ready(p, page), prefs: PrefsStore(defaults: d),
                                 selection: SelectionStore(defaults: d), sound: nil)
        c.loadViewIfNeeded()
        return (c, p, page)
    }

    private func type(_ text: String, into c: EditorController) {
        c.textView.text = text
        c.textViewDidChange(c.textView)
    }

    private func paste(_ text: String, into c: EditorController) {
        let board = UIPasteboard.withUniqueName()
        board.string = text
        c.textView.pasteboard = board
        c.textView.paste(nil)
        UIPasteboard.remove(withName: board.name)
    }

    func test_textViewUsesTextKit2AndCoreUndoManager() throws {
        let (c, _, _) = try makeController(tempDir())
        XCTAssertNotNil(c.textView.textLayoutManager)
        XCTAssertTrue(c.textView.undoManager is CoreUndoManager)
        if #available(iOS 18, *) { XCTAssertEqual(c.textView.writingToolsBehavior, .limited) }
    }

    func test_typingReachesCore() throws {
        let dir = tempDir()
        let (c, p, _) = try makeController(dir)
        type("你好", into: c)
        XCTAssertEqual(c.textView.text, "你好")
        p.waitUntilIdle()
        let (p2, page2) = try openReady(dir)
        withExtendedLifetime(p2) { XCTAssertEqual(page2.body(), "你好") }
    }

    func test_rejectedEditResetsTextView() throws {
        let (c, _, _) = try makeController(tempDir())
        paste("```\ncode\n```", into: c)
        let before = c.textView.text ?? ""
        let r = (before as NSString).range(of: "code")
        XCTAssertNotEqual(r.location, NSNotFound, "paste did not reach the text view: \(before)")
        let edited = (before as NSString).replacingCharacters(in: NSRange(location: r.location + 2, length: 0), with: "x")
        type(edited, into: c)
        XCTAssertEqual(c.textView.text, before)
    }

    func test_pasteWithoutStringDoesNothing() throws {
        let (c, _, page) = try makeController(tempDir())
        type("字", into: c)
        let board = UIPasteboard.withUniqueName()
        c.textView.pasteboard = board
        c.textView.paste(nil)
        UIPasteboard.remove(withName: board.name)
        XCTAssertEqual(c.textView.text, "字")
        XCTAssertEqual(page.body(), "字")
    }

    /// 粘贴含 CRLF 或单独 CR 的文字:换行统一为 LF 后交给内核,不被静默丢掉(终审 I-2)。
    func test_pasteNormalizesCarriageReturns() throws {
        let (c, _, page) = try makeController(tempDir())
        paste("# a\r\nb", into: c)
        XCTAssertEqual(page.body(), "# a\nb")
        XCTAssertFalse((c.textView.text ?? "").contains("\r"))
        XCTAssertEqual(c.textView.text, page.rendered().text)
        c.textView.selectedRange = NSRange(location: (c.textView.text as NSString).length, length: 0)
        paste("\rx\ry", into: c)
        XCTAssertEqual(page.body(), "# a\nb\nx\ny")
        XCTAssertEqual(c.textView.text, page.rendered().text)
    }

    func test_undoViaUndoManager() throws {
        let (c, _, _) = try makeController(tempDir())
        type("a", into: c)
        XCTAssertEqual(c.textView.undoManager?.canUndo, true)
        c.textView.undoManager?.undo()
        XCTAssertEqual(c.textView.text, "")
        XCTAssertEqual(c.textView.undoManager?.canRedo, true)
        c.textView.undoManager?.redo()
        XCTAssertEqual(c.textView.text, "a")
        XCTAssertEqual(c.textView.selectedRange, NSRange(location: 1, length: 0))
    }

    func test_caretOverlayIsHiddenFromAccessibility() throws {
        let (c, _, _) = try makeController(tempDir())
        XCTAssertTrue(c.textView.caretView.accessibilityElementsHidden)
        XCTAssertFalse(c.textView.caretView.isAccessibilityElement)
        XCTAssertTrue(c.textView.caretView.isDescendant(of: c.textView))
    }

    func test_caretRectUsesThemeCaretWidth() throws {
        let (c, _, _) = try makeController(tempDir())
        type("字", into: c)
        c.textView.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        c.textView.layoutIfNeeded()
        let rect = c.textView.caretRect(for: c.textView.endOfDocument)
        XCTAssertEqual(rect.width, CaretMetrics.width(fontSize: 22))
        let f = SumiFont.plex.uiFont(size: 22)
        XCTAssertEqual(rect.height, f.ascender - f.descender, accuracy: 0.001)
    }

    func test_saveFailureMakesReadOnly() throws {
        let (c, p, page) = try makeController(tempDir())
        type("留下", into: c)
        p.onFailure?("保存失败")
        XCTAssertEqual(c.statusText, "保存失败")
        XCTAssertFalse(c.textView.isEditable)
        XCTAssertEqual(c.textView.text, "留下")
        type("留下了", into: c)
        XCTAssertEqual(c.textView.text, "留下")
        XCTAssertEqual(page.body(), "留下")
        XCTAssertEqual(c.textView.undoManager?.canUndo, false)
    }

    func test_openFailureIsReadOnly() {
        let d = freshDefaults()
        let c = EditorController(open: .failed("打不开纸页"), prefs: PrefsStore(defaults: d),
                                 selection: SelectionStore(defaults: d), sound: nil)
        c.loadViewIfNeeded()
        XCTAssertEqual(c.statusText, "打不开纸页")
        XCTAssertFalse(c.textView.isEditable)
        XCTAssertEqual(c.textView.undoManager?.canUndo, false)
        c.sceneDidEnterBackground()
    }

    func test_launchRestoresSavedSelection() throws {
        let dir = tempDir()
        let d = freshDefaults()
        let (c, p, _) = try makeController(dir, defaults: d)
        type("一二三四", into: c)
        c.textView.selectedRange = NSRange(location: 2, length: 0)
        c.sceneDidEnterBackground()
        p.waitUntilIdle()
        let (c2, _, _) = try makeController(dir, defaults: d)
        XCTAssertEqual(c2.textView.text, "一二三四")
        XCTAssertEqual(c2.textView.selectedRange, NSRange(location: 2, length: 0))
    }

    /// 放进真窗口并取得焦点,走 UITextView 真实的输入代理链。
    private func hostInWindow(_ c: EditorController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 900)
        window.rootViewController = c
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        XCTAssertTrue(c.textView.becomeFirstResponder())
        return window
    }

    func test_keyboardInputGoesThroughCoreAndCoreUndo() throws {
        let (c, _, page) = try makeController(tempDir())
        let window = try hostInWindow(c)
        defer { window.isHidden = true }
        c.textView.insertText("a")
        c.textView.insertText("b")
        XCTAssertEqual(c.textView.text, "ab")
        XCTAssertEqual(page.body(), "ab")
        XCTAssertTrue(c.textView.caretView.isShown)
        XCTAssertEqual(c.textView.tintColor, .clear)
        c.textView.undoManager?.undo()
        XCTAssertTrue(["", "a"].contains(page.body()), "undo should step back through core history")
        XCTAssertEqual(c.textView.text, page.body())
    }

    func test_quickInputsEnterFocusAndCaretMoveExits() throws {
        let (c, _, _) = try makeController(tempDir())
        let window = try hostInWindow(c)
        defer { window.isHidden = true }
        for ch in ["一", "二", "三"] { c.textView.insertText(ch) }
        XCTAssertNil(c.textView.lockedOffsetY, "three inputs are below the threshold")
        c.textView.insertText("四")
        XCTAssertNotNil(c.textView.lockedOffsetY, "the fourth input within 2 s enters focus")
        c.textView.selectedRange = NSRange(location: 0, length: 0)
        XCTAssertNil(c.textView.lockedOffsetY, "moving the caret leaves focus")
        c.textView.insertText("五")
        XCTAssertNotNil(c.textView.lockedOffsetY, "the first input after a move returns to focus")
    }

    /// 两段之间隔着空行,在上一段末尾回车:光标留在用户处,接着打的字留在上一段之后(终审 I-1)。
    func test_enterBeforeBlankLineKeepsRealCaret() throws {
        let (c, _, page) = try makeController(tempDir())
        let window = try hostInWindow(c)
        defer { window.isHidden = true }
        type("a\n\nb", into: c)
        c.textView.selectedRange = NSRange(location: 1, length: 0)
        c.textView.insertText("\n")
        XCTAssertEqual(c.textView.text, "a\n\n\nb")
        XCTAssertEqual(page.body(), "a\n\n\nb")
        XCTAssertEqual(c.textView.selectedRange, NSRange(location: 2, length: 0))
        c.textView.insertText("c")
        XCTAssertEqual(page.body(), "a\nc\n\nb")
        XCTAssertEqual(c.textView.selectedRange, NSRange(location: 3, length: 0))
    }

    /// 叠词:`谢|谢` 处再打 `谢`,再退格;光标都留在用户处。
    func test_doubledCharacterKeepsRealCaret() throws {
        let (c, _, page) = try makeController(tempDir())
        let window = try hostInWindow(c)
        defer { window.isHidden = true }
        type("谢谢", into: c)
        c.textView.selectedRange = NSRange(location: 1, length: 0)
        c.textView.insertText("谢")
        XCTAssertEqual(page.body(), "谢谢谢")
        XCTAssertEqual(c.textView.selectedRange, NSRange(location: 2, length: 0))
        c.textView.deleteBackward()
        XCTAssertEqual(page.body(), "谢谢")
        XCTAssertEqual(c.textView.selectedRange, NSRange(location: 1, length: 0))
    }

    /// 键盘或听写直接插入的 CR 同样统一为 LF。
    func test_insertTextNormalizesCarriageReturns() throws {
        let (c, _, page) = try makeController(tempDir())
        let window = try hostInWindow(c)
        defer { window.isHidden = true }
        c.textView.insertText("a\r\nb\rc")
        XCTAssertEqual(page.body(), "a\nb\nc")
        XCTAssertEqual(c.textView.text, "a\nb\nc")
        XCTAssertEqual(c.textView.selectedRange, NSRange(location: 5, length: 0))
    }

    func test_prefsChangePersistsAndRestyles() throws {
        let d = freshDefaults()
        let (c, _, _) = try makeController(tempDir(), defaults: d)
        type("字", into: c)
        XCTAssertEqual(c.view.backgroundColor, ThemeID.dim.background)
        var p = EditorPrefs()
        p.theme = .paper
        p.fontSize = 30
        c.updatePrefs(p)
        XCTAssertEqual(PrefsStore(defaults: d).load(), p)
        XCTAssertEqual(c.view.backgroundColor, ThemeID.paper.background)
        let font = c.textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertEqual(font?.pointSize, 30)
        let color = c.textView.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color, ThemeID.paper.foreground)
    }
}
