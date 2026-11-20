# iOS 原型对齐设计

日期:2026-11-20。分支 `ios-m0-m1`(worktree `/Users/bruce/git/sumiwrite-ios`)。

## 1. 为什么做

用户在 Duo 上试了 M0/M1 版后说:「很多功能没实现,请保持和之前的原型操作方式对其。」随后定了方向:「包括我们调试过的代码细节,全部照搬」。

原型是「玄霜试做」,源码在本机 `~/git/sumiwrite-ios-spike/SumiSpike/`(不在版本管理里,结论见 `docs/spec/platform/ios.md` §8.1)。真机上 10 项手工测试都过了,其中很多细节是一点点调出来的。正式版要的是:操作方式和原型一模一样,底下换成正式的 Rust 内核。

## 2. 目标、不做、反目标

**目标**

- 原型的界面与操作方式全部搬进正式版:底部菜单条、纸页概览与废纸篓、设置页、提示条、隐藏状态栏、硬件键盘命令、两组内置字体。
- 原型调过的代码细节逐行照搬,见 §5 清单。
- 纸页的新建、顺序、移到废纸篓、恢复,一律走内核目录(`core/src/catalog.rs`),经 FFI 开放给 Swift。

**不做**

- 崩溃恢复的验证口径(强杀进程后正文不丢)仍属 M2,不在这次范围。
- 其余四组字体的按需下载(朝华、油茶、朱雀仿宋、Unifont),仍按 §7.4 待定。
- 同步、配对、导出:M3 及以后。

**反目标**(做出来也算失败)

- 在 Swift 里写纸页顺序、删除状态、摘要、修改时间的计算逻辑。这违反 AGENTS.md 第 4 条红线。
- 把正式版已经修好、原型却没有的地方改回原型写法。§6 逐条列出了这些地方。

## 3. 考虑过的做法

| 做法 | 取舍 | 结论 |
|---|---|---|
| A. 原型的界面和细节照搬,纸页走内核目录,经 FFI 开放 | 要动 FFI crate,可能还要动内核;纸页管理从 M2 提前 | **用户选定**(「全部照搬」回复的就是这个提议) |
| B. 原型的 PageStore 也照搬(每页一个 .md,外加 index.json) | 最快,但纸页逻辑写在 Swift 里,犯红线;以后同步也接不上 | 否 |
| C. 只搬界面,多页留到 M2 | 用户点名的「上一页、下一页、概览、废纸篓」做不出来 | 否 |

## 4. 架构

Swift 侧采用原型的结构,与 M1 已有的部分对接如下:

- **App 外壳(SwiftUI)**:照搬原型 `ContentView`,替换 M1 的 `EditorShell`。
  - 布局是 ZStack 背景加一个 VStack,VStack 里依次是编辑器宿主和底部菜单条,另有提示条、概览表单、设置表单。
  - `.statusBarHidden(true)`、`.persistentSystemOverlays(.hidden)`、`.preferredColorScheme`。
  - scenePhase 一旦不是 `.active` 就立即保存。
- **编辑面(UIKit)**:按原型 `EditorViewController` 的结构重写 M1 的 `EditorController`。
  - 原型的写入路径是 `store.save(text)`,这里换成 M1 的 `PageModel` + `PagePersistence` 管线。逐字增量照旧经内核提交,撤销照旧走内核。
  - M1 顶部状态栏里的 `menuButton` 和 SwiftUI `SettingsView` 删掉,由原型的菜单条和设置页取代。
- **纸页仓库(Swift 薄壳)**:新 `PageLibrary` 取代原型的 `PageStore`,对外接口与 `PageStore` 一致。
  - 发布 `pages`、`currentID`。
  - 提供 `live`、`trash`、`position`、`open`、`next`、`prev`、`newPage`、`moveToTrash`、`restore`。
  - 顺序、删除状态、摘要、修改时间全部取自 FFI 返回的列表,Swift 只做转发和发布。
  - 「当前页 ID」与各页光标锚点属于界面状态,存在 UserDefaults。光标的 key 改成按页区分:`sumi.selection.<pageId>`。
