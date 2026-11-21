import RimeKit
import RimeKitUI
import UIKit
import XCTest
@testable import SumiWrite

/// 假的内嵌输入法:记下编辑面要它做的事,测试经它推更新与状态。与 `RimeInput` 一样,`flush()` 与 `clear()`
/// 都同步回一次更新(`flush`:按原文上屏当前的输入;`clear`:空更新)。
final class FakeRime: RimeInputDriving {
    var onUpdate: ((RimeUpdate) -> Void)?
    var onStatus: ((RimeStatus) -> Void)?
    var status = RimeStatus(state: .ready, keyboard: true)
    var ascii = false
    var active: [Bool] = []
    var flushCount = 0, clearCount = 0, interruptCount = 0
    var selected: [Int] = []
    var paged: [Bool] = []
    /// `handlePress` 吞下的按键。
    var swallowed = Set<ObjectIdentifier>()
    /// 吞下按键时推的更新(模拟引擎对这一键的回应)。
    var onSwallow: ((UIPress) -> Void)?
    /// 正在组字的原文(最后一次推的 `RimeUpdate.input`)。
    var composing = ""

    func setActive(_ on: Bool) { active.append(on) }
    func handlePress(_ press: UIPress, began: Bool) -> Bool {
        guard swallowed.contains(ObjectIdentifier(press)) else { return false }
        if began { onSwallow?(press) }
        return true
    }
    /// 点候选时推的更新(模拟引擎上屏)。
    var onSelect: ((Int) -> Void)?
    func select(_ index: Int) {
        selected.append(index)
        onSelect?(index)
    }
    func page(next: Bool) { paged.append(next) }
    func flush() {
        flushCount += 1
        push(RimeUpdate(commit: composing))
    }
    func interrupt() { interruptCount += 1 }
    func clear() {
        clearCount += 1
        push(RimeUpdate())
    }
    /// 与 `RimeInput.setAscii` 一样随即推一次更新。
    func setAscii(_ on: Bool) {
        ascii = on
        push(RimeUpdate(input: composing, ascii: on))
    }

    func push(_ update: RimeUpdate) {
        composing = update.input
        onUpdate?(update)
    }
    func push(status: RimeStatus) {
        self.status = status
        onStatus?(status)
    }

    /// 组字 `input`(显示为 `input` 本身)。
    func compose(_ input: String, menu: RimeMenu = .empty) {
        push(RimeUpdate(preedit: input, caret: (input as NSString).length, input: input, menu: menu))
    }
}

final class SpySound: TypingSoundPlaying {
    var textSounds: [KeyKind?] = []
    var keySounds: [KeyKind] = []
    func play(before: String, after: String, kind: KeyKind?) {
        // 与 `TypingSound` 一样:文字没变不发声。
        guard KeyKind.classify(before: before, after: after) != nil else { return }
        textSounds.append(kind)
    }
    func play(kind: KeyKind) { keySounds.append(kind) }
    var total: Int { textSounds.count + keySounds.count }
}

/// 没有按键码的按键:只用来经 `pressesBegan` 走一遍按键入口。
private final class BarePress: UIPress {}

/// 有按键码与修饰键的实体键(UIKit 不给测试别的办法造一个)。
final class FakeKey: UIKey {
    let code: UIKeyboardHIDUsage, flags: UIKeyModifierFlags
    init(_ code: UIKeyboardHIDUsage, _ flags: UIKeyModifierFlags) {
        self.code = code
        self.flags = flags
        super.init()
    }
    required init?(coder: NSCoder) { nil }
    override var keyCode: UIKeyboardHIDUsage { code }
    override var modifierFlags: UIKeyModifierFlags { flags }
    override var characters: String { " " }
    override var charactersIgnoringModifiers: String { " " }
}

final class KeyPress: UIPress {
    let fakeKey: FakeKey
    init(_ code: UIKeyboardHIDUsage, _ flags: UIKeyModifierFlags) {
        fakeKey = FakeKey(code, flags)
        super.init()
    }
    override var key: UIKey? { fakeKey }
}

@MainActor
final class RimeIntegrationTests: XCTestCase {
    private var dirs: [URL] = []
    private var suites: [String] = []
    private var windows: [UIWindow] = []
    private var libraries: [PageLibrary] = []

    override func tearDown() {
        for w in windows { w.isHidden = true }
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        for s in suites { UserDefaults().removePersistentDomain(forName: s) }
        windows = []
        dirs = []
        suites = []
        libraries = []
        super.tearDown()
    }

    private struct Harness {
        let controller: EditorController
        let persistence: PagePersistence
        let page: CorePage
        let library: PageLibrary
        let defaults: UserDefaults
        let prefs: PrefsModel
        let rime: FakeRime
        let sound: SpySound
        let window: UIWindow
        @MainActor var textView: SumiTextView { controller.textView }
    }

