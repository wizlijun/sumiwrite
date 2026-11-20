/// 编辑面交给外壳的命令:硬件键盘快捷键与「正在打字」。
enum EditorCommand: Equatable {
    case newPage, prev, next, overview, appearance, menu
    /// 每次按键;外壳据此判断「最近在打字」。
    case typing
}
