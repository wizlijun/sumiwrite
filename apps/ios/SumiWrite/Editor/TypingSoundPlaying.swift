/// 打字音的播放入口;任务 8 的 `TypingSound` 实现它。
protocol TypingSoundPlaying: AnyObject {
    func play(before: String, after: String)
    /// 偏好载入或改动后调用(主线程);打字音关掉时实现应当停掉引擎。
    func preferencesChanged(_ prefs: EditorPrefs)
}

extension TypingSoundPlaying {
    func preferencesChanged(_ prefs: EditorPrefs) {}
}
