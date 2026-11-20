import XCTest
import UIKit
@testable import SumiWrite

final class AppearanceTests: XCTestCase {
    func test_themeHexMatchesSpec() {
        let want: [(ThemeID, String, String)] = [
            (.ink, "#ffffff", "#000000"), (.dim, "#b8b8b8", "#111111"),
            (.paper, "#111111", "#ffffff"), (.sepia, "#44413c", "#f3ead7"),
            (.crt, "#0ccc68", "#000000"), (.crtBlue, "#7fb4ff", "#000000"),
        ]
        XCTAssertEqual(ThemeID.allCases.count, 6)
        for (t, f, b) in want {
            XCTAssertEqual(t.foregroundHex, f, "\(t)")
            XCTAssertEqual(t.backgroundHex, b, "\(t)")
        }
        XCTAssertEqual(ThemeID.crtBlue.rawValue, "crt-blue")
    }

    func test_defaults() {
        let p = EditorPrefs()
        XCTAssertEqual(p.theme, .dim)
        XCTAssertEqual(p.fontSize, 22)
        XCTAssertEqual(p.lineSpacing, 1.6)
        XCTAssertEqual(p.caretMotion, .breathing)
        XCTAssertTrue(p.focusTyping)
        XCTAssertTrue(p.typingSound)
        XCTAssertEqual(p.soundPack, .typewriter)
    }

