# 04 编辑体验

本文描述玄霜写作(Sumi Write)当前的编辑体验:排版、主题、光标、聚焦与视区、窗口、编辑操作、剪贴板、输入法边界和打字音。这里只写与平台无关的产品规则。AppKit、GTK、Fcitx 的实现方法,以及具体键位,都放在平台附录 [platform/notemd-desktop.md](platform/notemd-desktop.md)。字体见 [05-fonts.md](05-fonts.md)。

写法约定:

- 由实现团队补充、不是用户逐项选定的数值(尺寸、时间、阈值、比例)都标 `(工程细则)`。
- 证据链接一律指向宿主 tag `v6.1117.1`(基线)下的源码、CHANGELOG 或发布报告。插件没有自己的 tag。
- 旧规范与基线代码不一致时,本文以代码为准。分歧记入 [../handoff/04-known-gaps.md](../handoff/04-known-gaps.md)。

外观偏好只影响显示,包括主题、字体、字号、行距、列宽、底部留白、光标动态、聚焦打字和启动全屏。修改外观不改正文、选区、revision 或行时间。

## 排版

### 排版默认值

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/contract.ts https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs

| 偏好 | 默认值 | 允许范围 |
|---|---|---|
| 字号 | 22 pt | 8–96 |
| 行距 | 1.6 | 1–3 |
| 正文最大宽 | 80 个半角列(约 40 个中文全角字) | 20–200 列 |
| 底部留白 | 0 | 0–2000 逻辑点 |
| 主题 | 黑底灰字(`dim`) | 见“主题” |
| 字体 | 第一组 `Sumi Plex` | 见 05-fonts |
| 光标动态 | `breathing` | `breathing` / `steady` |
| 聚焦打字 | 开 | 开 / 关 |
| 启动时全屏 | 开(仅 macOS 有此选项) | 开 / 关 |

以上默认值和范围都是 `(工程细则)`。80 列参考的是 W3C 阅读排版指导中的 80 字符 / 40 CJK,不是写作软件的通行强制标准。

- 正文左对齐。列宽按当前字体的实际字宽计算。窗口窄时取可用宽度。
- 软折行不插入 Markdown 换行,也不产生行时间记录。
- 旧设置缺某个字段时补默认值,其他字段保持不变。超出范围的值保存时被拒绝。

### 留白随字号缩放

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/native/editor.m https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/src/linux.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md

四周留白与字号同步缩放,算法如下(数值均为 `(工程细则)`)。设 `s = 当前字号 / 22`:

1. 左右最小留白 = max(16, 24 × s),且不超过视口宽度的 1/4。
2. 上下留白 = max(20, 32 × s),且不超过视口高度的 1/4。
3. 正文宽 = min(视口宽 − 2 × 左右最小留白, 最大列数 × 单字宽)。
4. 正文水平居中。实际横向留白 = max(左右最小留白, (视口宽 − 正文宽) / 2),所以可以大于最小留白。

另外两条规则:

- 底部留白是独立的绝对逻辑点数,不随字号缩放,也不占用上下留白。
- 窗口又窄又矮时仍保留可用正文宽度。超出视口的内容按原生滚动阅读。

### 主题

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/contract.ts https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/main.ts

共有六个主题。下表的色值是宿主交给原生正文编辑器的值:

| 键 | 名称 | 正文与光标色 | 背景色 |
|---|---|---|---|
| `ink` | 黑底白字 | `#ffffff` | `#000000` |
| `dim` | 黑底灰字(默认) | `#b8b8b8` | `#111111` |
| `paper` | 白底黑字 | `#111111` | `#ffffff` |
| `sepia` | 米色深灰 | `#44413c` | `#f3ead7` |
| `crt` | 复古绿磷 CRT | `#0ccc68` | `#000000` |
| `crt-blue` | 复古蓝磷 CRT | `#7fb4ff` | `#000000` |

