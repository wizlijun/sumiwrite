/// 打字音的播放入口;`TypingSound` 实现它。
protocol TypingSoundPlaying: AnyObject {
    /// `kind` 是输入代理判出的按键种类;`nil` 时由实现按前后文字自行分类。
    func play(before: String, after: String, kind: KeyKind?)
    /// 按下一个键就响一声,不看文字变没变:内嵌输入法吞下的按键(ios.md §3.6)。
    func play(kind: KeyKind)
    /// 偏好载入或改动后调用(主线程);打字音关掉时实现应当停掉引擎。
    func preferencesChanged(_ prefs: EditorPrefs)
}

extension TypingSoundPlaying {
    func play(before: String, after: String) { play(before: before, after: after, kind: nil) }
    func preferencesChanged(_ prefs: EditorPrefs) {}
}
