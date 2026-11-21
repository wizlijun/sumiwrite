import UIKit
import VoiceKit
import XCTest
@testable import SumiWrite

/// 语音的落地(ios.md §3.8「松手与落地」):开始前组字先上屏,结果进内核、算一次编辑;实体键盘长按右 ⌥(§3.8「入口」)。
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
        hold(c)
        wait { host.hold.holding }
        XCTAssertTrue(host.hold.active)
        let tab = KeyPress(.keyboardTab, [])
        XCTAssertEqual(c.unhandled([tab], began: true), [], "Tab 选「原话」,不往下传")
        wait { page.body() == "你好" }
        XCTAssertEqual(page.body(), "你好")
        XCTAssertFalse(c.textView.text.contains("\t"))
        XCTAssertEqual(c.unhandled([tab], began: false), [])
        XCTAssertEqual(c.unhandled([KeyPress(.keyboardRightAlt, .alternate)], began: false), [])
    }

    /// 设置里关掉「按住右 ⌥ 说话」:右 ⌥ 照常往下传,不开始说话。
    func testRightOptionOffDoesNotStart() throws {
        let (c, _, _, _) = try harness()
        let host = try voiceHost(c, final: "你好")
        prefs?.prefs.voiceKey = false
        var t: TimeInterval = 0
        c.uptime = { t }
        let option = KeyPress(.keyboardRightAlt, .alternate)
        XCTAssertEqual(c.unhandled([option], began: true), [option])
        t += VoiceKeyGate.holdDelay
        c.voiceKeyElapsed()
        drain()
        XCTAssertFalse(host.hold.active)
        XCTAssertEqual(c.unhandled([option], began: false), [option])
    }

    /// 接入点没填(空的 `LlmEndpoint`)时不碰 key 的钥匙串;整理请求走 `TidyStub`。
    private func voiceHost(_ c: EditorController, final text: String,
                           endpoint: LlmEndpoint = LlmEndpoint()) throws -> VoiceHost {
        let prefs = try XCTUnwrap(prefs)
        let d = try XCTUnwrap(suite.flatMap(UserDefaults.init(suiteName:)))
        let held = try XCTUnwrap(dir).appendingPathComponent("voice-held")
        return VoiceHost(controller: c, prefs: prefs, defaults: d, engine: FinalEngine(text), permissions: Granted(),
                         api: LlmApi(session: TidyStub.session), endpoint: { endpoint }, heldDir: held)
    }

    /// 长按右 ⌥ 过 0.3 s,开始一次键盘说话。门限的时钟从 0 起算:大的时间戳加 0.3 再减回去,浮点上可能差一点不到 0.3。
    private func hold(_ c: EditorController) {
        var t: TimeInterval = 0
        c.uptime = { t }
        XCTAssertEqual(c.unhandled([KeyPress(.keyboardRightAlt, .alternate)], began: true), [], "按住的右 ⌥ 先被吞下")
        t += VoiceKeyGate.holdDelay
        c.voiceKeyElapsed()
    }

    /// 接入点没填:长语音照样立刻插入原话,不出整理卡。
    func testEmptyEndpointInsertsRawImmediately() throws {
        let (c, page, _, _) = try harness()
        let said = "下午三点在图书馆二楼见然后记得带上周的打印稿"
        XCTAssertTrue(said.count >= 20)
        let host = try voiceHost(c, final: said)
        hold(c)
        wait { host.hold.holding }
        XCTAssertEqual(c.unhandled([KeyPress(.keyboardRightAlt, [])], began: false), [], "松开右 ⌥ 插入")
        wait { page.body() == said }
        XCTAssertEqual(page.body(), said)
        XCTAssertEqual(host.tidy.phase, .idle)
    }

    /// 整理后的文字分两步落地:撤销一次回到原话,再撤销一次两者都没有。
    func testTidyTwoStepUndo() throws {
        let (c, page, _, _) = try harness()
        let said = "嗯那个下午三点在图书馆二楼见然后记得带上周的打印稿"
        let tidied = "下午三点在图书馆二楼见,记得带上周的打印稿。"
        TidyStub.answer = tidied
        let host = try voiceHost(c, final: said, endpoint: LlmEndpoint(url: "http://llm.test", key: "test-key"))
        hold(c)
        wait { host.hold.holding }
        XCTAssertEqual(c.unhandled([KeyPress(.keyboardRightAlt, [])], began: false), [])
        wait { host.tidy.phase != .idle }
        XCTAssertEqual(page.body(), "", "整理中不落地")
        wait(5) { page.body() == tidied }
        XCTAssertEqual(page.body(), tidied)
        c.textView.coreUndoManager?.undo()
        XCTAssertEqual(page.body(), said)
        c.textView.coreUndoManager?.undo()
        XCTAssertEqual(page.body(), "")
    }

    /// 转主线程直到 `done` 成立(VoiceKit 的开始与松手都在主线程的 Task 里),最多 `seconds` 秒。
    private func wait(_ seconds: TimeInterval = 2, _ done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
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

/// 假的 LLM 网关:每个请求都回 200 和 `answer`,一次给完。
private final class TidyStub: URLProtocol {
    static var answer = ""

    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [TidyStub.self]
        return URLSession(configuration: c)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // nosniff:没有它 URLSession 会扣住 text/plain 的开头(最多 512 字节)去猜类型。
        let res = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                  headerFields: ["Content-Type": "text/plain; charset=utf-8",
                                                 "X-Content-Type-Options": "nosniff"])!
        client?.urlProtocol(self, didReceive: res, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.answer.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class Granted: SpeechPermissions {
    func access() -> Access { .granted }
    func askAccess() async -> Access { .granted }
}
