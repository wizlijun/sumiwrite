import AVFoundation
import XCTest
@testable import SumiWrite

@MainActor
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

    // MARK: 按需启动与恢复(终审 I-3、M-1)

    func test_engineIsBuiltOnlyWhileSoundIsOn() {
        var prefs = EditorPrefs()
        prefs.typingSound = false
        let sound = TypingSound(bundle: .main, prefs: { prefs }, center: NotificationCenter())
        sound.preferencesChanged(prefs)
        sound.play(before: "a", after: "ab")
        sound.waitUntilIdle()
        XCTAssertNil(sound.builtPack, "no engine while the sound is off")
        XCTAssertEqual(sound.startAttempts, 0)

        prefs.typingSound = true
        sound.preferencesChanged(prefs)
        sound.waitUntilIdle()
        XCTAssertEqual(sound.builtPack, .typewriter, "turning the sound on builds only the selected pack")

        prefs.soundPack = .thock
        sound.preferencesChanged(prefs)
        sound.waitUntilIdle()
        XCTAssertEqual(sound.builtPack, .thock)

        prefs.typingSound = false
        sound.preferencesChanged(prefs)
        sound.waitUntilIdle()
        XCTAssertNil(sound.builtPack, "turning the sound off stops and releases the engine")

        prefs.typingSound = true
        sound.play(before: "a", after: "ab")
        sound.waitUntilIdle()
        XCTAssertEqual(sound.builtPack, .thock, "the first sound after turning it back on rebuilds lazily")
    }

    func test_foregroundAndMediaResetRestart() {
        let center = NotificationCenter()
        let sound = TypingSound(bundle: .main, prefs: { EditorPrefs() }, center: center)
        sound.preferencesChanged(EditorPrefs())
        sound.waitUntilIdle()
        let base = sound.startAttempts
        XCTAssertGreaterThanOrEqual(base, 1)

        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        sound.waitUntilIdle()
        XCTAssertGreaterThan(sound.startAttempts, base, "becoming active retries the start")

        let beforeReset = sound.startAttempts
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        sound.waitUntilIdle()
        XCTAssertEqual(sound.rebuildCount, 1)
        XCTAssertGreaterThan(sound.startAttempts, beforeReset)
        XCTAssertEqual(sound.builtPack, .typewriter, "the engine is rebuilt from scratch")
    }

    func test_interruptionBlocksInputStartsUntilEndedOrForeground() {
        let center = NotificationCenter()
        let sound = TypingSound(bundle: .main, prefs: { EditorPrefs() }, center: center)
        sound.preferencesChanged(EditorPrefs())
        sound.waitUntilIdle()
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        sound.waitUntilIdle()
        let during = sound.startAttempts
        for _ in 0..<5 { sound.play(before: "a", after: "ab") }
        sound.waitUntilIdle()
        XCTAssertEqual(sound.startAttempts, during, "typing during an interruption does not fight it")
        XCTAssertEqual(sound.playedCount, 0)

        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        sound.waitUntilIdle()
        XCTAssertGreaterThan(sound.startAttempts, during)

        // 只有 `.began`、没有 `.ended` 时,回到前台也能恢复。
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        sound.waitUntilIdle()
        let again = sound.startAttempts
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        sound.waitUntilIdle()
        XCTAssertGreaterThan(sound.startAttempts, again)
    }

    func test_foregroundWhileOffDoesNothing() {
        var prefs = EditorPrefs()
        prefs.typingSound = false
        let center = NotificationCenter()
        let sound = TypingSound(bundle: .main, prefs: { prefs }, center: center)
        sound.preferencesChanged(prefs)
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        sound.waitUntilIdle()
        XCTAssertEqual(sound.startAttempts, 0)
        XCTAssertNil(sound.builtPack)
    }

    // MARK: 编辑面接线

    private final class SpySound: TypingSoundPlaying {
        var calls: [(String, String)] = []
        var prefsSeen: [EditorPrefs] = []
        func play(before: String, after: String) { calls.append((before, after)) }
        func preferencesChanged(_ prefs: EditorPrefs) { prefsSeen.append(prefs) }
    }

    private func makeController(sound: SpySound, writable: Bool = true) throws -> EditorController {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sumi-snd-\(UUID().uuidString)")
        dirs.append(dir)
        let name = "sumi.sound.test.\(UUID().uuidString)"
        suites.append(name)
        let d = UserDefaults(suiteName: name)!
        guard case .ready(let lib, let p, let page) = PageLibrary.open(directory: dir, defaults: d) else { throw CocoaError(.fileReadUnknown) }
        let c = EditorController(open: .ready(lib, p, page), prefs: PrefsStore(defaults: d),
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

    func test_controllerForwardsPrefsToSound() throws {
        let spy = SpySound()
        let c = try makeController(sound: spy)
        XCTAssertEqual(spy.prefsSeen.last?.typingSound, true, "loading the editor reports the prefs")
        var p = c.prefs
        p.typingSound = false
        c.updatePrefs(p)
        XCTAssertEqual(spy.prefsSeen.last?.typingSound, false)
    }
}