- 编辑区、光标、选区和留白都使用同一主题。选区保留正文前景色,背景为前景色的 22% 透明度 `(工程细则)`。
- 两个 CRT 主题的配色参考 cool-retro-term:绿色取自 Monochrome Green,蓝色取自 Deep Blue。它们不是行业统一标准。
- 主题与字体分开选择。换主题不改字体和字号。
- 保存时只接受上表六个键。
- 设置面板(Web 界面)跟随主题配色,但其中 `ink`、`dim`、`paper` 三项的色值与上表不完全相同。见 known-gaps。

### 光标

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/native/editor.m https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/src/linux_focus.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md

- 外形:一条主题色的稍粗竖线,取代系统默认的细光标。宽度为字号 / 11,并限制在 2–3 pt 之间,只随字号小幅变化 `(工程细则)`。高度取当前字体的 ascender 到 descender,不扩展到行距。
- 普通输入、中文组字的多次更新和最终提交,全程只显示这条自定义竖线。系统细光标始终隐藏。
- `breathing`(平缓呼吸)是默认值:每 4 秒一轮,2 秒渐暗、2 秒渐亮,明暗平滑往返,最低不透明度约 0.25 `(工程细则)`。连续输入不重启相位,节奏保持稳定。
- `steady`(不闪烁,常亮):立即停止动画,保持完全不透明。输入事务中出现临时选区或布局变化时,光标也不消失。
- 用户在玄霜写作里选的光标动态说了算。系统的“减少动态效果”不会覆盖这个选择,玄霜写作也不修改系统偏好。
- 旧设置没有光标动态字段时,按 `breathing` 补齐。

以下情形不显示光标,并且停止后台动画:

- 编辑器失焦或被隐藏;
- 存在非输入事务造成的普通范围选区;
- 插入点离开可视区;
- 插入点被候选区覆盖。

恢复聚焦或重新可见后,光标正确恢复。

## 聚焦与视区

### 聚焦打字:当前行居中渐隐

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/src/linux_focus.rs

“聚焦打字”(`focusTyping`)默认开启,可以在外观设置里关闭。

**进入聚焦**

- 2 秒内的有效输入累计达到 4 次时进入聚焦。计数用滑动窗口 `(工程细则)`。
- 用户移动光标或滚动阅读之后,第一个真实输入立即回到聚焦,不必重新累计。拼音预编辑也算真实输入。

**聚焦时的呈现**

