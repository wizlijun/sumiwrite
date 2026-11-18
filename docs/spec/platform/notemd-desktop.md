# 平台附录 · note.md 桌面插件(macOS 与 Linux)

玄霜写作(Sumi Write)在桌面上不是独立应用,而是 note.md 的一个插件(插件 ID `notemd.sumi`),编辑区用宿主提供的原生文本控件。这样定的理由见 [ADR 0005](../../adr/0005-native-text-controls.md)、[ADR 0006](../../adr/0006-plugin-backend-vs-host-session.md)、[ADR 0008](../../adr/0008-standalone-repo-desktop-stays-plugin.md)。

本附录只写**桌面插件独有**的规则。各端共用的规则在主题规范里:纸页与存储见 [01](../01-pages-and-storage.md),Markdown 与行时间见 [02](../02-markdown-and-line-time.md),同步见 [03](../03-sync.md),编辑体验见 [04](../04-editing-experience.md),字体见 [05](../05-fonts.md)。宿主与插件之间的接口以 [`host-contract v1`](../../handoff/03-notemd-contract.md) 为准;本附录与契约冲突时,以契约为准。

- **基线**:宿主 tag `v6.1117.1`(`main` 的 `969f8e73`),插件 `0.1.16`。证据链接都指向这个 tag。
- **读法**:每个小节首行的 `状态:` 标注该节整体状态。节内某条规则状态不同,就在该条末尾另标。由实现方选定的数值(尺寸、时间、阈值)后缀 `(工程细则)`,表示它不是产品决定。
- **出入**:旧规范与代码不一致处以代码为准,在文中写明“出入”,并汇总进 [`04-known-gaps.md`](../../handoff/04-known-gaps.md)。

---

## 1. 插件形态

### 1.1 manifest 要点

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/manifest.v2.json

| 项 | 现值 |
|---|---|
| 插件 ID / 类型 | `notemd.sumi`,`kind: native` |
| 显示名 | 中文“玄霜写作”,英文与日文“Sumi Write” |
| 二进制 | `bin/notemd-sumi`,只有两个目标:`aarch64-apple-darwin`、`x86_64-unknown-linux-gnu` |
| 最低宿主 | `engines.notemd >=6.1111.1` |
| 激活 | `onCommand:open`。在插件菜单的“新建”子菜单下;托盘窗口放在“capture”分区 |
| 独立窗口 | `windows[id=main]`,`index.html`,960×720,manifest 中 `resizable: false`(实际是否可缩放见 1.2) |
| 文件视图 | `file_views[id=writing]`,`surface: native-editor`,`open_command: read-writing`,优先级 100。选择器要求扩展名为 `md`,且 frontmatter `type` 为 `Writing Page`。只接管纸页,不接管其他 `.md` |
| 能力 | `editor.native`、`editor.write`、`editor.open`、`vault.read`、`vault.write`、`editor.kit` |

宿主的授权门要求插件 ID 恰为 `notemd.sumi`,并且同时具备 `editor.native`、`editor.write`、`vault.read`、`vault.write` 四项能力。缺一项就拒绝,返回 `CAPABILITY_DENIED`,详见[契约 §1](../../handoff/03-notemd-contract.md)。

原生写作只在 macOS 13+ 与 Linux 上可用,其他系统挂载时报“当前系统尚不支持 Sumi 原生编辑”(`src-tauri/src/sumi/mod.rs`)。宿主本身的最低系统是 macOS 11;写作要求 13+,是因为用到了 TextKit 2。

### 1.2 独立窗口的尺寸与全屏

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/plugin_runtime/windows.rs