- **FFI(`apps/ios/ffi`)**:给 `CoreStore` 加以下接口,内部都调 `catalog::*`,每个调用一个事务。
  - `pages() -> [PageInfo]`:按目录顺序排列,含已删除页。
    - `PageInfo { id, deleted, summary, modifiedMs: Int64? }`。
    - `summary`:首个非空行去掉首尾空白后取前 40 个字符,算法照原型 `PageStore.summary`。
    - `modifiedMs`:取各行行时间中最大的那个,空页为 nil。
  - `createPage(after: String?) -> String`:在目录里登记新页,并完成首次落盘。
  - `setDeleted(id, deleted)`。
  - `open` 时执行 `catalog::initialize`,再把 `documents` 里有、目录里没有的页按 `page_id` 顺序依次接在末尾登记。这是已装在 Duo 上的 M1 单页数据的迁移路径。
  - 摘要、修改时间和迁移都写在 Rust 里,不进 Swift。

## 5. 照搬清单(原型调过的细节,逐条照搬)

出处都是 `~/git/sumiwrite-ios-spike/SumiSpike/` 下的文件,下文称原型。

### 5.1 光标(Editor.swift `SumiCursorView`)

- 实现成 `UITextCursorView`,通过 `UITextSelectionDisplayInteraction.cursorView` 装上;`viewDidLoad` 和 `viewDidAppear` 各装一次。
- `isBlinking = false`;`resetBlinkAnimation()` 留空,连续输入时不重启呼吸相位。
- 呼吸动画:`opacity` 从 1.0 到 0.25,时长 2 秒,`autoreverses`,无限重复,曲线 `easeInEaseOut`,`isRemovedOnCompletion = false`。在 `didMoveToWindow` 里挂上。
- `textView.tintColor = theme.foreground`。

### 5.2 正文视图(`SumiTextView`)

- **`pinnedY`**:`contentOffset` setter、`setContentOffset`、`scrollRectToVisible` 三处都钉在 `pinnedY` 上;只有用户在拖动、跟踪或减速时不钉。
- **`caretRect`**:
  - 宽 `min(3, max(2, pointSize/11))`,高 ascender − descender。
  - 空行修正:`lineSpacing > 0.5 && r.height >= lineHeight + spacing − 0.5` 时,框顶下移一个行距,框高减一个行距。
  - 竖直方向在 `min(boxH, lineHeight)` 内居中,再按 displayScale 取整。
- **方向键**:`pressesBegan` 里遇到上、下方向键就置 `arrowNav`。M1 的 `pressHandler` 钩子保留,RimeKit 以后要用。

### 5.3 编辑面控制器

- `prefersStatusBarHidden` 与 `prefersHomeIndicatorAutoHidden` 都返回 true。
- 容器顶边和左右贴 safeArea,底边贴 `keyboardLayoutGuide.topAnchor`,`followsUndockedKeyboard = true`。
- textView 的设置:
  - 透明背景,不显示滚动条,`alwaysBounceVertical`;
  - `lineFragmentPadding = 0`,`contentInsetAdjustmentBehavior = .never`;
  - 自动更正、拼写检查、智能引号、智能破折号、智能增删和行内预测全部关掉。
- 渐隐遮罩:竖直方向的 `CAGradientLayer`,作为容器 layer 的 mask。
  - `viewDidLayoutSubviews` 里先在关掉隐式动画的情况下设 frame,再依次算留白、`setFocusInsets`、`updateFade(0)`、`centerCaret(false)`。
- 段落行距:`lineSpacing = font.lineHeight × (行距 − 1)`。
- `applyPrefs` 依次做:
  - 设背景、tint、键盘外观、光标颜色、是否呼吸、是否打字音;
  - 整段 `setAttributes`,更新 `typingAttributes`,恢复选区;
  - 关掉聚焦打字时立即退出聚焦。
- 留白随字号缩放:代码与原型 `layoutMargins()` 一致,M1 已经相同,保持。
- **聚焦打字**:
  - **进入**:只看最近 2 秒内的输入,有 `primed` 或累计满 4 次就进入。进入后 0.2 秒内渐隐,并重设 10 秒空闲计时;计时到了用 1.2 秒恢复。
  - **按键分类**:在 `shouldChangeTextIn` 里分类;拼音预编辑时,如果替换成的是原拼音的前缀而且更短,算退格。同时记下 `editSelection` 和 `lastEditTime`。
  - **选区变化**:选区等于 `editSelection`,或离上次编辑不到 0.5 秒,都算「跟着输入走」。`inEdit`、`arrowNav`、「跟着输入走」三种情况重新居中;其余情况退出聚焦。
  - **拖动**:开始拖动就退出聚焦,inset 等滚动停稳后再复位。
  - **退出**:退出后置 `primed`。
  - **居中**:内边距上下各半屏。`centerCaret` 把光标中线放到视区中线,结果按像素取整;只有换了行、而且没开「减弱动态效果」时,才做 0.2 秒 easeOut 动画。
  - **渐隐**:遮罩分 96 段,距中线 d 处的不透明度 `0.55^(d/lh) × max(0, 1 − (d/(H/2))²)`,d ≤ lh/2 时为 1。开了「减弱动态效果」就不做动画。
