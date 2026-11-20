import RimeKit
import RimeKitUI
import UIKit
import XCTest
@testable import SumiWrite

/// 假的内嵌输入法:记下编辑面要它做的事,测试经它推更新与状态。与 `RimeInput` 一样,`flush()` 与 `clear()`
/// 都同步回一次更新(`flush`:按原文上屏当前的输入;`clear`:空更新)。
private final class FakeRime: RimeInputDriving {
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
    func select(_ index: Int) { selected.append(index) }
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

private final class SpySound: TypingSoundPlaying {
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
        let c = EditorController(persistence: p, page: page, prefs: PrefsModel(store: PrefsStore(defaults: d)),
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
        return Harness(controller: c, persistence: p, page: page, library: lib, defaults: d, rime: rime,
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
    func test_candidateTapReachesSelect() throws {
        let h = try harness()
        h.rime.compose("nihao", menu: RimeMenu(rows: [RimeCandidate(index: 0, label: "1", text: "你好"),
                                                      RimeCandidate(index: 1, label: "2", text: "拟好")], cursor: 0))
        let bar = try bar(h)
        bar.layoutIfNeeded()
        let b = try XCTUnwrap(button("拟好", in: bar))
        let point = b.convert(CGPoint(x: b.bounds.midX, y: b.bounds.midY), to: h.window)
        let hit = try XCTUnwrap(h.window.hitTest(point, with: nil))
        XCTAssertTrue(hit === b || hit.isDescendant(of: b), "tap lands on \(hit)")
        b.sendActions(for: .touchUpInside)
        XCTAssertEqual(h.rime.selected, [1])
    }

    /// 点「系」:组字清掉,停用;再点「内」切回。选择记在 `rime.builtin`。
    func test_toggleTapSwitchesAndPersists() throws {
        let h = try harness()
        h.rime.compose("ni")
        let bar = try bar(h)
        bar.layoutIfNeeded()
        let toggle = try XCTUnwrap(button("切换内置输入法", in: bar))
        let point = toggle.convert(CGPoint(x: toggle.bounds.midX, y: toggle.bounds.midY), to: h.window)
        let hit = try XCTUnwrap(h.window.hitTest(point, with: nil))
        XCTAssertTrue(hit === toggle || hit.isDescendant(of: toggle), "tap lands on \(hit)")
        toggle.sendActions(for: .touchUpInside)
        XCTAssertEqual(h.rime.clearCount, 1)
        XCTAssertNil(h.textView.markedTextRange)
        XCTAssertEqual(h.page.body(), "")
        XCTAssertEqual(h.rime.active.last, false)
        XCTAssertEqual(h.defaults.object(forKey: RimeTextViewAdapter.builtinKey) as? Bool, false)
        XCTAssertFalse(bar.isHidden, "the bar stays so 内 can be tapped back")
        toggle.sendActions(for: .touchUpInside)
        XCTAssertEqual(h.rime.active.last, true)
        XCTAssertEqual(h.defaults.object(forKey: RimeTextViewAdapter.builtinKey) as? Bool, true)
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
}
