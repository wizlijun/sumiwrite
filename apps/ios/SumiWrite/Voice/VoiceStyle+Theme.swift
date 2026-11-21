import UIKit
import VoiceKit
import VoiceKitUI

extension VoiceStyle {
    /// Sumi 的两色主题与纸页当前的字体(气泡用 17pt);环带与提示行的字(ios.md §3.7「按住时」);
    /// 长按右 ⌥ 说话时提示行是 `keyboardHint`(§3.7「入口」)。
    /// 「原话」只在 Sumi 里:rapp 的「编辑」在这里是「不整理,直接插入」。
    static func sumi(_ prefs: EditorPrefs, reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled) -> VoiceStyle {
        VoiceStyle(
            foreground: prefs.theme.foreground,
            background: prefs.theme.background,
            font: prefs.font.uiFont(size: 17),
            labels: [.send: "插入", .edit: "原话", .cancel: "取消"],
            hints: [.send: "松手 插入", .edit: "松手 插入原话", .cancel: "松手 取消"],
            keyboardHint: "松开 ⌥ 插入 · Esc 取消 · Tab 原话",
            reduceMotion: reduceMotion,
            buttonSize: 44)
    }
}