- **硬件键盘**:
  - ⌘N 新建一页;⌘[ 上一页;⌘] 下一页;⇧⌘L 纸页列表;⌘, 设置;
  - ⌘= 放大字号(+2);⌘- 缩小字号(−2);⌘0 默认字号(22);Esc 菜单。
  - 组字期间 `canPerformAction` 对这些命令一律返回 false。
- `-SumiDemo` 启动参数照搬,只在模拟器自测时用。

### 5.4 外壳(ContentView.swift)

- **菜单条**:
  - 位置:编辑器下方单独一条,高 48,底部留 4。不叠在正文上,免得点击被 UITextView 的手势吞掉。
  - 展开时依次是:‹ 上一页、「序号 / 总数」(footnote、等宽数字、前景色 70% 不透明)、› 下一页、新建、总览、设置、移到废纸篓。
  - 末尾始终有「···」与「×」的切换按钮,切换动画 `.easeOut(0.15)`。
  - 按钮:SF Symbol 17 号 `.light`,点击区 44×44,`.contentShape(Rectangle())`,`.buttonStyle(.plain)`,带无障碍标签。
  - 胶囊底:前景色,展开时 10% 不透明,收起时 0%。
  - 整条不透明度:收起时 0.35;正在打字且收起时 0;展开时 1。不透明度变化用 `.easeOut(0.3)`。
  - 刚打过字时菜单自动收起;`typingRecently` 2.5 秒后复位。
- **切页守卫**:组字中切页会提示「请先完成输入」。可以切页时先保存,再执行切页,最后让编辑器重新获得焦点。
- **提示条**:footnote 字号胶囊,底色为前景色 12% 不透明,离底 64,显示 1.8 秒。
  - 移到废纸篓的提示:「已移到废纸篓,可在总览里恢复」。
- **概览(OverviewView)**:
  - 标题「纸页」,inline 样式,工具栏有「完成」。
  - 「继续书写」分区:点一下打开该页;左滑出现 destructive 的「移到废纸篓」。
  - 「废纸篓」分区(为空时不显示):点一下或左滑「恢复」均可恢复,图标 arrow.uturn.backward,蓝色。
  - 每行显示摘要(为空时显示灰色的「空白的一页」),单行;下面一行 caption 是修改时间(`.abbreviated` / `.shortened`);当前页带铅笔图标。
- **设置(AppearanceView)**:
  - 「主题」:inline 选择器,每项是 18pt 的圆,用背景色填充、前景色 3pt 描边。
  - 「字体」:inline 选择器,带页脚说明。
  - 「排版」:
    - 字号滑块 8–96,步长 1,标签「字号 N pt」;
    - 行距滑块 1–3,步长 0.1,标签「行距 x.x」;
    - 按钮「恢复默认字号与行距」,恢复为 22 / 1.6。
  - 「书写」:
    - 「光标」选项:平缓呼吸 / 常亮;
    - 开关:聚焦打字、打字音。
  - 两个表单都是 medium/large 两档高度,关闭后编辑器重新获得焦点。
- **主题**(Prefs.swift):

  | 主题 | 前景 | 背景 |
  |---|---|---|
  | 黑底白字 | ffffff | 000000 |
  | 黑底灰字 | b8b8b8 | 111111 |
  | 白底黑字 | 111111 | ffffff |
  | 米色深灰 | 44413c | f3ead7 |
  | 复古绿磷 CRT | 0ccc68 | 000000 |
  | 复古蓝磷 CRT | 7fb4ff | 000000 |

  除白底黑字和米色深灰外都是深色。
- **字体**:内置两组。
  - Sumi Plex:`IBMPlexMono-Light`,中文回退到 `IBMPlexSansSC-Light`。
  - Sumi WenKai:`LXGWWenKaiMonoLite-Regular`;取不到时回退到系统等宽 light。
  - 字体文件连同许可证从原型 `Resources/Fonts` 复制,经 `UIAppFonts` 注册。
