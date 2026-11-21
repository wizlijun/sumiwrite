import Foundation
import RimeKit

enum CaretMotion: String, Codable { case breathing, steady }
enum SoundPack: String, Codable, CaseIterable { case typewriter, thock }

struct EditorPrefs: Codable, Equatable {
    static let fontSizeRange = 8.0...96.0
    static let lineSpacingRange = 1.0...3.0
    static let defaultFontSize = 22.0
    static let defaultLineSpacing = 1.6

    var theme: ThemeID = .dim
    var font: SumiFont = .plex
    var fontSize: Double = EditorPrefs.defaultFontSize
    var lineSpacing: Double = EditorPrefs.defaultLineSpacing
    var caretMotion: CaretMotion = .breathing
    var focusTyping: Bool = true
    var typingSound: Bool = true
    var soundPack: SoundPack = .typewriter
    /// 内嵌输入法切换中 / 英的快捷键(ios.md §3.6)。
    var switchShortcut: RimeSwitchShortcut = .controlSpace
    /// 接实体键盘时单独长按右 ⌥ 说话(ios.md §3.7「入口」)。
    var voiceKey: Bool = true
    /// 长语音先让 AI 整理(ios.md §3.7「AI 整理」);接入点没填好时不起作用。
    var voiceTidy: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EditorPrefs()
        theme = try c.decodeIfPresent(ThemeID.self, forKey: .theme) ?? d.theme
        font = try c.decodeIfPresent(SumiFont.self, forKey: .font) ?? d.font
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? d.lineSpacing
        caretMotion = try c.decodeIfPresent(CaretMotion.self, forKey: .caretMotion) ?? d.caretMotion
        focusTyping = try c.decodeIfPresent(Bool.self, forKey: .focusTyping) ?? d.focusTyping
        typingSound = try c.decodeIfPresent(Bool.self, forKey: .typingSound) ?? d.typingSound
        soundPack = try c.decodeIfPresent(SoundPack.self, forKey: .soundPack) ?? d.soundPack
        switchShortcut = try c.decodeIfPresent(RimeSwitchShortcut.self, forKey: .switchShortcut) ?? d.switchShortcut
        voiceKey = try c.decodeIfPresent(Bool.self, forKey: .voiceKey) ?? d.voiceKey
        voiceTidy = try c.decodeIfPresent(Bool.self, forKey: .voiceTidy) ?? d.voiceTidy
    }

    /// 字号加 `delta` 并夹到合法范围。
    func bumpingFontSize(_ delta: Double) -> EditorPrefs {
        var p = self
        p.fontSize = min(Self.fontSizeRange.upperBound, max(Self.fontSizeRange.lowerBound, fontSize + delta))
        return p
    }

    /// 超出范围返回 `nil`。
    func validated() -> EditorPrefs? {
        guard Self.fontSizeRange.contains(fontSize),
              Self.lineSpacingRange.contains(lineSpacing) else { return nil }
        return self
    }
}

struct PrefsStore {
    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults, key: String = "sumi.prefs") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> EditorPrefs {
        guard let data = defaults.data(forKey: key),
              let p = try? JSONDecoder().decode(EditorPrefs.self, from: data),
              let ok = p.validated() else { return EditorPrefs() }
        return ok
    }

    func save(_ p: EditorPrefs) -> Bool {
        guard let ok = p.validated(), let data = try? JSONEncoder().encode(ok) else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
