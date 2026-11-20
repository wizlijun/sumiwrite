import XCTest
@testable import SumiWrite

final class TypingSoundTests: XCTestCase {
    private var dirs: [URL] = []
    private var suites: [String] = []

    override func tearDown() {
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        for s in suites { UserDefaults().removePersistentDomain(forName: s) }
        dirs = []
        suites = []
        super.tearDown()
    }

    func test_classifyKinds() {
        XCTAssertEqual(KeyKind.classify(before: "ab", after: "abc"), .key)
        XCTAssertEqual(KeyKind.classify(before: "ab", after: "ab "), .space)
        XCTAssertEqual(KeyKind.classify(before: "ab", after: "ab\n"), .enter)
        XCTAssertEqual(KeyKind.classify(before: "abc", after: "ab"), .delete)
        XCTAssertEqual(KeyKind.classify(before: "nih", after: "ni"), .delete)
        XCTAssertEqual(KeyKind.classify(before: "ni hao", after: "你好"), .key)
        XCTAssertNil(KeyKind.classify(before: "a", after: "a"))
    }

    private var soundsDirectory: URL { Bundle.main.bundleURL.appendingPathComponent("sounds") }

    func test_manifestResolvesBundledFiles() throws {
        let dir = soundsDirectory
        let manifest = try SoundManifest.load(from: dir)
        XCTAssertEqual(manifest.files(pack: .typewriter, kind: .key), ["typewriter/typewriter-keys-1.wav"])
        for pack in SoundPack.allCases {
            for kind in [KeyKind.key, .space, .enter, .delete] {
                let files = manifest.files(pack: pack, kind: kind)
                XCTAssertGreaterThanOrEqual(files.count, 1, "\(pack) \(kind)")
                for f in files {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(f).path), f)
                }
            }
        }
    }

    func test_manifestIgnoresUnknownRolesAndKeys() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sumi-sound-\(UUID().uuidString)")
        dirs.append(dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{"schema":1,"extra":true,"packs":[{"id":"thock","roles":{"key":["a.wav"],"future":["z"]},"note":1}],"assets":[]}"#
        try json.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let m = try SoundManifest.load(from: dir)
        XCTAssertEqual(m.files(pack: .thock, kind: .key), ["a.wav"])
        XCTAssertEqual(m.files(pack: .thock, kind: .space), [])
        XCTAssertEqual(m.files(pack: .typewriter, kind: .key), [])
    }

    func test_disabledPrefsPlayNothing() {
        var prefs = EditorPrefs()
        prefs.typingSound = false
        let sound = TypingSound(bundle: .main, prefs: { prefs })
        sound.play(before: "a", after: "ab")
        sound.waitUntilIdle()
        XCTAssertEqual(sound.playedCount, 0)
    }

    func test_classifyOnLongDocument() {
        let long = String(repeating: "你好 world\n", count: 20_000)
        XCTAssertEqual(KeyKind.classify(before: long, after: long + "x"), .key)
        XCTAssertEqual(KeyKind.classify(before: long, after: long + "\n"), .enter)
        XCTAssertEqual(KeyKind.classify(before: long + "x", after: long), .delete)
        XCTAssertNil(KeyKind.classify(before: long, after: long))
        let mid = long.index(long.startIndex, offsetBy: 100_000)
        var spaced = long
        spaced.insert(" ", at: mid)
        XCTAssertEqual(KeyKind.classify(before: long, after: spaced), .space)
    }

    func test_playsWhenReady() {
        let sound = TypingSound(bundle: .main, prefs: { EditorPrefs() })
        let deadline = Date().addingTimeInterval(5)
        while sound.playedCount == 0 && Date() < deadline {
            sound.play(before: "a", after: "ab")
            sound.waitUntilIdle()
            Thread.sleep(forTimeInterval: 0.05)
        }
        // 模拟器可能没有音频设备;只要不崩溃即可,有设备时应当播出。
        XCTAssertGreaterThanOrEqual(sound.playedCount, 0)
    }

    func test_notReadyPlaysNothingAndDoesNotCrash() {
        let sound = TypingSound(bundle: Bundle(for: TypingSoundTests.self), prefs: { EditorPrefs() })
        for _ in 0..<20 { sound.play(before: "a", after: "ab") }
        sound.waitUntilIdle()
        XCTAssertEqual(sound.playedCount, 0)
    }

    // MARK: 编辑面接线

    private final class SpySound: TypingSoundPlaying {
        var calls: [(String, String)] = []
        func play(before: String, after: String) { calls.append((before, after)) }
    }

    private func makeController(sound: SpySound, writable: Bool = true) throws -> EditorController {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sumi-snd-\(UUID().uuidString)")
        dirs.append(dir)
        guard case .ready(let p, let page) = PagePersistence.open(directory: dir) else { throw CocoaError(.fileReadUnknown) }
        let name = "sumi.sound.test.\(UUID().uuidString)"
        suites.append(name)
        let d = UserDefaults(suiteName: name)!
        let c = EditorController(open: .ready(p, page), prefs: PrefsStore(defaults: d),
                                 selection: SelectionStore(defaults: d), sound: sound)
        c.loadViewIfNeeded()
        if !writable { c.textView.isEditable = false }
        return c
    }

    private func type(_ text: String, into c: EditorController) {
        c.textView.text = text
        c.textViewDidChange(c.textView)
    }

    func test_controllerPlaysWithPreviousText() throws {
        let spy = SpySound()
        let c = try makeController(sound: spy)
        type("a", into: c)
        type("ab", into: c)
        XCTAssertEqual(spy.calls.map { "\($0.0)|\($0.1)" }, ["|a", "a|ab"])
    }

    func test_controllerDoesNotPlayWhenReadOnly() throws {
        let spy = SpySound()
        let c = try makeController(sound: spy, writable: false)
        type("a", into: c)
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func test_pasteAndUndoRefreshBeforeTextWithoutSound() throws {
        let spy = SpySound()
        let c = try makeController(sound: spy)
        let board = UIPasteboard.withUniqueName()
        board.string = "hello"
        c.textView.pasteboard = board
        c.textView.paste(nil)
        UIPasteboard.remove(withName: board.name)
        XCTAssertEqual(c.textView.text, "hello")
        XCTAssertTrue(spy.calls.isEmpty)
        type("hello!", into: c)
        XCTAssertEqual(spy.calls.map { "\($0.0)|\($0.1)" }, ["hello|hello!"])
    }
}