    func test_missingFieldsDecodeToDefaults() throws {
        let p = try JSONDecoder().decode(EditorPrefs.self, from: Data(#"{"fontSize":30}"#.utf8))
        var want = EditorPrefs()
        want.fontSize = 30
        XCTAssertEqual(p, want)
    }

    func test_outOfRangeRejected() {
        for size in [7.0, 97.0] {
            var p = EditorPrefs(); p.fontSize = size
            XCTAssertNil(p.validated())
        }
        for ls in [0.9, 3.1] {
            var p = EditorPrefs(); p.lineSpacing = ls
            XCTAssertNil(p.validated())
        }
        XCTAssertNotNil(EditorPrefs().validated())

        let d = UserDefaults(suiteName: "prefs-test-\(UUID().uuidString)")!
        let store = PrefsStore(defaults: d)
        var good = EditorPrefs(); good.fontSize = 30
        XCTAssertTrue(store.save(good))
        var bad = EditorPrefs(); bad.fontSize = 7
        XCTAssertFalse(store.save(bad))
        XCTAssertEqual(store.load(), good)
    }

    func test_caretWidthClamp() {
        XCTAssertEqual(CaretMetrics.width(fontSize: 11), 2)
        XCTAssertEqual(CaretMetrics.width(fontSize: 22), 2)
        XCTAssertEqual(CaretMetrics.width(fontSize: 27.5), 2.5)
        XCTAssertEqual(CaretMetrics.width(fontSize: 33), 3)
        XCTAssertEqual(CaretMetrics.width(fontSize: 96), 3)
    }

    func test_breathingCurve() {
        let acc = 1e-9
        XCTAssertEqual(Double(CaretMetrics.opacity(at: 0)), 1, accuracy: acc)
        XCTAssertEqual(Double(CaretMetrics.opacity(at: 2)), 0.25, accuracy: acc)
        XCTAssertEqual(Double(CaretMetrics.opacity(at: 4)), 1, accuracy: acc)
        let o1 = CaretMetrics.opacity(at: 1)
        XCTAssertTrue(o1 > 0.25 && o1 < 1)
        XCTAssertEqual(Double(CaretMetrics.opacity(at: 5)), Double(o1), accuracy: acc)
    }

    func test_stylerHeadingAndBold() throws {
        let page = try CorePage.create(pageId: newPageId())
        let c = try page.pasteMarkdown(revision: page.rendered().revision, start: 0, length: 0,
                                       markdown: "# 标题\n\n**粗**", atMs: 1)
        let rendered = c.rendered
        let text = rendered.text as NSString
        let prefs = EditorPrefs()
        let base = UIFont.systemFont(ofSize: 22)
        let attrs = Styler.attributes(for: rendered, prefs: prefs, baseFont: base)

        func font(at r: NSRange) -> UIFont? {
            for (range, a) in attrs where NSIntersectionRange(range, r).length == r.length {
                if let f = a[.font] as? UIFont { return f }
            }
            return nil
        }
        let h = text.range(of: "标题"), b = text.range(of: "粗")
        XCTAssertNotEqual(h.location, NSNotFound)
        XCTAssertNotEqual(b.location, NSNotFound)
        let hf = try XCTUnwrap(font(at: h)), bf = try XCTUnwrap(font(at: b))
        XCTAssertEqual(hf.pointSize, 22 * 1.5, accuracy: 0.001)
        XCTAssertTrue(hf.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertEqual(bf.pointSize, 22, accuracy: 0.001)
        XCTAssertTrue(bf.fontDescriptor.symbolicTraits.contains(.traitBold))

        let baseAttrs = Styler.base(prefs: prefs, baseFont: base)
        let ps = baseAttrs[.paragraphStyle] as? NSParagraphStyle
        XCTAssertEqual(ps?.lineHeightMultiple, 1.6)
    }

    func test_bundledFontsRegister() {
        for n in ["IBMPlexMono-Light", "IBMPlexSansSC-Light", "LXGWWenKaiMonoLite-Regular"] {
            XCTAssertNotNil(UIFont(name: n, size: 22), n)
        }
    }

    func test_plexCascadesToSansSC() {
        let list = SumiFont.plex.uiFont(size: 22).fontDescriptor.object(forKey: .cascadeList) as? [UIFontDescriptor]
        XCTAssertTrue(list?.contains { $0.postscriptName == "IBMPlexSansSC-Light" || ($0.object(forKey: .name) as? String) == "IBMPlexSansSC-Light" } ?? false)
    }

    func test_m1PrefsWithoutFontDecode() throws {
        let json = #"{"theme":"sepia","fontSize":30,"lineSpacing":2,"caretMotion":"steady","focusTyping":false,"typingSound":true,"soundPack":"thock"}"#
        let p = try JSONDecoder().decode(EditorPrefs.self, from: Data(json.utf8))
        XCTAssertEqual(p.theme, .sepia)
        XCTAssertEqual(p.fontSize, 30)
        XCTAssertEqual(p.lineSpacing, 2)
        XCTAssertEqual(p.font, .plex)
        XCTAssertEqual(p.caretMotion, .steady)
        XCTAssertFalse(p.focusTyping)
        XCTAssertTrue(p.typingSound)
        XCTAssertEqual(p.soundPack, .thock)
    }

    @MainActor
    func test_bumpSizeClampsAndResets() {
        let suite = "sumi.test.bump"
        UserDefaults().removePersistentDomain(forName: suite)
        let m = PrefsModel(store: PrefsStore(defaults: UserDefaults(suiteName: suite)!))
        m.prefs.fontSize = 95; m.bumpSize(2)
        XCTAssertEqual(m.prefs.fontSize, 96)
        m.prefs.fontSize = 9; m.bumpSize(-2)
        XCTAssertEqual(m.prefs.fontSize, 8)
        m.prefs.lineSpacing = 2.5
        m.resetSize()
        XCTAssertEqual(m.prefs.fontSize, 22)
        XCTAssertEqual(m.prefs.lineSpacing, 1.6)
    }

    @MainActor
    func test_prefsModelPersists() {
        let suite = "sumi.test.persist"
        UserDefaults().removePersistentDomain(forName: suite)
        let d = UserDefaults(suiteName: suite)!
        let m = PrefsModel(store: PrefsStore(defaults: d))
        m.prefs.theme = .crt
        XCTAssertEqual(PrefsModel(store: PrefsStore(defaults: d)).prefs.theme, .crt)
    }
}
