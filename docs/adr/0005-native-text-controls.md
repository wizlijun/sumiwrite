# 0005 桌面用各平台原生文本控件,不用统一 Qt 或 Web 编辑器

类型:补记
状态:已采纳;现行于基线 v6.1117.1 的 `tauri-plugin-native-editor`(macOS 为 NSTextView/TextKit 2,Linux 为 GTK3 TextView)。Windows 尚无后端。
记录日期:2026-11-18;决定出处为主规范 §0、§4、§8 与 Omarchy 原生规范。

## 背景

note.md 宿主是 Tauri + 系统 WebView + ProseMirror。玄霜写作的正文要求:中文组字、选词、撤销正确;自绘光标下不出现系统细线;逐键路径不经 JS 中转(主规范 §2.2、§8)。原生控件的预期收益是缩短输入、组字与排版路径,减少 DOM 与跨进程同步压力,并直接使用系统文本服务(主规范 §4)。

## 决定

- **每个桌面平台用自己的系统文本控件**,封装在随宿主编译签名的 `tauri-plugin-native-editor` 里:macOS 为 NSTextView + TextKit 2(Objective-C ARC + 固定 C ABI 薄桥,宿主显式注册,不加载任意 dylib);Linux 为 GTK3 TextView/Overlay,在现有宿主事件循环中作为原生 surface,专注窗口与专用 Tab 共用。
- **统一的是编辑接口和文档语义,不要求控件实现一致**:Markdown/source map、行时间与 CRDT 全在 `write-core`(见 [0001](0001-rust-core-yrs-yjs-v1.md));桥只负责控件、布局、样式、焦点、IME、选区和编辑事务交接,不解析隐藏 YAML、不写文件、不连网。
- **性能必须实测,不凭框架名推断**:在同机器、同字体、同语料、同输入法下对比现有 Rich、简化 Web 基线与原生实现,至少 5 轮;不承诺几倍提升。实测不达标先定位瓶颈,再决定是否引入替代控件。
- Sumi 原生写作要求 macOS 13+(TextKit 2),不抬高宿主自身的 macOS 11.0 下限;旧系统只保留普通 Markdown 阅读与 Source。

## 放弃的方案

旧文档记录的:

- **统一 Qt**(Mac/Win 统一 Qt,或整桌面统一 Qt):用户明确不采用(主规范 §0、§8)。
- **Linux 上的 Qt 6 方案**:主规范原把 Omawrite 同栈的 Qt 6 `QTextDocument + Qt Quick TextEdit` 列为首选原型。Linux 实施时重新评审后改为 GTK3:宿主是 GTK3/WebKitGTK,QQuickWidget 是 QWidget,不能作为 GtkContainer 的子控件;Wayland 外部窗口不能嵌入 Tab;离屏 Qt 渲染要重做输入法、无障碍与焦点桥。该判断基于容器 API 的工程评审,未实测所有 Qt 集成方式(Omarchy 原生规范)。
- **Web 编辑器**:沿用宿主 WebView 内的富文本编辑,或 WebView 实现的“原生”库(如 wasabeef RichEditor),不列入系统原生方案(主规范 §4)。旧文档没有为否决 Web 编辑面写单独的比较表,理由散见于上文的收益分析与 §8 的“正文逐键路径不依赖 JS”。
- **第三方控件**:STTextView(要求 macOS 14+、GPLv3/商业双许可)保留为性能备选;RichTextKit 维护方向不确定(主规范 §4)。
- **Delphi 类方案**:属于讨论候选,未选为实现框架(主规范 §0)。
- **macOS 的 objc2/Swift 桥**:只保留 Objective-C 一种生产桥,不并行维护(macOS 计划)。

## 后果

得到的:

- 系统 IME、候选定位、辅助功能走平台正路;macOS 自绘光标能用公开 AppKit/TextKit API 抑制系统细线。
- Linux 的 Qt 依赖不进入 macOS/Windows 构建。

付出的:

- **每个平台一套原生代码**,行为对齐靠人工清单和探针(`native/*-probe.m` 等),不是靠共享实现;macOS 与 Linux 的体验对齐至今是专门的工作项。
- **原生桥编进宿主**:改控件行为、布局算法或原生接口,都必须重建、签名、公证并发布宿主,不能只发插件包(主规范 §8.1)。这条约束直接决定了 [0008](0008-standalone-repo-desktop-stays-plugin.md) 的后果。
- 原生 NSView 不服从 DOM z-index:裁剪、DPI、多显示器、弹层遮挡、焦点、快捷键、VoiceOver 都要单独验证。
- “用了 NSTextView”不等于启用了 TextKit 2,误用 `layoutManager` 会退回 TextKit 1,需要运行时检测。
- Windows 只有方向(Win32 Rich Edit),没有实现。
- 性能收益至今没有完整的物理输入到呈现帧证据;规范禁止用框架名替代这份证据。

## 来源

- 主规范 §0、§1、§2.2、§4、§4.1、§4.2、§8、§8.1:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md
- Linux 改用 GTK3 的评审:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-10-sumi-omarchy-native.md
- macOS / Linux 体验对齐清单:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-11-sumi-platform-parity.md
- macOS 桥形态(Objective-C + C ABI):https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/plans/2026-11-07-immersive-write-macos.md
- macOS 后端:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/native/editor.m
- Linux 后端:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/src/linux.rs
- macOS 13 检查:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/src/platform.rs
- 宿主最低系统 11.0:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/tauri.conf.json