- **默认值**:主题黑底灰字、字体 Plex、字号 22、行距 1.6;呼吸、聚焦打字、打字音全开。

### 5.5 纸页行为(原型 PageStore 的语义,改由内核目录实现)

- `live` 按目录顺序排列;`trash` 按修改时间倒序排列;`position` 是当前页在 `live` 里的「序号 / 总数」,序号从 1 起。
- **下一页**:在最后一页时新建一页。**上一页**:在第一页时什么都不做。
- **新建**:插在当前页之后,即 `createPage(after: current)`。
- **移到废纸篓**:如果移走的是当前页,依次尝试:切到后一页,没有就切到前一页,都没有就新建一页。
- **恢复**:页面回到原位置。删除不改动目录里的锚点,内核已保证这一点。
- **空白页**:按 01 §3.2,新建即登记,立即 `createPage`;空白页不生成文件,但目录里有记录,概览里会出现这张空白页。

## 6. 冲突裁定:原型与正式版不一致处

| 项目 | 原型 | 正式版 | 裁定 |
|---|---|---|---|
| 写入与撤销 | 整段文本存文件,用系统撤销 | 内核增量,内核撤销 | 保留正式版(红线) |
| 换行 | 不处理 | CR、CRLF 统一成 LF | 保留正式版 |
| 编辑差异 | 不涉及 | 以光标为锚点算差异 | 保留正式版 |
| 打字音 | `playback` 类别,不受静音键影响 | `ambient` 类别,受静音键影响;前台恢复时重启;媒体服务重置后重建;静音时停转 | 保留正式版。spec §3.4 已定 M1 改为 ambient |
| 保存失败 | 不处理 | 保存失败后只读 | 保留正式版 |
| 打开应用 | 光标放到文末 | spec §1 要求恢复上次的纸页和光标 | 启动时按 spec 恢复;用上一页、下一页或概览切页时,照原型把光标放到文末 |
| Writing Tools | 未设置 | `.limited` | 保留正式版 |
| 部署目标 | iOS 18.0 | iOS 17.0 | 保留 17.0。用到的 API 在 17 上都有;如果编译发现缺了,用 `#available` 包起来 |
| 系统光标隐藏 | 换 `cursorView` | 自绘一个覆盖层,系统光标改透明 | 用原型的 `cursorView`。原型在真机上调过,选区手柄也能保留原色 |
| 外观入口 | 菜单条加 AppearanceView | 顶栏按钮加 SettingsView | 用原型的 |

## 7. 规范的改动(先改规范,再改实现)

- `docs/spec/platform/ios.md` §1「外观」:说明第一阶段内置 Plex、WenKai 两组字体,其余四组仍按需下载。注明是用户决定,2026-11-20,「全部照搬」。
- `docs/spec/platform/ios.md` §4.1:M1 增加纸页管理(概览、新建、上一页、下一页、废纸篓、恢复),M2 只保留崩溃恢复和与之相关的存储加固。
- `docs/spec/platform/ios.md` §3.2:补上硬件键盘命令表。
- 每改一节都更新状态行,跑 `bash docs/check.sh`。

## 8. 验证

- FFI 测试(`cd apps/ios/ffi && cargo +1.99.0 test`)增加以下用例:
  - 目录顺序;
  - 在中间插入;
  - 删除与恢复后位置不变;
  - 摘要取首个非空行、最多 40 字;
  - 修改时间取最大行时间;
  - 旧单页数据的迁移;
  - 重开后状态仍在。
- 如果动到 `core/`,先跑内核 README「Verification」段列出的命令。
- Swift 单元测试(`bash apps/ios/scripts/test-sim.sh`)覆盖:
  - `PageLibrary` 的下一页在末页时新建、上一页在首页时不动、移到废纸篓时的目标顺序、空白页不登记;
  - `caretRect` 的宽高与空行修正;
  - 渐隐的不透明度公式;
  - 快捷键在组字期间禁用。
- `apps/ios/README.md` 手工验收清单增加原型的操作项,装到 Duo 上由用户验收。

## 9. 交给实现者的部分

- 文件怎么拆:原型是 ContentView、Editor、Prefs、PageStore、TypingSound 五个文件,正式版目录沿用 M1 的 App/Appearance/Core/Editor/Sound。
- 把 M1 的 `EditorPrefs`/`Theme` 迁到原型的 `Prefs` 语义上。旧的 UserDefaults 键能沿用就沿用。
- 判断现有测试哪些随旧界面一起删掉、哪些改写。
