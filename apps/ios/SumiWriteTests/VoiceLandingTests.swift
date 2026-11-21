import UIKit
import VoiceKit
import XCTest
@testable import SumiWrite

/// 语音的落地(ios.md §3.7「松手与落地」):开始前组字先上屏,结果进内核、算一次编辑;实体键盘长按右 ⌥(§3.7「入口」)。
/// 识别、权限、音频只靠真机清单;这里只用编辑面、`RimeIntegrationTests` 里的假输入法与假按键,和下面的假识别。
@MainActor
final class VoiceLandingTests: XCTestCase {
    private var dir: URL?
    private var suite: String?
    private var window: UIWindow?
    private var library: PageLibrary?
    private var prefs: PrefsModel?

    override func tearDown() {
        window?.isHidden = true
        if let dir { try? FileManager.default.removeItem(at: dir) }
        if let suite { UserDefaults().removePersistentDomain(forName: suite) }
        window = nil
        library = nil
        super.tearDown()
    }

    /// 编辑面挂在真窗口上并取得焦点,接着假的内嵌输入法与打字音。
    private func harness() throws -> (EditorController, CorePage, FakeRime, SpySound) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sumi-voice-\(UUID().uuidString)")
        self.dir = dir
        let name = "sumi.voice.test.\(UUID().uuidString)"
        suite = name
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        guard case .ready(let lib, let p, let page) = PageLibrary.open(directory: dir, defaults: d) else {
            XCTFail("open failed"); throw CocoaError(.fileReadUnknown)
        }
        library = lib
        let rime = FakeRime()
        let sound = SpySound()
        let prefs = PrefsModel(store: PrefsStore(defaults: d))
        self.prefs = prefs
        let c = EditorController(persistence: p, page: page, prefs: prefs,
                                 selection: SelectionStore(defaults: d), sound: sound, rime: rime, rimeDefaults: d)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let w = UIWindow(windowScene: scene)
        w.frame = CGRect(x: 0, y: 0, width: 430, height: 900)
        w.rootViewController = c
        w.makeKeyAndVisible()
        w.layoutIfNeeded()
        window = w
        XCTAssertTrue(c.textView.becomeFirstResponder())
        return (c, page, rime, sound)
    }

    func testRimeCompositionCommitsBeforeVoice() throws {
        let (c, page, rime, _) = try harness()
        rime.compose("ni")
        XCTAssertNotNil(c.textView.markedTextRange)
        XCTAssertNil(c.voiceWillStart())
        XCTAssertNil(c.textView.markedTextRange)
        XCTAssertEqual(page.body(), "ni")
    }

    func testVoiceLandsInPage() throws {
        let (c, page, _, sound) = try harness()
        c.textView.insertText("前文")
        let sounds = sound.total
        c.insertVoice("你好")
        XCTAssertEqual(page.body(), "前文你好")
        XCTAssertEqual(c.textView.text, page.rendered().text)
        XCTAssertEqual(c.textView.selectedRange, NSRange(location: 4, length: 0))
        XCTAssertEqual(sound.total, sounds, "语音落地不播打字音")
        c.textView.coreUndoManager?.undo()
        XCTAssertFalse(page.body().contains("你好"))
        XCTAssertEqual(page.body(), "前文")
    }

    func testSystemCompositionRefuses() throws {
        let (c, page, rime, _) = try harness()
        c.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertEqual(c.voiceWillStart(), "请先完成输入")
        XCTAssertEqual(rime.flushCount, 0)
        XCTAssertNotNil(c.textView.markedTextRange)
        XCTAssertEqual(page.body(), "")
    }

    /// 右 ⌥ 按住 0.3 s 开始说话(键盘路径,只有气泡);说话中按 Tab 插入原话,Tab 本身不进正文。
    func testRightOptionHoldStartsAndTabInsertsRaw() throws {
        let (c, page, _, _) = try harness()
        let host = try voiceHost(c, final: "你好")
        // 从 0 起算:大的时间戳加 0.3 再减回去,浮点上可能差一点不到 0.3。
        var t = Date(timeIntervalSinceReferenceDate: 0)
        c.now = { t }
        let option = KeyPress(.keyboardRightAlt, .alternate)
        XCTAssertEqual(c.unhandled([option], began: true), [], "按住的右 ⌥ 先被吞下")
        t += VoiceKeyGate.holdDelay
        c.voiceKeyElapsed()
        wait { host.hold.holding }
        XCTAssertTrue(host.hold.active)
        let tab = KeyPress(.keyboardTab, [])
        XCTAssertEqual(c.unhandled([tab], began: true), [], "Tab 选「原话」,不往下传")
        wait { page.body() == "你好" }
        XCTAssertEqual(page.body(), "你好")
        XCTAssertFalse(c.textView.text.contains("\t"))
        XCTAssertEqual(c.unhandled([tab], began: false), [])
        XCTAssertEqual(c.unhandled([option], began: false), [])
    }

    /// 设置里关掉「按住右 ⌥ 说话」:右 ⌥ 照常往下传,不开始说话。
    func testRightOptionOffDoesNotStart() throws {
        let (c, _, _, _) = try harness()
        let host = try voiceHost(c, final: "你好")
        prefs?.prefs.voiceKey = false
        var t = Date(timeIntervalSinceReferenceDate: 0)
        c.now = { t }
        let option = KeyPress(.keyboardRightAlt, .alternate)
        XCTAssertEqual(c.unhandled([option], began: true), [option])
        t += VoiceKeyGate.holdDelay
        c.voiceKeyElapsed()
        drain()
        XCTAssertFalse(host.hold.active)
        XCTAssertEqual(c.unhandled([option], began: false), [option])
    }

    private func voiceHost(_ c: EditorController, final text: String) throws -> VoiceHost {
        let prefs = try XCTUnwrap(prefs)
        let d = try XCTUnwrap(suite.flatMap(UserDefaults.init(suiteName:)))
        return VoiceHost(controller: c, prefs: prefs, defaults: d, engine: FinalEngine(text), permissions: Granted())
    }

    /// 转主线程直到 `done` 成立(VoiceKit 的开始与松手都在主线程的 Task 里),最多 2 s。
    private func wait(_ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    private func drain() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
}

/// 假识别:`stop` 时给出 `text` 作最终结果。VoiceKit 自己的假引擎在它的测试目标里,这里引不到。
private final class FinalEngine: SpeechEngine {
    let text: String
    private var events: AsyncStream<VoiceEvent>.Continuation?
    init(_ text: String) { self.text = text }
    func start(locale: Locale) async throws -> AsyncStream<VoiceEvent> {
        let (stream, events) = AsyncStream.makeStream(of: VoiceEvent.self)
        self.events = events
        return stream
    }
    func stop() {
        events?.yield(.final(text))
        events?.finish()
    }
    func cancel() { events?.finish() }
}

private final class Granted: SpeechPermissions {
    func access() -> Access { .granted }
    func askAccess() async -> Access { .granted }
}
