import XCTest
import UIKit
@testable import SumiWrite

@MainActor
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

    private func openLibrary(_ dir: URL, defaults: UserDefaults) throws -> (PageLibrary, PagePersistence, CorePage) {
        guard case .ready(let lib, let p, let page) = PageLibrary.open(directory: dir, defaults: defaults) else {
            XCTFail("open failed"); throw CocoaError(.fileReadUnknown)
        }
        return (lib, p, page)
    }

    private func openReady(_ dir: URL) throws -> (PagePersistence, CorePage) {
        let (_, p, page) = try openLibrary(dir, defaults: freshDefaults())
        return (p, page)
    }

    private struct Harness {
        let controller: EditorController
        let persistence: PagePersistence
        let page: CorePage
        let library: PageLibrary
        let prefs: PrefsModel
    }

    private func harness(_ dir: URL, defaults: UserDefaults? = nil) throws -> Harness {
        let d = defaults ?? freshDefaults()
        let (lib, p, page) = try openLibrary(dir, defaults: d)
        let prefs = PrefsModel(store: PrefsStore(defaults: d))
        let c = EditorController(persistence: p, page: page, prefs: prefs,
                                 selection: SelectionStore(defaults: d), sound: nil)
        c.loadViewIfNeeded()
        return Harness(controller: c, persistence: p, page: page, library: lib, prefs: prefs)
    }

    private func makeController(_ dir: URL, defaults: UserDefaults? = nil) throws -> (EditorController, PagePersistence, CorePage) {
        let h = try harness(dir, defaults: defaults)
        return (h.controller, h.persistence, h.page)
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

    /// 让主队列上排着的 `async` 跑完(输入后的 `afterEdit` 等)。
    private func drainMain() {
        let done = expectation(description: "main drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    private func keyCommand(_ c: EditorController, _ input: String) throws -> UIKeyCommand {
        try XCTUnwrap(c.keyCommands?.first { $0.input == input }, "no key command for \(input)")
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

    /// 宽 = 字号/11 限 2–3;空行(行距 1.6)的光标框不高于字体行高、按像素对齐,且与该行打出字后的位置一致。
    func test_caretRectWidthAndBlankLine() throws {
        let h = try harness(tempDir())
        let c = h.controller
        c.textView.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        type("字", into: c)
        c.textView.layoutIfNeeded()
        XCTAssertEqual(c.textView.caretRect(for: c.textView.endOfDocument).width, min(3, max(2, 22 / 11)))
        let f22 = SumiFont.plex.uiFont(size: 22)
        XCTAssertEqual(c.textView.caretRect(for: c.textView.endOfDocument).height, f22.ascender - f22.descender, accuracy: 0.001)

        h.prefs.prefs.fontSize = 44
        c.textView.layoutIfNeeded()
        XCTAssertEqual(c.textView.caretRect(for: c.textView.endOfDocument).width, 3)

        h.prefs.prefs.fontSize = 22
        XCTAssertEqual(h.prefs.prefs.lineSpacing, 1.6)
        type("字\n", into: c)
        c.textView.layoutIfNeeded()
        let blank = c.textView.caretRect(for: c.textView.endOfDocument)
        XCTAssertLessThanOrEqual(blank.height, f22.lineHeight)
        let scale = c.textView.traitCollection.displayScale > 0 ? c.textView.traitCollection.displayScale : 1
        XCTAssertEqual((blank.minY * scale).rounded(), blank.minY * scale, accuracy: 1e-6)

        type("字\n字", into: c)
        c.textView.layoutIfNeeded()
        let typed = c.textView.caretRect(for: c.textView.endOfDocument)
        XCTAssertEqual(blank.minY, typed.minY, accuracy: 1, "a blank line's caret sits where the first glyph will")
    }

    func test_fadeOpacityFormula() {
        let lh: CGFloat = 10, H: CGFloat = 200
        XCTAssertEqual(FadeMask.opacity(distance: 0, lineHeight: lh, height: H), 1)
        XCTAssertEqual(FadeMask.opacity(distance: 5, lineHeight: lh, height: H), 1)
        XCTAssertEqual(Double(FadeMask.opacity(distance: 10, lineHeight: lh, height: H)),
                       0.55 * (1 - pow(10.0 / 100, 2)), accuracy: 1e-4)
        XCTAssertEqual(Double(FadeMask.opacity(distance: 10, lineHeight: lh, height: H)), 0.5445, accuracy: 1e-4)
        XCTAssertEqual(FadeMask.opacity(distance: 100, lineHeight: lh, height: H), 0)
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
        let c = EditorController(persistence: nil, page: nil, prefs: PrefsModel(store: PrefsStore(defaults: d)),
                                 selection: SelectionStore(defaults: d), sound: nil)
        c.loadViewIfNeeded()
        XCTAssertEqual(c.statusText, "打不开纸页")
        XCTAssertFalse(c.textView.isEditable)
        XCTAssertEqual(c.textView.undoManager?.canUndo, false)
        c.saveNow()
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
        c.textView.undoManager?.undo()
        XCTAssertTrue(["", "a"].contains(page.body()), "undo should step back through core history")
        XCTAssertEqual(c.textView.text, page.body())
    }

    /// 光标换成主题色的 `SumiCursorView`:不闪烁,呼吸动画挂在窗口里;常亮时摘掉。
    func test_cursorViewInstalled() throws {
        let h = try harness(tempDir())
        let c = h.controller
        let window = try hostInWindow(c)
        defer { window.isHidden = true }
        c.viewDidAppear(false)
        let display = try XCTUnwrap(c.textView.interactions.compactMap { $0 as? UITextSelectionDisplayInteraction }.first)
        let cursor = try XCTUnwrap(display.cursorView as? SumiCursorView)
        XCTAssertEqual(c.textView.tintColor, h.prefs.prefs.theme.foreground)
        XCTAssertFalse(SumiCursorView().isBlinking)
        XCTAssertNotNil(cursor.window)
        XCTAssertNotNil(cursor.layer.animation(forKey: "breath"))
        // 系统按自己的节奏置位 isBlinking、重启闪烁:都不打断呼吸相位。
        cursor.isBlinking = true
        cursor.resetBlinkAnimation()
        XCTAssertNotNil(cursor.layer.animation(forKey: "breath"))
        h.prefs.prefs.caretMotion = .steady
        XCTAssertNil(cursor.layer.animation(forKey: "breath"))
        h.prefs.prefs.theme = .paper
        XCTAssertEqual(c.textView.tintColor, ThemeID.paper.foreground)
    }

    func test_statusBarAndHomeIndicatorHidden() throws {
        let (c, _, _) = try makeController(tempDir())
        XCTAssertTrue(c.prefersStatusBarHidden)
        XCTAssertTrue(c.prefersHomeIndicatorAutoHidden)
    }

    func test_quickInputsEnterFocusAndCaretMoveExits() throws {
        let (c, _, _) = try makeController(tempDir())
        let window = try hostInWindow(c)
        defer { window.isHidden = true }
        var t = Date(timeIntervalSinceReferenceDate: 1000)
        c.now = { t }
        for ch in ["一", "二", "三"] { c.textView.insertText(ch) }
        XCTAssertNil(c.textView.pinnedY, "three inputs are below the threshold")
        c.textView.insertText("四")
        XCTAssertNotNil(c.textView.pinnedY, "the fourth input within 2 s enters focus")
        drainMain()
        t += 1
        c.textView.selectedRange = NSRange(location: 0, length: 0)
        XCTAssertNil(c.textView.pinnedY, "moving the caret leaves focus")
        c.textView.insertText("五")
        XCTAssertNotNil(c.textView.pinnedY, "the first input after a move returns to focus")
    }

    /// 外置键盘下选区通知晚于文字变更:离上次编辑不到 0.5 秒的选区变化仍算跟着输入,不退出聚焦。
    func test_selectionWithinHalfSecondOfEditKeepsFocus() throws {
        let (c, _, _) = try makeController(tempDir())
        let window = try hostInWindow(c)
        defer { window.isHidden = true }
        var t = Date(timeIntervalSinceReferenceDate: 1000)
        c.now = { t }
        for ch in ["一", "二", "三", "四"] { c.textView.insertText(ch) }
        XCTAssertNotNil(c.textView.pinnedY)
        drainMain()
        t += 0.3
        c.textView.selectedRange = NSRange(location: 1, length: 0)
        XCTAssertNotNil(c.textView.pinnedY, "a selection change within 0.5 s of the last edit follows the input")
        drainMain()
        t += 0.3
        c.textView.selectedRange = NSRange(location: 2, length: 0)
        XCTAssertNil(c.textView.pinnedY, "after 0.5 s a selection change is a caret move")
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
        let h = try harness(tempDir(), defaults: d)
        let c = h.controller
        type("字", into: c)
        XCTAssertEqual(c.view.backgroundColor, ThemeID.dim.background)
        var p = EditorPrefs()
        p.theme = .paper
        p.fontSize = 30
        h.prefs.prefs = p
        XCTAssertEqual(PrefsStore(defaults: d).load(), p)
        XCTAssertEqual(c.view.backgroundColor, ThemeID.paper.background)
        let font = c.textView.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertEqual(font?.pointSize, 30)
        let color = c.textView.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color, ThemeID.paper.foreground)
        let ps = c.textView.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let f30 = SumiFont.plex.uiFont(size: 30)
        XCTAssertEqual(ps?.lineSpacing ?? 0, f30.lineHeight * 0.6, accuracy: 0.001)
    }

    // MARK: 硬件键盘

    /// 组字期间九条命令一律不可执行;组字结束后恢复。
    func test_pageCommandsDisabledWhileComposing() throws {
        let (c, _, _) = try makeController(tempDir())
        let window = try hostInWindow(c)
        defer { window.isHidden = true }
        let actions = try XCTUnwrap(c.keyCommands).compactMap(\.action)
        XCTAssertEqual(actions.count, 9)
        c.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertNotNil(c.textView.markedTextRange)
        for a in actions {
            XCTAssertFalse(c.canPerformAction(a, withSender: nil), "\(a) while composing")
        }
        c.textView.unmarkText()
        XCTAssertNil(c.textView.markedTextRange)
        let newPage = try XCTUnwrap(keyCommand(c, "n").action)
        XCTAssertTrue(c.canPerformAction(newPage, withSender: nil))
    }

    func test_fontSizeCommands() throws {
        let h = try harness(tempDir())
        let c = h.controller
        c.perform(try XCTUnwrap(keyCommand(c, "=").action))
        XCTAssertEqual(h.prefs.prefs.fontSize, 24)
        c.perform(try XCTUnwrap(keyCommand(c, "-").action))
        XCTAssertEqual(h.prefs.prefs.fontSize, 22)
        c.perform(try XCTUnwrap(keyCommand(c, "=").action))
        c.perform(try XCTUnwrap(keyCommand(c, "=").action))
        XCTAssertEqual(h.prefs.prefs.fontSize, 26)
        c.perform(try XCTUnwrap(keyCommand(c, "0").action))
        XCTAssertEqual(h.prefs.prefs.fontSize, 22)
    }

    func test_keyCommandsForwardToOnCommand() throws {
        let (c, _, _) = try makeController(tempDir())
        var seen: [EditorCommand] = []
        c.onCommand = { seen.append($0) }
        for input in ["n", "[", "]", "l", ",", UIKeyCommand.inputEscape] {
            c.perform(try XCTUnwrap(keyCommand(c, input).action))
        }
        XCTAssertEqual(seen, [.newPage, .prev, .next, .overview, .appearance, .menu])
        XCTAssertEqual(try keyCommand(c, "l").modifierFlags, [.command, .shift])
        XCTAssertEqual(try keyCommand(c, UIKeyCommand.inputEscape).modifierFlags, [])
        XCTAssertEqual(try keyCommand(c, "n").title, "新建一页")
    }

    // MARK: 切页

    /// 在 A 打字后立刻切到 B 再打字:两页各得其字;切页后光标在文末,不用该页存下的锚点。
    func test_switchThenTypeWritesBothPages() throws {
        let dir = tempDir()
        let h = try harness(dir)
        let c = h.controller
        let window = try hostInWindow(c)
        defer { window.isHidden = true }
        let a = h.page.pageId()
        c.textView.insertText("a")
        let b = try XCTUnwrap(h.library.newPage())
        c.show(page: b)
        XCTAssertEqual(c.textView.text, "")
        XCTAssertEqual(c.textView.selectedRange, NSRange(location: 0, length: 0))
        XCTAssertNil(c.textView.pinnedY)
        c.textView.insertText("b")
        XCTAssertEqual(b.body(), "b")
        h.persistence.waitUntilIdle()

        let (_, p2, _) = try openLibrary(dir, defaults: freshDefaults())
        let reA = try p2.perform { try $0.loadFresh(pageId: a) }
        let reB = try p2.perform { try $0.loadFresh(pageId: b.pageId()) }
        XCTAssertEqual(reA.body(), "a")
        XCTAssertEqual(reB.body(), "b")

        // 回到 A:A 存下的锚点在 0,切页照原型放到文末。
        c.textView.selectedRange = NSRange(location: 0, length: 0)
        c.show(page: try XCTUnwrap(h.library.open(a)))
        XCTAssertEqual(c.textView.text, "a")
        XCTAssertEqual(c.textView.selectedRange, NSRange(location: 1, length: 0))
    }

    func test_canSwitchPageFollowsComposition() throws {
        let (c, _, _) = try makeController(tempDir())
        let window = try hostInWindow(c)
        defer { window.isHidden = true }
        XCTAssertTrue(c.canSwitchPage)
        c.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertFalse(c.canSwitchPage)
        c.textView.unmarkText()
        XCTAssertTrue(c.canSwitchPage)
    }
}
