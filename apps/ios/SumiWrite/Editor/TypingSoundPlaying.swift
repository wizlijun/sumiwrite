/// 打字音的播放入口;`TypingSound` 实现它。
protocol TypingSoundPlaying: AnyObject {
    /// 按下一个键就响一声(ios.md §3.4「发声时机」):输入代理在文字改动之前调,内嵌输入法吞下的键在 `pressesBegan` 里调;不经代理的改动在文字变了之后调。
    func play(kind: KeyKind)
    /// 偏好载入或改动后调用(主线程);打字音关掉时实现应当停掉引擎。
    func preferencesChanged(_ prefs: EditorPrefs)
}

extension TypingSoundPlaying {
    func preferencesChanged(_ prefs: EditorPrefs) {}
}