- **macOS**:新开的独立窗口按目标显示器的逻辑工作区摆放(依次取焦点所在、鼠标所在、主显示器),并扣除菜单栏与 Dock。窗口可缩放、可最大化,绿色按钮能进入系统原生全屏。设置里的“启动时进入全屏”默认开启,只在 Apple 平台出现,只影响此后新开的独立窗口;嵌入的写作标签页和 note.md 普通窗口不会自动全屏。来源:`src-tauri/src/plugin_runtime/windows.rs`、`plugins-src/write/src/main.ts`、旧规范 `2026-11-11-sumi-window-startup.md`。
- **Linux**:宿主对所有插件窗口强制可缩放(`desktop_policy.rs` 的 `plugin_window_resizable` 在 Linux 恒为真)。窗口按主窗口所在显示器的工作区摆放,实测 CSD 标题栏高度后居中。窗口菜单只挂一项“Close Window”(Ctrl+W),宿主的 Ctrl+N / Ctrl+S 加速键不会挂到插件窗口上。
- **全屏字号**:全屏后正文字号按窗口与 960×720 的比例放大。公式为 `基准 × sqrt(min(宽/960, 高/720))`,放大倍数夹在 1–1.25 之间,上限 96(工程细则)。两端一致,见 `src-tauri/src/sumi/mod.rs`。

> **出入**:manifest 写 `resizable: false`,但宿主在 Linux 上以及 macOS 的 Sumi 主窗口上都强制可缩放。以宿主行为为准。

---

## 2. vault 投影与外部修改的三方合并

纸页的本机事实源是内核的 SQLite 存储;vault 里的文件只是**投影**。两层为什么分开,见 [ADR 0009](../../adr/0009-page-store-vs-vault-projection.md) 与 [01-pages-and-storage](../01-pages-and-storage.md)。文件布局、frontmatter 键与 OKF 写入规矩以[契约 §3](../../handoff/03-notemd-contract.md) 为准,本节只写行为。

### 2.1 投影文件

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/projection.rs

- 正文文件是 `<vault>/inbox/writings/YYYY-MM-DD-NN.writing.md`,同目录另有 sidecar `YYYY-MM-DD-NN.writing.meta.json`,记录行级时间与行 ID。日期是首次有效输入时的本机日期,`NN` 是两位序号。一页的身份是 `page_id`,不是文件名。
- 目录不存在就创建。路径上任何一层是符号链接或者不是目录,都拒绝写入。
- 每个文件单独原子写入:先写临时文件 `.sumi-<uuid>.tmp`,`fsync` 后再重命名。**两个文件合起来不是原子的**,它们只是一份可恢复的投影。
- 发布前会比对磁盘基线的哈希。磁盘内容如果既不是“上次发布的”也不是“本次待发布的”,就停下来,先保全外部内容,改走导入。

投影写盘的节奏:**[未定]**。旧规范写“停笔后 0.5–1 秒防抖”。基线代码里能看到的是后台检查点调度:距最后一次编辑 250 ms,或距首次变脏 2 s,两者先到即触发(`plugins-src/write/backend/src/durability.rs` 的 `checkpoint_due`)。投影写盘是否就在这个检查点里完成,没有逐行核实。

### 2.2 外部修改走三方合并

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/import.rs

- 宿主监视投影文件,并能认出投影器自己写下的哈希。遇到不认识的修改,不覆盖,做三方导入。三方是:上次确认的投影基线、磁盘上的外部文本、当前 CRDT。差分按字素计算,单次导入有 100 ms 超时(工程细则)。
- 导入结果有三种:未变、已合并、冲突。冲突时三份文本都保留(基线、当前、外部),交给用户处理,**绝不整篇替换**。
- 宿主读外部文件时拒绝符号链接和超过 64 MiB 的文件(工程细则)。正文或 sidecar 缺失时,给出用户可读的错误(`src-tauri/src/sumi/external.rs`)。
- sidecar 迟到、缺失或成了孤儿,都**不等于**删除正文或云端纸页。修复入口是宿主命令 `host.sumi.restore_projection` 和“恢复”界面(`src/components/SumiRecovery.svelte`):可以恢复为新的一页、原文件不动;也可以保留原文件,再用本机已保存的正文和行时间重新写出这一页。

### 2.3 源码模式与身份字段

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/storage.rs

- 读回投影时,`type`、`write_metadata`、`schema`、`page_id`、`write_epoch`、正文哈希、行数和行 ID 序列必须全部一致才接受。