    /// 编辑面挂在真窗口上并取得焦点,接着假的内嵌输入法(默认接着实体键盘)。
    private func harness(keyboard: Bool = true, configure: ((FakeRime, UserDefaults) -> Void)? = nil) throws -> Harness {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sumi-rime-\(UUID().uuidString)")
        dirs.append(dir)
        let name = "sumi.rime.test.\(UUID().uuidString)"
        suites.append(name)
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        guard case .ready(let lib, let p, let page) = PageLibrary.open(directory: dir, defaults: d) else {
            XCTFail("open failed"); throw CocoaError(.fileReadUnknown)
        }
        libraries.append(lib)
        let rime = FakeRime()
        rime.status = RimeStatus(state: .ready, keyboard: keyboard)
        configure?(rime, d)
        let sound = SpySound()
        let prefs = PrefsModel(store: PrefsStore(defaults: d))
        let c = EditorController(persistence: p, page: page, prefs: prefs,
                                 selection: SelectionStore(defaults: d), sound: sound, rime: rime, rimeDefaults: d)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 900)
        window.rootViewController = c
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        windows.append(window)
        XCTAssertTrue(c.textView.becomeFirstResponder())
        drainMain()
        return Harness(controller: c, persistence: p, page: page, library: lib, defaults: d, prefs: prefs, rime: rime,
                       sound: sound, window: window)
    }

    private func drainMain() {
        let done = expectation(description: "main drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    private func bar(_ h: Harness) throws -> RimeCandidateBar {
        try XCTUnwrap(h.controller.rimeAdapter?.bar, "no candidate bar")
    }

    private func button(_ label: String, in view: UIView) -> UIButton? {
        if let b = view as? UIButton, b.accessibilityLabel == label, !b.isHidden { return b }
        for v in view.subviews { if let b = button(label, in: v) { return b } }
        return nil
    }

    private func selector(_ h: Harness, _ input: String) throws -> Selector {
        try XCTUnwrap(h.controller.keyCommands?.first { $0.input == input }?.action, "no key command for \(input)")
    }

    /// 第 `offset` 个字所在段落的顶边,换到编辑面根视图的坐标里。
    private func paragraphTop(_ h: Harness, offset: Int) throws -> CGFloat {
        let tv = h.textView
        let tlm = try XCTUnwrap(tv.textLayoutManager)
        let tcm = try XCTUnwrap(tlm.textContentManager)
        let loc = try XCTUnwrap(tcm.location(tcm.documentRange.location, offsetBy: offset))
        tlm.ensureLayout(for: tcm.documentRange)
        let frag = try XCTUnwrap(tlm.textLayoutFragment(for: loc))
        let y = frag.layoutFragmentFrame.minY + tv.textContainerInset.top
        return tv.convert(CGPoint(x: 0, y: y), to: h.controller.view).y
    }

    // MARK: 组字与上屏

    /// 正文中间组字:标记文字插在光标处,后文照常;内核里的正文不变。
    func test_compositionDoesNotReachCore() throws {
        let h = try harness()
        h.textView.insertText("前文\n后文")
        XCTAssertEqual(h.page.body(), "前文\n后文")
        h.textView.selectedRange = NSRange(location: 1, length: 0)
        h.rime.compose("nihao")
        XCTAssertNotNil(h.textView.markedTextRange)
        XCTAssertEqual(h.textView.text, "前nihao文\n后文")
        XCTAssertTrue(h.controller.rimeAdapter?.isComposing ?? false)
        h.persistence.waitUntilIdle()
        XCTAssertEqual(h.page.body(), "前文\n后文")
    }

    /// 上屏后内核里的文字与屏幕一致,光标在上屏文字之后。
    func test_commitReachesCore() throws {
        let h = try harness()
        h.textView.insertText("前文\n后文")
        h.textView.selectedRange = NSRange(location: 1, length: 0)
        h.rime.compose("nihao")
        h.rime.push(RimeUpdate(commit: "你好"))
        XCTAssertNil(h.textView.markedTextRange)
        XCTAssertEqual(h.page.body(), "前你好文\n后文")
        XCTAssertEqual(h.textView.text, h.page.rendered().text)
        XCTAssertEqual(h.textView.selectedRange, NSRange(location: 3, length: 0))
    }

    // MARK: 切页

    /// 内置输入法组字时可以切页;切之前按原文上屏进内核。切页类命令放行,字号命令与 Esc 不放行。
    func test_switchPageFlushesBuiltinComposition() throws {
        let h = try harness()
        h.textView.insertText("字")
        h.rime.compose("nihao")
        XCTAssertNotNil(h.textView.markedTextRange)
        XCTAssertTrue(h.controller.canSwitchPage)
        for input in ["n", "[", "]", "l", ","] {
            XCTAssertTrue(h.controller.canPerformAction(try selector(h, input), withSender: nil), input)
        }
        for input in ["=", "-", "0", UIKeyCommand.inputEscape] {
            XCTAssertFalse(h.controller.canPerformAction(try selector(h, input), withSender: nil), input)
        }
        h.controller.prepareToSwitch()
        XCTAssertEqual(h.rime.flushCount, 1)
        XCTAssertNil(h.textView.markedTextRange)
        XCTAssertEqual(h.page.body(), "字nihao")
        // 上屏后再切页:新页里没有残留的组字。
        let b = try XCTUnwrap(h.library.newPage())
        h.controller.show(page: b)
        XCTAssertEqual(h.textView.text, "")
        XCTAssertFalse(h.controller.rimeAdapter?.isComposing ?? true)
    }

    /// 系统输入法组字(适配器没有组字)时照旧拦住切页,也不去上屏。
    func test_systemCompositionStillBlocksSwitch() throws {
        let h = try harness()
        h.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertNotNil(h.textView.markedTextRange)
        XCTAssertFalse(h.controller.rimeAdapter?.isComposing ?? true)
        XCTAssertFalse(h.controller.canSwitchPage)
        XCTAssertFalse(h.controller.canPerformAction(try selector(h, "["), withSender: nil))
        h.controller.prepareToSwitch()
        XCTAssertEqual(h.rime.flushCount, 0)
        XCTAssertNotNil(h.textView.markedTextRange)
    }

    /// 失去焦点:组字按原文上屏进内核。
    func test_focusLossCommitsComposition() throws {
        let h = try harness()
        h.rime.compose("hao")
        XCTAssertTrue(h.textView.resignFirstResponder())
        XCTAssertEqual(h.rime.flushCount, 1)
        XCTAssertEqual(h.page.body(), "hao")
        XCTAssertEqual(h.rime.active.last, false)
    }

    // MARK: 组字期间正文不接受改动

    func test_compositionBlocksTapsPasteAndUndo() throws {
        let h = try harness()
        h.textView.insertText("ab")
        XCTAssertTrue(h.textView.undoManager?.canUndo ?? false)
        let taps = (h.textView.gestureRecognizers ?? []).filter { $0 !== h.textView.panGestureRecognizer }
        XCTAssertFalse(taps.isEmpty)
        h.rime.compose("ni")
        for g in taps { XCTAssertFalse(h.textView.gestureRecognizerShouldBegin(g), "\(g) while composing") }
        XCTAssertTrue(h.textView.gestureRecognizerShouldBegin(h.textView.panGestureRecognizer))
        let board = UIPasteboard.withUniqueName()
        board.string = "粘"
        h.textView.pasteboard = board
        XCTAssertFalse(h.textView.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
        XCTAssertFalse(h.textView.canPerformAction(#selector(UIResponderStandardEditActions.selectAll(_:)), withSender: nil))
        XCTAssertFalse(h.textView.undoManager?.canUndo ?? true)
        UIPasteboard.remove(withName: board.name)
        h.rime.push(RimeUpdate(commit: "你"))
        XCTAssertTrue(taps.contains { h.textView.gestureRecognizerShouldBegin($0) })
        XCTAssertTrue(h.textView.undoManager?.canUndo ?? false)
    }

    // MARK: 候选行

    /// 光标在第 1 行:候选行盖住第 2 行,从正文左缘开始,宽为正文列宽;不在文本视图里,也不在渐隐遮罩的图层里。
    func test_barOverlaysNextLine() throws {
        let h = try harness()
        h.textView.insertText("第一行\n第二行\n第三行")
        h.textView.selectedRange = NSRange(location: 3, length: 0)
        h.controller.view.layoutIfNeeded()
        drainMain()
        let bar = try bar(h)
        XCTAssertFalse(bar.isHidden)
        let line2 = try paragraphTop(h, offset: 4)
        XCTAssertEqual(bar.frame.minY, line2, accuracy: 1)
        let tv = h.textView
        let left = tv.convert(CGPoint(x: tv.textContainerInset.left, y: 0), to: h.controller.view).x
        XCTAssertEqual(bar.frame.minX, left, accuracy: 1)
        XCTAssertEqual(bar.frame.width, tv.bounds.width - tv.textContainerInset.left - tv.textContainerInset.right,
                       accuracy: 1)
        XCTAssertEqual(bar.frame.height, RimeCandidateBar.height(for: bar.style.font), accuracy: 0.5)
        XCTAssertFalse(bar.isDescendant(of: tv))
        var layer: CALayer? = bar.layer
        while let l = layer {
            XCTAssertNil(l.mask, "bar is inside a masked layer: \(l)")
            layer = l.superlayer
        }
        // 候选行在文本视图之上(兄弟视图里排在它后面)。
        XCTAssertTrue(bar.window === h.window)

        // 同一行里打字不动;换行后跟着下移一行。
        let y0 = bar.frame.minY
        h.rime.compose("ni")
        XCTAssertEqual(bar.frame.minY, y0, accuracy: 0.5)
        h.rime.push(RimeUpdate(commit: "你"))
        XCTAssertEqual(bar.frame.minY, y0, accuracy: 0.5)
        h.textView.selectedRange = NSRange(location: 6, length: 0) // 第二行行尾
        drainMain()
        XCTAssertEqual(bar.frame.minY, try paragraphTop(h, offset: 9), accuracy: 1)
    }

    /// 候选行的样式取自主题与正文字体。
    func test_barStyleFollowsTheme() throws {
        let h = try harness()
        let style = try bar(h).style
        let prefs = h.controller.prefs
        XCTAssertEqual(style.font.pointSize, CGFloat(prefs.fontSize))
        XCTAssertEqual(style.font.fontName, prefs.font.uiFont(size: CGFloat(prefs.fontSize)).fontName)
        XCTAssertEqual(style.text, prefs.theme.foreground)
        XCTAssertEqual(style.background, prefs.theme.background)
        XCTAssertEqual(style.muted, prefs.theme.foreground.withAlphaComponent(0.65))
    }

    /// 光标在视区最后一行:正文先上滚,候选行留在视区里。
    func test_barStaysInViewOnLastVisibleLine() throws {
        let h = try harness()
        let tv = h.textView
        tv.insertText(Array(repeating: "一行", count: 60).joined(separator: "\n"))
        // 让光标所在行正好是视区最后一行(系统滚到光标后就是这样),再像打字那样来一次组字。
        h.controller.view.layoutIfNeeded()
        if let tlm = tv.textLayoutManager, let tcm = tlm.textContentManager { tlm.ensureLayout(for: tcm.documentRange) }
        let end = try XCTUnwrap(tv.selectedTextRange?.end)
        let caretInText = tv.caretRect(for: end)
        let lastLine = (caretInText.maxY + 4 - tv.bounds.height).rounded(.up)
        tv.setContentOffset(CGPoint(x: 0, y: lastLine), animated: false)
        drainMain()
        h.rime.compose("ni")
        XCTAssertGreaterThan(tv.contentOffset.y, lastLine, "the text scrolled up to make room for the bar")
        let bar = try bar(h)
        XCTAssertFalse(bar.isHidden)
        let visible = tv.convert(tv.bounds, to: h.controller.view)
        XCTAssertLessThanOrEqual(bar.frame.maxY, visible.maxY + 0.5)
        let caret = tv.convert(tv.caretRect(for: try XCTUnwrap(tv.selectedTextRange?.end)), to: h.controller.view)
        XCTAssertGreaterThanOrEqual(bar.frame.minY, caret.maxY - 0.5, "bar covers the caret line")
        XCTAssertGreaterThanOrEqual(caret.minY, visible.minY)
    }

    /// 没接实体键盘:候选行不出现,输入照旧经内核。
    func test_barHiddenWithoutKeyboard() throws {
        let h = try harness(keyboard: false)
        let bar = try bar(h)
        XCTAssertTrue(bar.isHidden)
        XCTAssertEqual(h.rime.active.last ?? false, false)
        h.textView.insertText("软键盘")
        XCTAssertEqual(h.page.body(), "软键盘")
        // 接上再拔掉:候选行跟着出现、消失。
        h.rime.push(status: RimeStatus(state: .ready, keyboard: true))
        drainMain()
        XCTAssertFalse(bar.isHidden)
        h.rime.push(status: RimeStatus(state: .ready, keyboard: false))
        drainMain()
        XCTAssertTrue(bar.isHidden)
    }

    /// 点候选:点按落在候选行的按钮上(不被文本视图的手势接走),到达 `select`。
    /// 候选用单字:有的机型(如 iPhone Duo 模拟器)给测试窗口加了右侧安全区,候选行窄到放不下两个双字候选。
    func test_candidateTapReachesSelect() throws {
        let h = try harness()
        h.rime.compose("ni", menu: RimeMenu(rows: [RimeCandidate(index: 0, label: "1", text: "你"),
                                                   RimeCandidate(index: 1, label: "2", text: "拟")], cursor: 0))
        let bar = try bar(h)
        bar.layoutIfNeeded()
        let b = try XCTUnwrap(button("拟", in: bar))
        let point = b.convert(CGPoint(x: b.bounds.midX, y: b.bounds.midY), to: h.window)
        let hit = try XCTUnwrap(h.window.hitTest(point, with: nil))
        XCTAssertTrue(hit === b || hit.isDescendant(of: b), "tap lands on \(hit)")
        b.sendActions(for: .touchUpInside)
        XCTAssertEqual(h.rime.selected, [1])
    }

    /// 选菜单项(点状态字弹出的系统菜单;测试里直接调菜单项的回调),等主队列下一轮。
    private func choose(_ choice: RimeInputChoice, in bar: RimeCandidateBar) {
        bar.onChoose?(choice)
        drainMain()
        bar.layoutIfNeeded()
    }

    /// 状态字:候选行右端只有一个字,点它弹出菜单;点按落在它上面(不被文本视图接走)。
    func test_statusCharacterOpensMenu() throws {
        let h = try harness()
        h.rime.compose("ni", menu: RimeMenu(rows: [RimeCandidate(index: 0, label: "1", text: "你")], cursor: 0))
        let bar = try bar(h)
        bar.layoutIfNeeded()
        XCTAssertTrue(bar.statusMenu)
        XCTAssertNil(button("切换内置输入法", in: bar))
        let status = try XCTUnwrap(button("切换输入法", in: bar))
        XCTAssertEqual(status.currentAttributedTitle?.string, "中")
        XCTAssertTrue(status.showsMenuAsPrimaryAction)
        XCTAssertEqual(status.menu?.children.map(\.title), ["中文", "英文", "系统输入法"])
        let point = status.convert(CGPoint(x: status.bounds.midX, y: status.bounds.midY), to: h.window)
        let hit = try XCTUnwrap(h.window.hitTest(point, with: nil))
        XCTAssertTrue(hit === status || hit.isDescendant(of: status), "tap lands on \(hit)")
    }

    /// 选「系统输入法」:组字清掉,停用;再选「中文」切回。选择记在 `rime.builtin`。
    func test_toggleTapSwitchesAndPersists() throws {
        let h = try harness()
        h.rime.compose("ni")
        let bar = try bar(h)
        bar.layoutIfNeeded()
        choose(.system, in: bar)
        XCTAssertEqual(h.rime.clearCount, 1)
        XCTAssertNil(h.textView.markedTextRange)
        XCTAssertEqual(h.page.body(), "")
        XCTAssertEqual(h.rime.active.last, false)
        XCTAssertEqual(h.defaults.object(forKey: RimeTextViewAdapter.builtinKey) as? Bool, false)
        XCTAssertFalse(bar.isHidden, "the bar stays so the built-in input method can be chosen back")
        XCTAssertEqual(button("切换输入法", in: bar)?.currentAttributedTitle?.string, "系")
        choose(.chinese, in: bar)
        XCTAssertEqual(h.rime.active.last, true)
        XCTAssertEqual(h.defaults.object(forKey: RimeTextViewAdapter.builtinKey) as? Bool, true)
        XCTAssertEqual(button("切换输入法", in: bar)?.currentAttributedTitle?.string, "中")
    }

    /// 选「英文」:引擎切到 ascii_mode,状态字随即变「英」;Shift 切回时(引擎推 ascii=false)跟着变「中」。
    func test_menuEnglishSetsAsciiAndFollowsShift() throws {
        let h = try harness()
        let bar = try bar(h)
        bar.layoutIfNeeded()
        choose(.english, in: bar)
        XCTAssertTrue(h.rime.ascii)
        XCTAssertEqual(button("切换输入法", in: bar)?.currentAttributedTitle?.string, "英")
        h.rime.push(RimeUpdate(ascii: false))
        bar.layoutIfNeeded()
        XCTAssertEqual(button("切换输入法", in: bar)?.currentAttributedTitle?.string, "中")
    }

    /// 空闲(无组字、无候选、无提示):候选行只画状态字那一块,点在下一行别处落到正文上;正文底下照样留出候选行的高度。
    func test_idleBarShrinksToStatusCharacter() throws {
        let h = try harness()
        h.textView.insertText("第一行\n第二行\n第三行")
        h.textView.selectedRange = NSRange(location: 3, length: 0)
        h.controller.view.layoutIfNeeded()
        drainMain()
        let bar = try bar(h)
        bar.layoutIfNeeded()
        XCTAssertFalse(bar.isHidden)
        XCTAssertFalse(bar.isOpaque)
        let status = try XCTUnwrap(button("切换输入法", in: bar))
        let left = bar.convert(CGPoint(x: 20, y: bar.bounds.midY), to: h.window)
        let hit = try XCTUnwrap(h.window.hitTest(left, with: nil))
        XCTAssertTrue(hit === h.textView || hit.isDescendant(of: h.textView), "tap lands on \(hit)")
        let onStatus = status.convert(CGPoint(x: status.bounds.midX, y: 4), to: h.window)
        XCTAssertTrue(try XCTUnwrap(h.window.hitTest(onStatus, with: nil)) === status)
        // 小块只比状态字宽一点、与候选行同高;点在画出来的小块紧左边、正下方都落到正文上。
        XCTAssertLessThan(status.bounds.width, 44)
        let block = try XCTUnwrap(bar.subviews.first { !$0.isHidden && $0.backgroundColor == bar.style.background })
        XCTAssertEqual(block.frame.height, bar.bounds.height, accuracy: 0.5)
        for (name, p) in [("left", CGPoint(x: block.frame.minX - 1, y: block.frame.midY)),
                          ("below", CGPoint(x: block.frame.midX, y: block.frame.maxY + 1))] {
            let hit = try XCTUnwrap(h.window.hitTest(bar.convert(p, to: h.window), with: nil))
            XCTAssertTrue(hit === h.textView || hit.isDescendant(of: h.textView), "tap \(name) lands on \(hit)")
        }
        // 小块右边是正文列以外的页边:点在那里也弹菜单,点击区在页边里补到 44pt 宽。
        let margin = h.controller.view.bounds.maxX - bar.frame.maxX
        XCTAssertGreaterThan(margin, 0)
        let reach = min(margin, 44 - block.frame.width)
        let right = bar.convert(CGPoint(x: block.frame.maxX + reach - 1, y: block.frame.midY), to: h.window)
        XCTAssertTrue(try XCTUnwrap(h.window.hitTest(right, with: nil)) === status)
        XCTAssertEqual(h.textView.contentInset.bottom, RimeCandidateBar.height(for: bar.style.font), accuracy: 0.5)
        // 组字时整行不透明。
        h.rime.compose("ni", menu: RimeMenu(rows: [RimeCandidate(index: 0, label: "1", text: "你")], cursor: 0))
        bar.layoutIfNeeded()
        XCTAssertTrue(bar.isOpaque)
    }

    /// 一篇长页:`count` 段会自动换行的长段落(中英混排,每段约 `paragraph.count` 字)。
    private func longPage(_ count: Int) -> String {
        let paragraph = String(repeating: "这是一段比较长的文字,用来让它在屏幕上自动换行。Some English words that wrap as well. ",
                               count: 4)
        return Array(repeating: paragraph, count: count).joined(separator: "\n") + "\n"
    }

    /// 光标框在窗口里的位置(含滚动)。
    private func caretInWindow(_ h: Harness) throws -> CGRect {
        let tv = h.textView
        return tv.convert(tv.caretRect(for: try XCTUnwrap(tv.selectedTextRange?.end)), to: h.window)
    }

    /// 聚焦打字之后 ⌘N 新建一页,再 ⌘V 粘进一篇长页(经 `SumiTextView.paste`,由内核改字,不走 `UITextView`
    /// 自己插入时的滚动):粘完光标在文末、在可见区里,候选行(空闲小块)显示,点得到状态字。
    /// sim-rime 按 builtin、english、entype 的顺序跑时 x00 停在页首、候选行隐去,就是这条。
    func test_pastingALongPageScrollsTheCaretIntoView() throws {
        let h = try harness()
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }
        board.string = longPage(60)
        h.textView.pasteboard = board
        for c in "abcde" { h.textView.insertText(String(c)); drainMain() } // 进入聚焦打字
        h.controller.show(page: try XCTUnwrap(h.library.newPage()))        // ⌘N
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        h.textView.paste(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        h.controller.view.layoutIfNeeded()
        let tv = h.textView
        XCTAssertEqual(tv.selectedRange.location, tv.textStorage.length)
        let caret = tv.caretRect(for: try XCTUnwrap(tv.selectedTextRange?.end))
        let top = tv.contentOffset.y + (tv.pinnedY == nil ? tv.contentInset.top : 0)
        let bottom = tv.contentOffset.y + tv.bounds.height - (tv.pinnedY == nil ? tv.contentInset.bottom : 0)
        XCTAssertTrue(caret.minY >= top - 0.5 && caret.maxY <= bottom + 0.5, "caret \(caret.minY)…\(caret.maxY) outside \(top)…\(bottom)")
        XCTAssertEqual(try bar(h).alpha, 1)
    }

    /// 光标在文本视图的可见区里(聚焦打字时留白属于可见区,平时不算)。
    private func caretVisible(_ tv: SumiTextView) -> Bool {
        guard let end = tv.selectedTextRange?.end else { return false }
        let caret = tv.caretRect(for: end)
        let top = tv.contentOffset.y + tv.contentInset.top - (tv.pinnedY == nil ? 0 : tv.contentInset.top)
        let bottom = tv.contentOffset.y + tv.bounds.height - (tv.pinnedY == nil ? tv.contentInset.bottom : 0)
        return caret.minY >= top - 0.5 && caret.maxY <= bottom + 0.5
    }

    /// 切到英文后打字(菜单切和单按 Shift 切两条路),长页、长段落自动换行:
    /// - 切换前后光标在窗口里的位置不变;
    /// - 文本视图一直是第一响应者,每打一键光标都在可见区里,候选行(空闲小块)显示;
    /// - 进入聚焦打字之前,留白与候选行高度不变;进入之后,同一行里打字不滚动,留白与候选行位置不变。
    /// 真机「切英文后光标丢失、上下跳动」:TextKit 2 对没排过的段落用估算高度,光标位置随排版补全而变,
    /// 滚动按估算值算,光标落到可见区外。
    func test_englishTypingKeepsCaretVisibleAndStill() throws {
        for viaMenu in [true, false] {
            let h = try harness()
            h.textView.insertText(longPage(30))
            let bar = try bar(h)
            // 等粘贴后画面停稳:模拟器可能先弹软键盘、再把光标滚进可见区,iOS 27 上要 1 秒左右,不能按固定时长等。
            // 停稳 = 光标可见、候选行显示,且视区高度、滚动位置、留白连续 0.3 秒不变。
            let deadline = Date().addingTimeInterval(4)
            var last: [CGFloat] = []
            var still = 0
            repeat {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                h.controller.view.layoutIfNeeded()
                let tv = h.textView
                let now = [tv.bounds.height, tv.contentOffset.y, tv.contentInset.top, tv.contentInset.bottom]
                still = now == last ? still + 1 : 0
                last = now
            } while !(caretVisible(h.textView) && bar.alpha == 1 && still >= 6) && Date() < deadline
            XCTAssertTrue(caretVisible(h.textView), "caret not revealed after paste, via menu: \(viaMenu)")
            let before = try caretInWindow(h)
            if viaMenu {
                choose(.english, in: bar)
            } else {
                h.rime.ascii = true
                h.rime.push(RimeUpdate(ascii: true)) // 单按左 Shift:引擎切到英文后推的那次更新
                drainMain()
                bar.layoutIfNeeded()
            }
            h.controller.view.layoutIfNeeded()
            let switched = try caretInWindow(h)
            XCTAssertEqual(switched.minY, before.minY, accuracy: 0.5, "caret moved on switch, via menu: \(viaMenu)")
            XCTAssertEqual(switched.minX, before.minX, accuracy: 0.5, "caret moved on switch, via menu: \(viaMenu)")
            XCTAssertTrue(h.textView.isFirstResponder)
            XCTAssertEqual(button("切换输入法", in: bar)?.currentAttributedTitle?.string, "英")
            let resting = (inset: h.textView.contentInset, barHeight: bar.frame.height)
            var pinned: (offset: CGFloat, inset: UIEdgeInsets, bar: CGRect)?
            for c in "The quick, brown fox " {
                let press = BarePress()
                h.rime.swallowed.insert(ObjectIdentifier(press))
                h.rime.onSwallow = { [weak rime = h.rime] _ in rime?.push(RimeUpdate(commit: String(c), ascii: true)) }
                h.textView.pressesBegan([press], with: nil)
                h.textView.pressesEnded([press], with: nil)
                drainMain()
                h.controller.view.layoutIfNeeded()
                let at = "after \(c), via menu: \(viaMenu)"
                let tv = h.textView
                XCTAssertTrue(tv.isFirstResponder, at)
                let caret = tv.caretRect(for: try XCTUnwrap(tv.selectedTextRange?.end))
                XCTAssertTrue(caretVisible(tv), "caret \(caret.minY)…\(caret.maxY) outside \(tv.contentOffset.y)+\(tv.bounds.height), " + at)
                XCTAssertEqual(bar.alpha, 1, at)
                XCTAssertFalse(bar.isOpaque, "idle chip while typing English, " + at)
                if tv.pinnedY == nil {
                    XCTAssertEqual(tv.contentInset, resting.inset, "before focus, " + at)
                    XCTAssertEqual(bar.frame.height, resting.barHeight, accuracy: 0.5, "before focus, " + at)
                } else if let p = pinned {
                    XCTAssertEqual(tv.contentOffset.y, p.offset, accuracy: 0.5, at)
                    XCTAssertEqual(tv.contentInset, p.inset, at)
                    XCTAssertEqual(bar.frame.minY, p.bar.minY, accuracy: 0.5, at)
                    XCTAssertEqual(bar.frame.height, p.bar.height, accuracy: 0.5, at)
                } else {
                    pinned = (tv.contentOffset.y, tv.contentInset, bar.frame)
                }
            }
            XCTAssertNotNil(pinned, "focus typing engaged")
            XCTAssertTrue(h.page.body().hasSuffix("The quick, brown fox "))
        }
    }

    /// 重开应用:选「系」的记录还在,接着实体键盘也不启用。
    func test_systemChoiceSurvivesRelaunch() throws {
        let h = try harness { _, d in d.set(false, forKey: RimeTextViewAdapter.builtinKey) }
        XCTAssertEqual(h.controller.rimeAdapter?.builtin, false)
        XCTAssertEqual(h.rime.active.last ?? false, false)
    }

    // MARK: 打字音

    /// 引擎吞下的按键:上屏后打字音只响一次(不再按文字变化另响)。
    func test_swallowedKeyPlaysSound() throws {
        let h = try harness()
        let press = BarePress()
        h.rime.swallowed.insert(ObjectIdentifier(press))
        h.rime.onSwallow = { [weak rime = h.rime] _ in rime?.push(RimeUpdate(commit: "你")) }
        h.textView.pressesBegan([press], with: nil)
        XCTAssertEqual(h.page.body(), "你")
        XCTAssertEqual(h.sound.keySounds, [.key])
        XCTAssertEqual(h.sound.total, 1)
        h.textView.pressesEnded([press], with: nil)
        XCTAssertEqual(h.sound.total, 1, "a release makes no sound")
    }

    /// 吞下的按键只改了候选(文字没变)也发声。
    func test_swallowedKeyWithoutTextChangePlaysSound() throws {
        let h = try harness()
        h.rime.compose("ni")
        let before = h.sound.total
        let press = BarePress()
        h.rime.swallowed.insert(ObjectIdentifier(press))
        h.rime.onSwallow = { [weak rime = h.rime] _ in
            rime?.push(RimeUpdate(preedit: "ni", caret: 2, input: "ni",
                                  menu: RimeMenu(rows: [RimeCandidate(index: 0, label: "1", text: "你")], cursor: 0)))
        }
        h.textView.pressesBegan([press], with: nil)
        XCTAssertEqual(h.sound.total, before + 1)
    }

    /// 切页前的上屏不发声(切换不算打字)。
    func test_flushBeforeSwitchIsSilent() throws {
        let h = try harness()
        h.rime.compose("ni")
        let before = h.sound.total
        h.controller.prepareToSwitch()
        XCTAssertEqual(h.page.body(), "ni")
        XCTAssertEqual(h.sound.total, before)
    }

    // MARK: 复审修正

    private func typed(_ h: Harness) -> (() -> Int) {
        var count = 0
        h.controller.onCommand = { if $0 == .typing { count += 1 } }
        return { count }
    }

    /// 切页前的上屏不算打字:不发 typing,不进聚焦打字(复审 1)。
    func test_switchFlushIsNotTyping() throws {
        let h = try harness()
        h.rime.compose("ni")
        let typing = typed(h)
        h.controller.prepareToSwitch()
        XCTAssertEqual(h.page.body(), "ni")
        XCTAssertEqual(typing(), 0)
    }

    /// 切换中 / 英的快捷键取设置里的值(默认 Control + 空格),改了随即传给适配器(ios.md §3.6)。
    func test_switchShortcutFollowsPrefs() throws {
        let h = try harness()
        XCTAssertEqual(h.controller.rimeAdapter?.switchShortcut, .controlSpace)
        h.prefs.prefs.switchShortcut = .off
        XCTAssertEqual(h.controller.rimeAdapter?.switchShortcut, .off)
    }

    /// 组字中按 Control + 空格:组字按原文上屏进内核,切到英文;空格不进正文,不发声,不算打字。
    func test_switchShortcutIsNotTyping() throws {
        let h = try harness()
        h.rime.compose("ni")
        let typing = typed(h)
        let sounds = h.sound.total
        let press = KeyPress(.keyboardSpacebar, .control)
        h.textView.pressesBegan([press], with: nil)
        h.textView.pressesEnded([press], with: nil)
        drainMain()
        XCTAssertEqual(h.page.body(), "ni")
        XCTAssertTrue(h.rime.ascii)
        XCTAssertEqual(typing(), 0)
        XCTAssertEqual(h.sound.total, sounds)
    }

    /// 失去焦点时的上屏也不算打字:不进聚焦打字的计数、不发声,文字照样经 textViewDidChange 进内核(终审 Minor 1)。
    func test_blurFlushIsNotTyping() throws {
        let h = try harness()
        for ch in ["一", "二"] { h.textView.insertText(ch) }
        h.rime.compose("hao")
        let typing = typed(h)
        let sounds = h.sound.total
        XCTAssertTrue(h.textView.resignFirstResponder())
        XCTAssertEqual(h.rime.flushCount, 1)
        XCTAssertEqual(h.page.body(), "一二hao", "flushed text reached the core")
        XCTAssertEqual(typing(), 0)
        XCTAssertEqual(h.sound.total, sounds)
        // 失焦上屏若算第三次输入,重新取得焦点后再打一个字就会满四次进聚焦;不算则还差一次。
        XCTAssertTrue(h.textView.becomeFirstResponder())
        h.textView.insertText("四")
        XCTAssertNil(h.textView.pinnedY, "the blur flush was not the third input")
    }

    /// 保存失败后编辑面不可编辑:组字结束,引擎停用,按键原样交给系统,不发声(复审 2)。
    func test_readOnlyKeepsEngineOff() throws {
        let h = try harness()
        h.rime.compose("ni")
        h.persistence.onFailure?("保存失败")
        XCTAssertFalse(h.textView.isEditable)
        XCTAssertEqual(h.rime.active.last, false)
        XCTAssertFalse(h.controller.rimeAdapter?.isComposing ?? true)
        XCTAssertNil(h.textView.markedTextRange)
        let press = BarePress()
        h.rime.swallowed.insert(ObjectIdentifier(press))
        XCTAssertEqual(h.controller.unhandled([press], began: true), [press])
        XCTAssertEqual(h.sound.keySounds, [])
        // 不可编辑时再取得焦点也不启用。
        h.textView.resignFirstResponder()
        h.textView.becomeFirstResponder()
        XCTAssertNotEqual(h.rime.active.last, true)
    }

    /// 打不开纸页(只读)时引擎从不启用。
    func test_openFailureNeverActivates() throws {
        let name = "sumi.rime.test.\(UUID().uuidString)"
        suites.append(name)
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        let rime = FakeRime()
        let c = EditorController(persistence: nil, page: nil, prefs: PrefsModel(store: PrefsStore(defaults: d)),
                                 selection: SelectionStore(defaults: d), sound: SpySound(), rime: rime, rimeDefaults: d)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 900)
        window.rootViewController = c
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        windows.append(window)
        _ = c.textView.becomeFirstResponder()
        drainMain()
        XCTAssertFalse(rime.active.contains(true))
        let press = BarePress()
        rime.swallowed.insert(ObjectIdentifier(press))
        XCTAssertEqual(c.unhandled([press], began: true), [press])
    }

    /// 光标所在行滚出视区:候选行不贴在边上,而是不显示;滚回来再显示(复审 4)。
    func test_barHiddenWhileCaretLineOffscreen() throws {
        let h = try harness()
        let tv = h.textView
        tv.insertText(Array(repeating: "一行", count: 60).joined(separator: "\n"))
        h.controller.view.layoutIfNeeded()
        if let tlm = tv.textLayoutManager, let tcm = tlm.textContentManager { tlm.ensureLayout(for: tcm.documentRange) }
        let bar = try bar(h)
        tv.setContentOffset(.zero, animated: false)
        drainMain()
        XCTAssertEqual(bar.alpha, 0, "caret line is off screen")
        let visible = tv.convert(tv.bounds, to: h.controller.view)
        XCTAssertTrue(bar.alpha == 0 || bar.frame.minY >= visible.minY)
        tv.selectedRange = NSRange(location: 4, length: 0) // 第二行
        drainMain()
        XCTAssertEqual(bar.alpha, 1)
        XCTAssertEqual(bar.frame.minY, try paragraphTop(h, offset: 6), accuracy: 1)
    }

    /// 改字号后候选行跟着重摆:高度随新字号,位置仍在下一行(复审 5)。
    func test_barFollowsFontSize() throws {
        let h = try harness()
        h.textView.insertText("第一行\n第二行")
        h.textView.selectedRange = NSRange(location: 3, length: 0)
        drainMain()
        let bar = try bar(h)
        let before = bar.frame.height
        h.prefs.bumpSize(8)
        drainMain()
        XCTAssertGreaterThan(bar.style.font.pointSize, 0)
        XCTAssertEqual(bar.frame.height, RimeCandidateBar.height(for: bar.style.font), accuracy: 0.5)
        XCTAssertGreaterThan(bar.frame.height, before)
        XCTAssertEqual(bar.frame.minY, try paragraphTop(h, offset: 4), accuracy: 1)
        XCTAssertEqual(h.textView.contentInset.bottom, bar.frame.height, accuracy: 0.5)
    }

    /// 候选行消失、底部留白收回时,滚动位置夹回内容范围内(复审 6)。
    func test_insetChangeClampsOffset() throws {
        let h = try harness()
        let tv = h.textView
        tv.insertText(Array(repeating: "一行", count: 60).joined(separator: "\n"))
        h.controller.view.layoutIfNeeded()
        if let tlm = tv.textLayoutManager, let tcm = tlm.textContentManager { tlm.ensureLayout(for: tcm.documentRange) }
        drainMain()
        XCTAssertGreaterThan(tv.contentInset.bottom, 0)
        let bottom = tv.contentSize.height + tv.contentInset.bottom - tv.bounds.height
        tv.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        h.rime.push(status: RimeStatus(state: .ready, keyboard: false))
        drainMain()
        XCTAssertEqual(tv.contentInset.bottom, 0)
        XCTAssertLessThanOrEqual(tv.contentOffset.y, max(0, tv.contentSize.height - tv.bounds.height) + 0.5)
    }

    /// 不是按键引起、也不是点候选的上屏(如失去活跃时引擎自己上屏):不发声,不算打字(复审 7)。
    func test_engineCommitWithoutKeyIsSilent() throws {
        let h = try harness()
        h.rime.compose("ni")
        let before = h.sound.total
        let typing = typed(h)
        h.rime.push(RimeUpdate(commit: "ni"))
        XCTAssertEqual(h.page.body(), "ni")
        XCTAssertEqual(h.sound.total, before)
        XCTAssertEqual(typing(), 0)
    }

    /// 按住键时引擎自己连发的上屏照常按文字发声。
    func test_heldKeyRepeatSounds() throws {
        let h = try harness()
        let press = BarePress()
        h.rime.swallowed.insert(ObjectIdentifier(press))
        h.textView.pressesBegan([press], with: nil)
        XCTAssertEqual(h.sound.keySounds, [.key])
        h.rime.push(RimeUpdate(commit: "a"))
        XCTAssertEqual(h.sound.textSounds.count, 1)
        h.textView.pressesEnded([press], with: nil)
        h.rime.push(RimeUpdate(commit: "b"))
        XCTAssertEqual(h.sound.textSounds.count, 1, "no key held: silent")
    }

    /// 点候选上屏照常发声。
    func test_candidateTapCommitSounds() throws {
        let h = try harness()
        h.rime.compose("ni", menu: RimeMenu(rows: [RimeCandidate(index: 0, label: "1", text: "你")], cursor: 0))
        h.rime.onSelect = { [weak rime = h.rime] _ in rime?.push(RimeUpdate(commit: "你")) }
        let bar = try bar(h)
        bar.layoutIfNeeded()
        let before = h.sound.total
        try XCTUnwrap(button("你", in: bar)).sendActions(for: .touchUpInside)
        XCTAssertEqual(h.page.body(), "你")
        XCTAssertEqual(h.sound.total, before + 1)
    }

    /// 聚焦打字中取消组字(Esc 清掉、点「内」换成「系」)不算挪光标:仍在聚焦,正文不跳回页首(04「退出聚焦」;
    /// sim-rime.sh 的 repeat r03、toggle t02 看到过跳回)。清掉组字时 UIKit 发的选区通知不经 `shouldChangeTextIn`,
    /// 光标停在组字之前,与按键记下的位置不符,且可能离上次输入已过 0.5 秒。
    func test_cancelledCompositionKeepsFocus() throws {
        let h = try harness()
        var t = Date(timeIntervalSinceReferenceDate: 1000)
        h.controller.now = { t }
        for ch in ["一", "二", "三", "四"] { h.textView.insertText(ch) }
        XCTAssertNotNil(h.textView.pinnedY, "four quick inputs enter focus")
        drainMain()

        /// 按一键(引擎吞下),按下时引擎推 `update`。
        func key(_ update: RimeUpdate) {
            let press = BarePress()
            h.rime.swallowed.insert(ObjectIdentifier(press))
            h.rime.onSwallow = { [weak rime = h.rime] _ in rime?.push(update) }
            h.textView.pressesBegan([press], with: nil)
            h.textView.pressesEnded([press], with: nil)
            h.rime.onSwallow = nil
            drainMain()
        }
        let ni = RimeUpdate(preedit: "ni", caret: 2, input: "ni")

        key(ni)
        t += 1
        key(RimeUpdate()) // Esc
        XCTAssertEqual(h.textView.text, "一二三四")
        XCTAssertNotNil(h.textView.pinnedY, "Esc clearing the composition is not a caret move")

        key(ni)
        t += 1
        let bar = try bar(h)
        bar.layoutIfNeeded()
        choose(.system, in: bar)
        XCTAssertEqual(h.textView.text, "一二三四")
        XCTAssertNotNil(h.textView.pinnedY, "switching to the system input method is not a caret move")
    }

    /// 组字中不接受拖入(复审 8)。
    func test_compositionForbidsDrop() throws {
        let h = try harness()
        let tv = h.textView
        XCTAssertTrue(tv.textDropDelegate === tv)
        let ok = UITextDropProposal(operation: .copy)
        XCTAssertEqual(tv.dropProposal(suggested: ok).operation, .copy)
        h.rime.compose("ni")
        XCTAssertEqual(tv.dropProposal(suggested: ok).operation, .forbidden)
    }

    // MARK: 上屏后候选行不跳(真机反馈 2026-11-20)

    /// 按一键(引擎吞下),按下时引擎推 `update`。
    private func key(_ h: Harness, _ update: RimeUpdate) {
        let press = BarePress()
        h.rime.swallowed.insert(ObjectIdentifier(press))
        h.rime.onSwallow = { [weak rime = h.rime] _ in rime?.push(update) }
        h.textView.pressesBegan([press], with: nil)
        h.textView.pressesEnded([press], with: nil)
        h.rime.onSwallow = nil
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// 排版落定后,候选行的顶边应在的位置(编辑面根视图坐标):光标所在行的下一行的顶边;以及光标框。
    private func expectedBarTop(_ h: Harness) throws -> (bar: CGFloat, caret: CGRect) {
        let tv = h.textView
        tv.layoutIfNeeded()
        let top = try XCTUnwrap(tv.lineTopBelowCaret(pitch: h.controller.view.bounds.height))
        let caret = tv.convert(tv.caretRect(for: try XCTUnwrap(tv.selectedTextRange?.end)), to: h.controller.view)
        return (tv.convert(CGPoint(x: 0, y: top), to: h.controller.view).y, caret)
    }

    /// 自动换行的长页,聚焦打字中在正文中间组字后上屏:候选行仍在光标行的下一行,不上移盖住文字。
    /// 上屏那次编辑被内核接受后整段重设属性(`restyle`),TextKit 2 的排版随之作废;那一刻读到的光标行是估计值,
    /// 比真实位置高出几行。候选行若按那个值摆放,之后没有滚动、也没有更新,就一直停在上面(真机上看到的「上移」)。
    func test_commitInFocusKeepsBarBelowCaretLine() throws {
        let h = try harness()
        let tv = h.textView
        let paragraph = "这是一段比较长的文字，用来让它在窄屏上自动换行，看看候选行会不会跳。"
        tv.insertText(Array(repeating: paragraph, count: 30).joined(separator: "\n"))
        tv.selectedRange = NSRange(location: 300, length: 0)
        spin(0.3)
        for ch in ["一", "二", "三", "四"] { tv.insertText(ch) }
        XCTAssertNotNil(tv.pinnedY, "four quick inputs enter focus")
        spin(0.3)
        let menu = RimeMenu(rows: [RimeCandidate(index: 0, label: "1", text: "你好")], cursor: 0)
        var typed = ""
        for ch in ["n", "i", "h", "a", "o"] {
            typed += ch
            key(h, RimeUpdate(preedit: typed, caret: (typed as NSString).length, input: typed, menu: menu))
        }
        spin(0.3)
        let bar = try bar(h)
        let composing = try expectedBarTop(h)
        XCTAssertEqual(bar.frame.minY, composing.bar, accuracy: 1, "while composing")

        key(h, RimeUpdate(commit: "你好"))
        XCTAssertEqual(bar.frame.minY, try expectedBarTop(h).bar, accuracy: 1, "right after the commit")
        spin(0.5)
        let settled = try expectedBarTop(h)
        XCTAssertEqual(bar.frame.minY, settled.bar, accuracy: 1, "after the layout settled")
        XCTAssertGreaterThanOrEqual(bar.frame.minY, settled.caret.maxY - 0.5, "the bar covers the caret line")
        XCTAssertEqual(bar.alpha, 1)
        if abs(settled.caret.minY - composing.caret.minY) < 1 {
            XCTAssertEqual(bar.frame.minY, composing.bar, accuracy: 1, "same caret line, the bar did not move")
        }
    }
}