- 当前行固定在有效视区的垂直中线上。有效视区指扣除底部留白后的区域。
- 字号、行距和横向排版都保持不变。
- 上下文按与当前行的距离逐级渐隐,到视区边缘为 0。相邻一行约为 55%,每远一行再乘 0.55,同时乘以随距离平方衰减的边缘系数 `(工程细则)`。
- 进入过渡 0.2 秒。停笔 10 秒后,用 1.2 秒让上下文恢复完全可见。再次输入时,0.2 秒内回到渐隐 `(工程细则)`。
- 聚焦状态下按上、下方向键移动,当前行仍保持居中。空白页或首行从中线开始。
- 回车后,上文必须仍然可见且连续。
- 位置稳定:文档、光标、字号和视区都不变时,重复居中必须得到同一滚动位置和同一正文像素位置;平滑移动结束后不再跳动。浮点滚动值与平台整数像素之间按平台实际的取整规则换算,不靠放大误差容限掩盖抖动。Linux 已修复半像素来回跳动,并有重复居中幂等的单测。[已交付:Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/tauri-plugin-native-editor/src/linux.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md macOS 上没有找到同等的验收记录。[未定]

**退出聚焦与不触发的情形**

- 移动光标或滚动阅读时回到普通页面。
- 下列动作不算打字活动:挂载、程序设置选区、远端投影、切换、隐藏或重新显示、纯修饰键、快捷键、粘贴、取消组字、打开面板时的交接。
- 下列状态下不进入聚焦:只读、偏好已关闭、保存失败、编辑面隐藏或会话已过期。
- 系统开启“减少动态效果”时,直接呈现聚焦后的最终状态,不播放空间位移动画。光标动态偏好不受影响。
- 预编辑和最终提交保持原生语义、选区和候选几何。不会为了触发聚焦而提前提交组字。

### 非聚焦输入

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-11-sumi-platform-parity.md

适用于关闭聚焦打字,或尚未进入聚焦的时候:

- 打字时,当前行、光标和滚动位置都保持原位。
- 候选区出现或翻页时,不推动正文,也不改变正文视区高度。
- 候选区的具体呈现属于配套输入法,见平台附录。

正文区不显示滚动条和边框。

### 进入后从文末续写

状态:[已交付:Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-12-sumi-entry-release/README.md https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-12-sumi-entry-end/README.md https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md

这项行为随宿主 6.1112.2 / Sumi 0.1.15 首次发布。

- 新建编辑面时,光标落在正文末尾(按 UTF-16 计),视区滚动到末行可见。新建编辑面包括冷启动、关闭后重新进入和新打开一页。
- 正文以换行结尾时,光标落在最后的空行上。
- 从设置面板返回,或已有编辑面重新获得焦点时,保留当前选区和编辑位置。
- note.md 主窗口里的写作标签恢复已保存的阅读位置,不跳到文末。
- macOS:修复提交已包含在 macOS 发布 v6.1116.1 中,但没有找到专门的 macOS GUI 验收记录。[未定]
- Sumi 0.1.16 只更正了插件界面中配套输入法的名称(Fcitx5 for Sumi),编辑行为与 0.1.15 相同。

### 全屏字号

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md

- 独立写作窗口全屏时,有效字号 = 保存的字号 × clamp(√min(逻辑宽 / 960, 逻辑高 / 720), 1, 1.25),上限 96 `(工程细则)`。
- 保存的字号偏好不变。退出全屏后恢复保存的字号。
- 窗口在全屏中异步调整尺寸时,有效字号随之重算。
- 组字期间暂不应用新字号,组字结束后再应用。
- note.md 主窗口里的写作标签不做全屏放大。

### 底部留白

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/contract.ts

- 桌面端可以设置底部留白,默认 0。它是为键盘、候选区或今后自制输入法预留的空间。
- 设置底部留白后,聚焦的中线和渐隐边缘都按扣除留白后的有效视区计算。光标和候选区始终在可用编辑区内,不会被留白挡住。
- 移动端按系统键盘的实际 inset 让位,连接硬件键盘后收回空白。[计划:iOS] 见 [platform/ios.md](platform/ios.md)。

## 窗口

### 专注窗口与全屏(仅桌面)

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/manifest.v2.json https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md

本节只适用于桌面端。

- 独立写作窗口的默认逻辑尺寸是 960 × 720 `(工程细则)`。插件 manifest 声明窗口不可缩放(`resizable: false`)。
- 独立写作窗口在两个平台上都可以拖动改变大小,尽管 manifest 声明的是不可缩放。macOS 上由宿主对这个窗口单独放开(同时保留绿色全屏按钮);Linux 上宿主对所有插件窗口放开。[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/plugin_runtime/windows.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/desktop_policy.rs 平台细节见 [platform/notemd-desktop.md](platform/notemd-desktop.md),manifest 与实际行为的出入记在 [known-gaps](../handoff/04-known-gaps.md) §4.6、§4.9。
- 新窗口按当前显示器的可用工作区布局,不超出小屏范围。
- 可以进入和退出系统原生全屏。全屏往返时保留光标和滚动位置,保留标准的退出方式。
- macOS 有“新窗口以全屏打开”选项,默认开启。修改后从下一个新建的独立窗口开始生效。再次激活已打开的窗口时,不改变用户选定的非全屏状态。[已交付:macOS] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md
- Linux 窗口保留可拖动的标题栏,可以缩放(见本节第二条),启动尺寸适配可用桌面。[已交付:Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md
- 当前偏好里没有窗口规格选项。是否提供,[未定]。
- 平铺窗口管理器下,固定尺寸窗口如何与之协商:[未定]。见 [platform/notemd-desktop.md](platform/notemd-desktop.md)。
- note.md 主窗口里的写作标签跟随宿主布局,不会自动全屏,也不强制主窗口使用固定尺寸。

### 按需工具与状态提示

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/main.ts https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md

- 写作界面没有常驻工具栏。前一页、后一页、新页、纸页列表、外观、同步和全屏这些入口,只在指针悬停或键盘聚焦时出现。
- 底部状态提示平时隐藏,悬停或聚焦时才显示。
- 例外:严重的保存失败会一直显示,并提供“重试保存”。
- 退出当前弹层的操作关闭设置等面板。

## 编辑操作

### 快捷键语义

状态:[已交付:macOS] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md

本节只规定每个操作做什么。具体键位见平台附录 [platform/notemd-desktop.md](platform/notemd-desktop.md)。

通用规则:

- 菜单、键盘和右键菜单走同一套命令语义。
- 原生正文有焦点时,命令作用于当前纸页。设置面板里的输入框保持普通的系统编辑行为。
- 快捷键不能误操作 note.md 主窗口、其他标签或另一篇稿件。
- 修饰键按完整组合精确匹配,多按了 Ctrl、Option 或 Shift 时不会变成另一个动作。
- 组字期间不执行应用命令。

| 操作 | 行为 |
|---|---|
| 全选、复制、剪切、粘贴 | 全选只选正文。剪贴板规则见下文。剪切先确认复制成功 |
| 纯文本粘贴 | 与普通粘贴共用文本化清洗,但按字面插入,不解释 Markdown,不引入外来样式 |
| 撤销、重做 | 本机文档事务,只有一套撤销栈。撤销只撤本设备本次操作,保留远端后来的输入 |
| 按字符、词、行、文档移动 | 按 UTF-16 与字素安全移动,保持原生的视觉行导航 |
| 扩展选择 | 不切开代理对或组合字素,支持跨行选择和全文选择 |
| 删除(字符、词、至行首) | 沿用系统语义,统一转成文档事务 |
| 原生文本服务键 | 保持系统的移动、删除、转置语义,修改仍经过内核。不侵占输入法切换或 emoji 快捷键 |
| 换行、显式换行、缩进、反缩进 | 见“Return 与缩进” |
| 粗体、斜体、删除线 | 有选区时切换对应的 Markdown 格式。空选区时切换后续输入的样式,再按一次关闭 |
| 标题(1–6 级)、正文 | 把当前段落或所选段落设为对应标题级别,或恢复为正文 |
| 引用、无序列表、有序列表 | 作用于当前或所选逻辑段落,保持选区,可撤销 |
| 链接 | 在正文内编辑 Markdown 链接 |
| 查找、下一个、上一个、替换 | 只在当前纸页内。替换走同一个文档事务,不绕过 source map 和行时间 |
| 新页、纸页列表、前一页、后一页 | 本产品的纸页操作,不新建普通 Vault 文件,也不打开宿主里的其他文档 |
| 立即保存、导出快照 | 在自动保存之外立即写出,或导出当前纸页。失败时可见,不悄悄另存成新身份 |
| 字号增大、减小、恢复默认 | 只改玄霜写作的整体字号,不缩放宿主的 Web 界面 |
| 外观设置、关闭、全屏 | 打开写作设置;关闭当前写作窗口或标签,关闭前写出;进入或退出全屏 |
| 取消 / 退出当前层 | 先交给输入法取消组字;没有组字时关闭当前弹层;都没有时打开按需菜单 |

- 不支持的 RTF 属性操作不能绕过规范模型直接改 attributed text,例如任意字体面板、粘贴外来样式、与 Markdown 无关的对齐。下划线命令不会被偷换成删除线。
- Linux 用 Ctrl 作为应用命令的主修饰键,不占用桌面的 Super 绑定,全屏用独立按键切换。[已交付:Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md 表中每一项在 Linux 上是否逐一对齐,没有找到验收证据。[未定]

### 空选区输入样式

状态:[已交付:macOS] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md

- 空选区样式是当前编辑面的临时状态。第一次切换时参考插入位置已有的样式。粗体、斜体、删除线可以叠加。
- 只切换样式时,不改正文、revision 或行时间。
- 实际键入、输入法确认和可兼容的粘贴,在同一次内核事务中生成合法 Markdown。不能先插入文字,再追加一个独立的格式事务。
- 关闭某个样式时,正确拆分已有的格式范围,不改动后面未编辑的原文。一次撤销撤掉这次提交的全部内容。
- 以下动作清除临时样式:显式移动光标、普通范围选择、切页或交接编辑面、撤销或重做。输入法内部的临时选区不清除它。
- 提交的内容含换行时,第一个换行之前沿用临时样式,从换行起清除。普通空白保持原样,同时保留待输入样式,不硬造无效的强调标记。
- Markdown 边界无法合法表达时,优先保全原文。多行或未知块的粘贴保留自身语法,不强行包装。
- Linux 上是否同样交付,没有找到验收证据。[未定]

### Return 与缩进

状态:[已交付:macOS] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-11-sumi-platform-parity.md

- 换行写入普通 LF。首版不做列表自动续写。
- 显式换行写入两个尾随空格加 LF,即 Markdown 的硬换行。
- 两者都是单一、可撤销的事务。
- 缩进:给当前段落或所选逻辑段落增加一级缩进,每级两个空格 `(工程细则)`。
- 反缩进:去掉一级缩进。不足一级时只去掉已有的空格;没有缩进时不改内容。
- 普通段落不会因为反复缩进而意外变成不可编辑的代码块。列表保持合法的 Markdown 层级。选区通过锚点跟随。
- 普通正文里按缩进键不会跳出编辑器。
- 不支持的原文块保留源码,不强制重排。
- Linux 的显式换行映射已随 v6.1111.4 发布,但发布记录写明没有 Linux GTK 实机证据。[未定]

## 剪贴板

### 复制与剪切

状态:[已交付:macOS] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md

- 复制和剪切把选区导出为对应的 Markdown 文本,只写入通用纯文本类型。不写富文本样式、内部 YAML、page UUID、行时间或同步元数据。
- 粗体、斜体、链接、列表等受支持的格式保留 Markdown 语义。
- 部分选区导出有效的片段,不夹带未选中的正文。部分引用式链接带上所需的定义。
- 全选复制时输出 Markdown 正文原文。多段选择按文档顺序合并,不重复文字。未知原文片段按原始 Markdown 复制。
- 复制是只读动作。
- 剪切只有在剪贴板写入成功后才删除选中正文。写入失败时,选区和正文保持不变。删除走同一个本机可撤销事务。[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-11-sumi-platform-parity.md
- Linux 上 Markdown 复制输出的其余规则,没有找到逐项验收证据。[未定]

### 粘贴

状态:[已交付:macOS] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md

所有粘贴一律文本化,不导入外来的字体、字号、颜色或 RTF 排版。

- **来源优先级**:优先用明确的 Markdown 或纯文本。剪贴板同时有纯文本和 HTML/RTF 时,取纯文本。
- **合法 Markdown**:文本中的合法 Markdown 作为 Markdown 源插入,不转义成可见星号。
- **原样保留**:特殊字符、空行和制表符不吞掉,换行统一为 LF。
- **只有 HTML**:提取纯文本,保留可读的段落、列表、表格单元分隔、预格式文本和图像替代文字。不执行脚本,不请求远端资源。
- **只有 RTF**:提取文本,去掉字体、大小、颜色、附件和布局属性。
- **文件、URL、表格**:文件和 URL 粘贴成可读的路径、链接或名称文本,不作为附件导入。表格可以降为制表符分隔、逐行排列的文本。
- **只有图像,或无法提取文本**:不伪造识别结果,明确说明或插入可理解的文字占位,原剪贴板内容不丢。首版不做 OCR,也不上传文件。
- **一次事务**:一次粘贴是一个可撤销的本地事务,只新增本次写入的内容和时间,不继承剪贴板里的 page 身份或行身份。它与输入法、远端更新使用同一套选区锚点语义。
- **键盘与菜单**:普通粘贴的语义相同。
- **显式纯文本粘贴**:按字面插入,由内核保留字面字符。没有绕过清洗的“原样富文本插入”。
- **失败**:转换失败或超限时,原文和原剪贴板保持不变,可以重试,不会报告为已粘贴。
- Linux 上是否逐项对齐,没有找到验收证据。[未定]

## 输入法

### 输入法边界

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs

**组字内容不进 CRDT**

- 组字(预编辑、marked text)期间的内容只属于原生编辑面,不写入 CRDT,不保存,也不同步。
- 只有输入法确认提交的文字才形成本地事务。

**组字期间暂缓远端更新**

- 组字开始时,冻结该编辑面的 revision 和 source map,并锚定替换区。
- 远端更新可以先持久写入队列,但不应用到这个编辑面。
- 组字确认后,先按冻结基线生成本地事务并持久化,再按顺序合并远端队列,然后更新显示和选区。
- 队列有大小上限 `(工程细则)`。超限时先安全提交或取消组字,并保存恢复稿,再追平远端。
- 外观变化(字体、字号)也推迟到组字结束后再应用。

**打开面板前的受控交接**

- 用户主动打开设置、纸页列表或其他玄霜写作面板时,先把当前可见的组字内容按冻结基线提交为一次本地编辑。
- 提交成功后,才解除组字、清除输入法预编辑并隐藏正文。
- 提交失败时,保留文字、组字选区和可见的编辑器,提示重试,不丢输入。
- 后台隐藏、远端更新和切换操作仍受原有的组字防护,不能擅自提交组字。

**不强制系统输入法**

- 应用不能、也不尝试强制系统输入法的候选窗位置或配色。
- 不伪造光标位置来固定候选条。编辑器始终报告真实的文字和插入点几何。
- 候选区固定在底部、内嵌在正文中、去掉预编辑底色等能力,由配套输入法 Fcitx5 for Sumi 自己实现。编辑器只提供经过授权的主题与几何参数,不传送不必要的全文。
- 各平台如何对接,见 [platform/notemd-desktop.md](platform/notemd-desktop.md)。

### 打字音

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/sound.rs https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/main.ts

- 默认开启,可以独立关闭。
- 有两种音色:打字机(`typewriter`,默认)和低沉机械键(`thock`)。音效设置与外观偏好分开保存。
- 只在原生正文编辑器有焦点时发声,包括中文组字过程。设置面板里的输入框不发声。
- 不记录按键内容。
- 命令快捷键不当作正文打字,不发声。保存失败后被暂停的草稿也不发声。Shift、Option 等参与正常输入的修饰键保留修饰键反馈。
- 按普通键、空格、回车、删除和修饰键区分声音。只有部分音色带按键抬起声:`thock` 有抬起样本,`typewriter` 没有。共 12 个短 WAV,总计 133,584 字节,随插件提供 `(工程细则)`。
- macOS 需要“输入监控”权限。设置面板提供明确的授权入口和重试,状态里显示是否缺少权限。[已交付:macOS] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md
- 长按自动重复:macOS 不为自动重复发声;Linux 保留长按重复的声音。两端不一致,目标行为没有定下来。[未定]

### 输入法按键反馈

状态:[已交付:Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.zh-CN.md https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-11-sumi-ime-key-feedback.md

- 输入法尚未确认文字时,拼音组字一有变化就发声。重复刷新、确认后清空不额外补声。打字音开关继续有效。
- 宿主配合配套输入法模块,按真实按键发声。覆盖中文标点、空格或回车确认、删空、候选导航和数字选词。英文透传键去重。
- 这项能力需要同时更新宿主和配套输入法模块。
- macOS 通过“输入监控”取得真实按键,见上一节。