旧规范还要求:同一个文件不论在富文本、源码还是原生编辑面里打开,都只有一个文件 owner;用户在源码模式里改动或删除 `page_id`、`write_epoch`、`type` 时,暂停投影并标出身份冲突。这两条在代码中的具体路径没有逐行核实。[未定]

### 2.4 vault 同步工具

状态:[未定]

旧规范建议把 vault 的 Git / iCloud 只当归档,不当实时同步通道;纸页的实时同步走玄霜写作自己的同步服务(见 [03-sync](../03-sync.md))。这是建议,不是宿主强制的行为,基线代码里没有对应的检测。

---

## 3. 专用 Tab 与专注窗口共享会话

### 3.1 一页一个编辑 owner

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs

- 同一张纸页可以从两个入口打开:主窗口里的专用 Tab(文件视图),或者插件的专注窗口。两个入口共用同一个会话,任何时刻只有一个可编辑的原生编辑面。
- 宿主在挂载前检查这一页是否已有 owner。如果 owner 在另一个窗口或 Tab,挂载返回 `{"kind":"existing_owner"}`,调用方随即调用 `host.sumi.focus_existing`(需要 `editor.native` 能力),**聚焦已有的编辑面**,不新建第二个:
  - owner 在主窗口 Tab:宿主向主窗口发 `sumi-focus-owner`;
  - owner 在插件窗口:宿主显示该窗口、取消最小化,再聚焦。
- 挂载与命令都绑定插件、vault、纸页、Tab 和会话代数(generation),代数过期的命令一律拒绝。窄接口包括:`mount`、`command`(边界、外观、焦点、可见性、文档投影)、`inspect`、`detach`,以及修订、选区、保存状态等事件。全部列表见[契约 §1.2 表 B](../../handoff/03-notemd-contract.md)。
- 组字中不能强行 `detach`。要打开面板时,先发显式的 `PreparePanel` 交接:用同一个本地事务提交当前可见的预编辑,再释放组字并隐藏编辑面。

### 3.2 owner 交接时的上下文转移

状态:[未定]

旧规范写,Tab 与窗口之间切换时“转移选区、滚动与撤销上下文”。基线代码里看到的是“第二个入口去聚焦已有编辑面”,没有看到在两个编辑面之间转移选区、滚动或撤销栈的交接。阅读位置的恢复走 `SurfaceConfig` 里的初始 `selection` 与 `viewport`(见 `tauri-plugin-native-editor/README.md`),那是重新挂载时用的,不是 owner 交接。是否还需要真正的交接,留待第 3 期会话下沉(`session/`,见 [ADR 0012](../../adr/0012-shared-session-module.md))时定。

---

## 4. 宿主更新边界

### 4.1 三层代码各自随谁发布

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/scripts/release-plugins.sh

下表是**归纳**,没有哪一个源文件直接写着这张表。它由三处来源拼成:

- 旧主规范 §8.1 的三层表;
- 插件打包脚本 `scripts/release-plugins.sh` 的 `release_sumi()`:插件界面和后台二进制 `bin/notemd-sumi` 一起打进插件包;
- 宿主 `src-tauri/Cargo.toml`:原生编辑桥以 `tauri-plugin-native-editor = { path = ... }` 编进宿主,证据 https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/Cargo.toml 。

发版规则以[契约 §4](../../handoff/03-notemd-contract.md)为准。

| 层 | 现位置(基线) | 怎么更新 |
|---|---|---|
| 插件界面 | `plugins-src/write/`(将迁入 sumiwrite) | 随 Sumi 插件包发布,宿主不用发版 |
| 插件后台 | `plugins-src/write/backend/`(将迁入 sumiwrite) | 随插件包发布。前提是后台服务协议仍与宿主兼容(`sumi-protocol` 的握手,见[契约 §1.4 表 D](../../handoff/03-notemd-contract.md)) |
| 原生编辑桥 | `tauri-plugin-native-editor/`(**留在 note.md**) | 编进宿主。改它就要重编、签名、公证并发布宿主 |

改动落在哪一层,决定了要不要配套发宿主。现行规则写在[契约 §4 发版配合](../../handoff/03-notemd-contract.md):

