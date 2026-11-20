import XCTest
import UIKit
@testable import SumiWrite

/// 长页上的排版(ios.md §3.3「TextKit 2 的估算高度」):光标之前的段落为什么停在估算值上,以及每打一键
/// 「从文首排到光标」的代价。数字打印成 `LAYOUT …` 行,记在任务报告里;模拟器上的毫秒数只作相对比较。
@MainActor
final class LongPageLayoutTests: XCTestCase {
    private var dirs: [URL] = []
    private var suites: [String] = []
    private var windows: [UIWindow] = []

    override func tearDown() {
        for w in windows { w.isHidden = true }
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        for s in suites { UserDefaults().removePersistentDomain(forName: s) }
        windows = []; dirs = []; suites = []
        super.tearDown()
    }

    /// 放进窗口、有焦点的编辑器,正文约 `characters` 字:会自动换行的长段落(中英混排),光标在文末。
    private func editor(characters: Int) throws -> EditorController {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sumi-long-\(UUID().uuidString)")
        dirs.append(dir)
        let name = "sumi.long.test.\(UUID().uuidString)"
        suites.append(name)
        let d = try XCTUnwrap(UserDefaults(suiteName: name))
        guard case .ready(_, let p, let page) = PageLibrary.open(directory: dir, defaults: d) else {
            XCTFail("open failed"); throw CocoaError(.fileReadUnknown)
        }
        let c = EditorController(persistence: p, page: page, prefs: PrefsModel(store: PrefsStore(defaults: d)),
                                 selection: SelectionStore(defaults: d), sound: nil)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 900)
        window.rootViewController = c
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        windows.append(window)
        XCTAssertTrue(c.textView.becomeFirstResponder())
        let paragraph = String(repeating: "这是一段比较长的文字,用来让它在屏幕上自动换行。Some English words that wrap as well. ",
                               count: 4) + "\n"
        let text = String(repeating: paragraph, count: max(1, characters / paragraph.count))
        c.textView.insertText(text)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        c.view.layoutIfNeeded()
        return c
    }

    /// 一键:经 `UITextView` 插入(代理 → 内核 → restyle → 排版),再走一次布局(运行循环里的那次)。返回毫秒。
    private func keystroke(_ c: EditorController, _ s: String = "a") -> Double {
        let t0 = CACurrentMediaTime()
        c.textView.insertText(s)
        c.view.layoutIfNeeded()
        return (CACurrentMediaTime() - t0) * 1000
    }

    private func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        return s.isEmpty ? 0 : s[s.count / 2]
    }

    /// 从文首到光标的段落里,还没排版(只有估算高度)的有几段。
    private func paragraphsBeforeCaret(_ tv: SumiTextView) throws -> (total: Int, estimated: Int) {
        let tlm = try XCTUnwrap(tv.textLayoutManager)
        let tcm = try XCTUnwrap(tlm.textContentManager)
        let caret = tv.offset(from: tv.beginningOfDocument, to: try XCTUnwrap(tv.selectedTextRange?.end))
        let end = try XCTUnwrap(tcm.location(tcm.documentRange.location, offsetBy: caret))
        var total = 0, estimated = 0
        tlm.enumerateTextLayoutFragments(from: tcm.documentRange.location, options: []) { f in
            guard f.rangeInElement.location.compare(end) == .orderedAscending else { return false }
            total += 1
            if f.state != .layoutAvailable { estimated += 1 }
            return true
        }
        return (total, estimated)
    }

    /// 探针:打一键之后(restyle 对全文重设属性),光标之前的段落有多少停在估算值上。
    /// 不排到光标时,只有可见区附近的几段排过;排到光标时一段不剩。
    func test_paragraphsBeforeTheCaretStayEstimatedAfterAnEdit() throws {
        let c = try editor(characters: 50_000)
        let tv = c.textView
        for on in [false, true] {
            tv.layoutsThroughCaret = on
            _ = keystroke(c)
            let after = try paragraphsBeforeCaret(tv)
            let estimatedHeight = tv.contentSize.height
            print("LAYOUT probe layoutThroughCaret=\(on): \(after.estimated) of \(after.total) paragraphs before the caret estimated, contentSize \(Int(estimatedHeight))")
            if on {
                XCTAssertEqual(after.estimated, 0)
            } else {
                XCTAssertGreaterThan(after.estimated, after.total / 2, "most paragraphs before the caret are estimated")
            }
        }
        // 再作废一次全文属性(restyle 做的事),不排版:排过的段落又全部回到估算值。
        tv.layoutsThroughCaret = true
        _ = keystroke(c)
        let storage = tv.textStorage
        storage.beginEditing()
        storage.addAttribute(.kern, value: 0, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        let invalidated = try paragraphsBeforeCaret(tv)
        print("LAYOUT probe after a full-text attribute change: \(invalidated.estimated) of \(invalidated.total) estimated")
        XCTAssertGreaterThan(invalidated.estimated, invalidated.total / 2)
    }

    /// 每打一键的耗时,约 5 万字的长页:不排 / 排到光标(光标在文末、在中间),以及旧做法每次布局的全文
    /// `ensureLayout`(作废后、没作废时)。断言只防数量级的退化,数字看 `LAYOUT` 行。
    func test_keystrokeCostOnALongPage() throws {
        let c = try editor(characters: 50_000)
        let tv = c.textView
        let length = tv.textStorage.length
        var rows: [String] = []
        var results: [String: Double] = [:]
        for (place, location) in [("end", length), ("middle", length / 2)] {
            for on in [false, true] {
                tv.layoutsThroughCaret = on
                tv.selectedRange = NSRange(location: location, length: 0)
                c.view.layoutIfNeeded()
                _ = keystroke(c) // 热身
                let times = (0..<15).map { _ in keystroke(c) }
                let key = "\(place) layoutThroughCaret=\(on)"
                results[key] = median(times)
                rows.append(String(format: "LAYOUT keystroke caret at %@, layoutThroughCaret=%@: median %.1f ms, max %.1f ms",
                                   place, on ? "on" : "off", median(times), times.max() ?? 0))
            }
        }
        // 旧做法(修正第 1 轮):每次布局对全文 `ensureLayout`。作废之后(每一键)、没作废时(滚动时的每一帧)。
        let tlm = try XCTUnwrap(tv.textLayoutManager)
        let doc = try XCTUnwrap(tlm.textContentManager?.documentRange)
        tv.layoutsThroughCaret = false
        var full: [Double] = [], walk: [Double] = []
        for _ in 0..<10 {
            tv.insertText("a")
            var t0 = CACurrentMediaTime()
            tlm.ensureLayout(for: doc)
            full.append((CACurrentMediaTime() - t0) * 1000)
            t0 = CACurrentMediaTime()
            tlm.ensureLayout(for: doc)
            walk.append((CACurrentMediaTime() - t0) * 1000)
        }
        rows.append(String(format: "LAYOUT whole-document ensureLayout after an edit: median %.1f ms; when nothing changed: median %.2f ms",
                           median(full), median(walk)))
        // restyle 的作废本身:全文重设一次属性,不排版。
        var invalidate: [Double] = []
        for _ in 0..<10 {
            let t0 = CACurrentMediaTime()
            let storage = tv.textStorage
            storage.beginEditing()
            storage.addAttribute(.kern, value: 0, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
            invalidate.append((CACurrentMediaTime() - t0) * 1000)
        }
        rows.append(String(format: "LAYOUT full-text attribute change alone: median %.1f ms", median(invalidate)))
        rows.append("LAYOUT page: \(length) UTF-16 units, contentSize \(Int(tv.contentSize.height)) pt")
        rows.forEach { print($0) }
        XCTAssertLessThan(results["end layoutThroughCaret=true"] ?? .infinity, 1000, "one keystroke under a second")
    }

    /// XCTest 的测量:光标在文末,排到光标,每次 5 键。
    func test_measureKeystrokesAtTheEndOfALongPage() throws {
        let c = try editor(characters: 50_000)
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<5 { _ = keystroke(c) }
        }
    }
}
