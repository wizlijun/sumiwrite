/// 打字音的播放入口;任务 8 的 `TypingSound` 实现它。
protocol TypingSoundPlaying: AnyObject {
    func play(before: String, after: String)
}