- 契约版本不变时,只发插件包;
- 新增可选能力时,宿主先发;
- 主版本变化或服务协议 `VERSION` 变化时,两边配套发版。

**先例**:聚焦状态下上下键居中这次修正,改到了原生编辑桥,所以是宿主 `6.1109.4` 与 Sumi `0.1.9` 一起发的。证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-09-sumi-focus-arrow-release.md

### 4.2 可独立更新的编辑模块

状态:[未定]

旧规范把“让原生编辑能力不必随宿主发版就能更新”列为远期目标,至今没有实现。原生编辑桥的去留与桌面是否独立绑在一起,判断标准见 [later.md · 桌面独立应用](later.md)。

---

## 5. macOS

### 5.1 键位表

状态:[已交付:macOS] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/native/shortcuts.h

匹配看完整的修饰键集合,只认 ⌘、⇧、⌥、⌃ 四个,多按一个修饰键就不是同一条命令。组字期间这些键先归输入法。下表列出插件接管的命令;下表之外,系统文本服务键(方向键、⌥ 方向键按词移动、⌘ 方向键、Home/End/Page 等)保持 AppKit 原有语义,修改内容仍经过内核。

| 键 | 命令 | 键 | 命令 |
|---|---|---|---|
| ⌘A | 全选 | ⌘⇧Z | 重做 |
| ⌘C / ⌘X / ⌘V | 复制 / 剪切 / 粘贴 | ⌘⇧V、⌘⌥⇧V | 粘贴为纯文本 |
| ⌘Z | 撤销 | ⌘⇧X | 删除线 |
| ⌘B / ⌘I | 粗体 / 斜体 | ⌘⇧G | 查找上一个 |
| ⌘K | 链接 | ⌘⇧S | 导出 |
| ⌘F / ⌘G | 查找 / 查找下一个 | ⌘⇧9 / ⌘⇧8 / ⌘⇧7 | 引用 / 无序列表 / 有序列表 |
| ⌘⌥F | 替换 | ⌘⌥0 | 正文段落 |
| ⌘N | 新建纸页 | ⌘⌥1 – ⌘⌥6 | 一至六级标题 |
| ⌘⌥← / ⌘⌥→ | 上一页 / 下一页 | ⌘] / Tab | 增加缩进 |
| ⌘O | 菜单 | ⌘[ / ⇧Tab | 减少缩进 |
| ⌘S | 保存 | ⌘= / ⌘+ / ⌘⇧= | 放大字号 |
| ⌘W | 关闭 | ⌘- / ⌘0 | 缩小字号 / 复原字号 |
| ⌘, | 设置 | ⌘Return、⌘ 小键盘 Enter、⌃⌘F | 全屏切换 |
| Esc | 先关查找栏;没有查找栏时打开菜单 | 系统 `insertLineBreak:` | 段内硬换行 |

- 按住不放产生的重复事件不会反复切换全屏。退出全屏后,窗口恢复原来的尺寸。来源:`tauri-plugin-native-editor/README.md`、`native/editor.m`。
- 旧规范写过全屏键“Cmd/Win/Super+Enter”。macOS 保留 ⌘Return,Linux 已改为 F11,见 6.2。

### 5.2 AppKit 实现要点

状态:[已交付:macOS] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/README.md

- **控件**:ARC Objective-C 写的 AppKit 桥,控件是 `NSTextView(initUsingTextLayoutManager:YES)`,需要 macOS 13+。只调用这个初始化方法还不足以证明真的跑在 TextKit 2 上,误用旧 `layoutManager` 会退回 TextKit 1,所以 `inspect` 会报告 TextKit 2 的实际状态,供验收使用。
- **层级**:原生编辑面作为 WKWebView 的兄弟视图挂在它上面。坐标是相对 WebView 视口左上角的逻辑点,由桥换算标题栏与安全区偏移。所有 API 都派发到主线程。
- **编辑事务**:`Edit` 是对 `base_revision` 的一次 UTF-16 替换。宿主返回更大的修订号之前,必须先把这次操作同步写进本机崩溃日志。日志写失败时走 `draft_error`(原生 ABI 返回 -2):编辑面保留当前可见文字,但禁止继续修改,直到重存成功。
- **组字**:组字中的文字(marked text)不发 `Edit`,输入法确认时才发一次已提交的 `Edit`。组字期间,`ApplyDocument` 和外观、可见性变更都返回 `composition active`,宿主先把远端更新排队,不丢弃。
- **撤销与格式**:AppKit 自带的撤销关闭,撤销/重做交给 CRDT 的撤销 owner。只改属性的 AppKit 编辑一律拒绝,格式只能通过 Action 修改。
- **粘贴**:粘贴 HTML 或 RTF 时发 `Paste`,附带纯文本兜底,由宿主清洗。桥本身从不把任意 HTML 导入 AppKit。
- **光标**:系统光标被压住不显示,改为自绘竖线光标,宽 2–3 pt(工程细则)。可选呼吸(Core Animation,周期 4 s,工程细则)或常亮。光标规则见 [04-editing-experience](../04-editing-experience.md)。
- **字体**:`register_font` 只注册经过 SHA 校验的缓存字体,作用域限于进程,并核对实际字族,不往系统安装字体。字体组合规则见 [05-fonts](../05-fonts.md)。
- **凭据**:设备长期凭据存在宿主进程的 macOS 钥匙串里,服务名 `com.notemd.sumi.credentials.v1`,插件只能经窄授权代理使用(`src-tauri/src/sumi/credentials.rs`)。

---

## 6. Linux / Omarchy

### 6.1 实现要点

状态:[已交付:Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/src/linux.rs

- **控件**:GTK3 `TextView`,放在宿主自己的 GTK overlay 和事件循环里,支持原生 Wayland 输入。它和 macOS 遵守同一套宿主持有的事务与 UTF-16 协议。展示层用 GTK 的真实显示行和插入光标(`linux_focus.rs`)。
- **窗口缩放**:宿主钉住了一份 `tauri-runtime-wry` 的 GTK 兼容补丁(`vendor/tauri-runtime-wry/NOTEMD_PATCH.md`)。原生 overlay 多出一层容器后,鼠标和触摸缩放仍能找到真正的顶层窗口。
- **光标**:光标画在单独的小绘图区里。在 Wayland 上,它挂在原生 GDK subsurface 上(`linux_caret.rs`),呼吸时不重绘共享的 WebKit 表面;输入区域为空,鼠标事件可以穿透。GTK 自带光标的两种颜色都设为透明。
- **字体**:通过 Fontconfig 做进程内注册。
- **凭据**:经 libsecret 存入系统密钥环。凭据不出现在命令行参数、vault、偏好或日志里(`src-tauri/src/sumi/credentials_linux.rs`)。
- **音效**:经 PulseAudio 播放,也兼容 PipeWire 的 Pulse 服务。
- **RTF 粘贴**:只有 RTF 的剪贴板内容,用 `rclip-rtf` 0.1.0 转成纯文本。输入与解码结果各限 2 MiB(工程细则)。旧式中日韩代码页字节一律拒绝,并提示改用纯文本复制。
- **打包**:Arch 包 `.pkg.tar.zst`,目前只有 x86_64。

> **出入**:旧规范 §4.1 推荐“Qt 6 富文本原型”,GTK3 只是备选;代码实际选了 GTK3 TextView overlay,决定记录在旧规范 `2026-11-10-sumi-omarchy-native.md`。以代码为准。

验收口径沿用旧规范(Omarchy 优先),其中多项**尚未有物理证据**,逐条见 6.4:

- 在 Hyprland 原生 Wayland 下验收,XWayland 单列;
- Fcitx5 正常工作,不要求全局覆盖 `GTK_IM_MODULE` / `QT_IM_MODULE`;
- 快捷键避开 Omarchy 的 Super 系绑定。

### 6.2 与 macOS 的必要差异

状态:[已交付:Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/src/linux.rs

键位把 ⌘ 换成 Ctrl、把 ⌥ 换成 Alt,其余同 5.1。Super 留给桌面环境,插件不用。修饰键要完全匹配;Caps Lock 不算修饰键,Shift 照常参与区分(Ctrl+Shift+V 和 Ctrl+V 是两条命令)。下表只列不同之处:

| 项 | macOS | Linux | 原因 |
|---|---|---|---|
| 全屏 | ⌘Return、⌘ 小键盘 Enter、⌃⌘F | **F11**(不带任何修饰键;带修饰键的 F11 不触发) | 避开 Omarchy 的 Super 绑定,遵循 Linux 惯例(旧规范 `2026-11-10-omarchy-plugin-shortcuts.md`) |
| 重做 | 只有 ⌘⇧Z | Ctrl+Shift+Z,**另有 Ctrl+Y** | Linux 惯例 |
| Esc | 先关查找栏,再打开菜单 | 直接打开菜单 | macOS 用的是系统查找栏 |
| 硬换行 | 系统 `insertLineBreak:` 动作 | Shift+Return / Shift+小键盘 Enter | GTK 没有对应的系统动作 |
| 减少缩进 | ⇧Tab | Shift+Tab 或 `ISO_Left_Tab` | X/GTK 的键值差异 |
| 粘贴为纯文本 | 另有 ⌘⌥⇧V | 只有 Ctrl+Shift+V | — |
| 窗口装饰 | 系统标题栏,绿色按钮全屏 | GTK CSD,宿主实测标题栏高度;全屏时菜单放在顶部,避开 dock | Hyprland 平铺与 CSD |
| 启动时进入全屏 | 有此偏好,默认开 | 无此偏好 | 只在 Apple 平台提供(`plugins-src/write/src/main.ts`) |
| 音效运行目录 | 系统音频 | 需要 Pulse 运行目录 | 平台差异,见旧规范 `2026-11-11-sumi-platform-parity.md` |

**各行的证据强度不同**:

- **全屏 F11**:有真实 GUI 证据。正式 GUI 验收里,正文与面板各做了两次 F11 往返;另有本机安装后的 F11 实测往返。见 `docs/superpowers/reports/2026-11-10-omarchy-plugin-window-release/README.md`。
- **窗口装饰与顶部全屏工具区**:有 GUI 证据。但验收是在私有 Sway 会话里做的,真实 Omarchy dock 没有启动,“避开 dock”只靠几何推断(同一报告)。
- **只有单元测试、没有物理按键证据**:[未定]
  - Shift+Return / Shift+小键盘 Enter 硬换行;
  - Shift+Tab / `ISO_Left_Tab` 减少缩进;
  - 修饰键精确匹配与 Caps Lock 处理。

  这些都只在 `linux.rs` 的 `linux_hard_break_requires_only_shift`、`linux_shortcuts_use_exact_modifiers`、`linux_shortcuts_ignore_caps_lock_letter_case_without_ignoring_shift` 里测过。平台对齐报告也写明硬换行“没有 Linux GTK 实机证据”。
- **单元测试也没有逐项覆盖**:Ctrl+Y 重做、Esc 打开菜单。基线上只有 `shortcut()` 里的映射代码,没有对应的断言,也没有物理证据。[未定]

### 6.3 Fcitx5 for Sumi 对接契约

状态:[已交付:Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/src/linux_candidates.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-11-omarchy-amd64-ime-release/README.md ;macOS 侧另标,见下文“macOS 接口”

Fcitx5 for Sumi 是独立的输入法项目,不并入本仓库;本节只写对接契约。**[我的判断]**(设计 §2)没有装它时,写作照常可用,候选框退回系统默认样式。

**候选呈现规则**(两端规则相同,来源旧规范 `sumi-ime-cross-platform.md`;macOS 一侧的真机物理验收 [未定]):

- 聚焦状态下,候选出现在输入行的下一显示行,向下展开;
- 非聚焦状态下,输入行原地不动,候选固定在底部,向上展开;
- 最多 4 行(工程细则),不加背景和边框;
- 预编辑不加蓝色底,候选里不出现 emoji;
- 只把候选绑定到当前编辑面这一个精确的输入上下文。连不上增强接口时,退回系统默认候选框。

**Linux 接口**(D-Bus):

| 项 | 值 |
|---|---|
| 服务 / 路径 / 接口 | `org.fcitx.Fcitx5` / `/org/fcitx/Fcitx5/SumiCandidates` / `org.fcitx.Fcitx.SumiCandidates1` |
| 方法 | `SetActive`、`SetActiveWithTyping(token, programs, active)`、`Select`、`Page` |
| 信号 | `Revoked`;`TypingKey`,角色有 Key / Space / Enter / Delete / Modifier / KeyUp / SpaceUp,用于输入音效 |
| 输入上下文 | 经 `org.fcitx.Fcitx.Controller1` 取当前聚焦的输入上下文 |
| 调用约束 | `NO_AUTO_START`,超时 1000 ms(工程细则)。插件只**检查** `GTK_IM_MODULE`,从不设置它 |

**Linux 打包**:addon 包 `fcitx5-sumi-candidates`(源仓库 `packaging/omarchy/fcitx5-sumi-candidates/`),依赖 `fcitx5>=5.1.23` 且 `<5.2`,运行时需要 `fcitx5-chinese-addons` 与 `fcitx5-gtk`,不需要 Qt 模块。用 `pacman -U` 和宿主一起装,装完要注销后重新登录。它提供三样东西:候选桥、预编辑下划线、输入音效用的按键回馈。它以 LGPL 发布,不改 ClassicUI 和个人配置。按真实按键发声的完整输入音效,需要宿主配合 r4 版 addon(`5.1.23.r4`),两者须同时更新(`CHANGELOG.zh-CN.md`)。

**macOS 接口** [已交付:macOS] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/native/candidates-bridge.h ;macOS 真机物理输入法终验 [未定]。

用 CFMessagePort 通信,来源 `tauri-plugin-native-editor/native/candidates-bridge.h`、旧规范 `2026-11-10-sumi-macos-fcitx-bridge.md`。

- 消息端口名:标记前缀 `com.notemd.sumi.candidates.v1.`,回复前缀 `org.fcitx.Fcitx5.Sumi.`;单条消息上限 256 KiB(工程细则)。
- 消息序列:hello / ready / snapshot / prepared / present / select / page / ping / pong / release。
- 保活:250 ms ping 一次,1 s 内无回应即判失联(工程细则)。

**macOS 分发**:每次发布 macOS 宿主,都附上经过核准的 Fcitx5 for Sumi 安装包。它**不在** note.md 的自动更新载荷里,需要用户单独安装。现值见 `scripts/release-companions/fcitx5.json`:

- 版本 0.5.0.15,仅 Apple Silicon(darwin-aarch64);
- 其中的 App 已公证,但**安装包本身未签名**(`packageSigned: false`)。安装包签名 [未定]。

macOS 内嵌候选随宿主 `v6.1110.8` / Sumi `0.1.13` 首发(`CHANGELOG.zh-CN.md`)。真机物理输入法的最终验收**未执行** [未定],见 `docs/superpowers/reports/2026-11-11-sumi-macos-ime-plugin-release/README.md`。

> **出入**:旧规范 `2026-11-10-sumi-fcitx-candidates.md` 和 `v6.1110.2` 的更新日志写的是正文贴底布局,后来在 `v6.1110.4` 改为“非聚焦状态下输入行原地不动”。以现行规则为准。

### 6.4 平台对齐的遗留项

状态:[未定]

以下各项在发布报告里写明没有物理证据,或者根本没有验证过(`docs/superpowers/reports/2026-11-11-sumi-platform-parity.md` 等):

- 平台对齐 P1 的根因未确认;
- P8 缺少完整宿主加物理输入法的证据;
- Linux 硬换行没有 GTK 物理证据;
- Linux 只验证了 x86_64,ARM64 Linux 未验证;
- Hyprland 分数缩放、XWayland、VoiceOver 等无障碍能力未验证。

---

## 7. Windows

### 7.1 Windows 桌面插件

状态:[未定]

Windows **没有交付**。插件二进制没有 Windows 目标,宿主在 Windows 上挂载原生编辑面会报“当前系统尚不支持”。旧规范的选型方向(Win32 Rich Edit HWND 内嵌)和后续评估,统一记在 [later.md · Windows](later.md)。
