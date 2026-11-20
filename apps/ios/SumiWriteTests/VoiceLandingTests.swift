import UIKit
import XCTest
@testable import SumiWrite

/// 语音的落地(ios.md §3.7「松手与落地」):开始前组字先上屏,结果进内核、算一次编辑。
/// 识别、权限、音频只靠真机清单;这里只用编辑面和 `RimeIntegrationTests` 里的假输入法。
@MainActor
final class VoiceLandingTests: XCTestCase {
    private var dir: URL?
    private var suite: String?
    private var window: UIWindow?
    private var library: PageLibrary?

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
        let c = EditorController(persistence: p, page: page, prefs: PrefsModel(store: PrefsStore(defaults: d)),
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
}
