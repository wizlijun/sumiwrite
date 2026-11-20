# 共享内嵌输入法 RimeKit 设计

状态:用户认可「请自主完成功能」「我希望看到完整的内嵌输入体验的版本」(2026-11-20),按下面的修订执行。

## 0. 修订(2026-11-20,写在原稿之前,冲突时以这里为准)

原稿写于正式 iOS 应用之前。现在 Sumi Write(`apps/ios/`,M0/M1)已经装在 Duo 上,用户要的是在它上面看到完整的内嵌输入体验。所以:

1. **宿主改为 Sumi Write**:§5.3 里「试做编辑器」一律换成 `apps/ios/` 的正式编辑面(`SumiTextView` / `EditorController`)。不再动 `~/git/sumiwrite-ios-spike`。§2「不做」里的「玄霜写作正式 `apps/ios/`」作废。
2. **rapp 改为引用 RimeKit(§5.2)推迟到下一轮**【我定的】:它不影响 Sumi Write 的体验;rapp 的 main 合并即发版,改动要回归和 rapp-49 交接,和这一轮绑在一起只会拖慢用户试用。这一轮 RimeKit 从 rapp 搬代码,保持逐行一致,rapp 一侧暂时还是原样的那一份——下一轮切换过去后才算「一处」。
3. **引用方式**【我定的】:RimeKit 在推到 GitHub 之前只在本机 `~/git/rime-kit`(本地 git 仓库,不推送)。`apps/ios/project.yml` 用 XcodeGen 本地包引用 `../../../rime-kit`(仓库在 `~/git/` 下的任何工作树都能找到它)。建 GitHub 仓库之后改为子模块。缺 RimeKit 时构建失败并提示去哪拿,README 写明。
4. **词库只用内置雾凇**【我定的】:「我的目录」(文件共享、用户 `default.yaml`)这一轮不做,`RimeInput` 的接口保留 `dictionary` 参数。
5. **开关**:正式编辑面总是启用,只有候选行上的「内 / 系」;「内 / 系」的选择记在 `UserDefaults`,重开 app 保留【我定的】。外观面板里不加开关。
6. **组字显示**:先用 `setMarkedText`(编辑面已有的组字路径:组字不进内核,上屏时整段提交),模拟器端到端验证;不行再退回叠层。


## 1. 为什么

用户的话(2026-11-20):

- 「请阅读 ~/git/rapp 中内嵌输入法的做法,把整个实现过程都搬到这个项目中。让 ios ipados 的外置键盘输入可以有我们需要的输入法效果。」
- 「请保持是实现代码尽量同步和一致,持续把这一块的能力对齐,将来放在更多的 app 中。」
- 问「不能直接在原生编辑器上挂上吗?」之后,认可了「拆共享包 → 挂到试做编辑器装 Duo → 第 4 期正式编辑面复用」的做法(「可以,按你说的来」)。

背景:

- rapp 0.15.0 已经发布内嵌 Rime(`~/git/rapp/gui/packages/rapp_rime/`,设计 `~/git/rapp/docs/superpowers/specs/2026-11-20-rapp-ios-rime-ime-design.md`)。iOS 上第三方输入法是键盘扩展,接实体键盘后按键不经过它们;rapp 的做法是把 librime 放进 app,在 `pressesBegan` 里把按键交给引擎,候选固定在文字下一行。用户在 Duo 上用过:「我看效果很好」。
- 玄霜写作还没有正式的 iOS 应用(第 4 期)。能用的原生编辑器是界面试做 `~/git/sumiwrite-ios-spike`(UIKit `UITextView` + TextKit 2,已接管 `pressesBegan`,iPhone 真机跑通,未进版本管理),见 [ios.md §8.1](../../spec/platform/ios.md#81-界面试做)。
- rapp 插件里和 Flutter 绑定的只有两处:`RappRimePlugin` 经 `FlutterMethodChannel` 收发,以及 Dart 画的候选行。引擎封装 `RimeEngine`、按键策略 `RappRimeKeys`(键码换算、连发、补发、Shift 组合、加载时机)和按键入口 `handlePress(_:began:) -> Bool` 都是 UIKit / 纯 Swift。

## 2. 目标、不做的、不能出现的

目标:

1. **一份共享包 RimeKit**:引擎封装、按键策略、按键控制器、UIKit 候选行、下载脚本、词库打包,全在一个独立仓库里。所有 app 引用同一份,升级 librime、雾凇或修按键问题只改这里。
2. **rapp 改为引用 RimeKit**:`rapp_rime` 变成薄的 Flutter 适配层(通道收发 + Dart 一侧不变)。用户在 rapp 里感觉不到任何变化。
3. **玄霜写作试做编辑器挂上 RimeKit**,装到 Duo 上:接实体键盘时,组字在光标处带下划线,候选固定在当前行下一行,「中 / 英」标记和「内 / 系」小按钮与 rapp 一致。
4. 第 4 期正式的 iOS 编辑面直接引用 RimeKit,不再另写。

不做(这一轮):

- 玄霜写作正式 `apps/ios/`(第 4 期再开)、设置页、每页开关。试做里只有候选行上的「内 / 系」,默认「内」。
- 自己的软键盘、键盘扩展、macOS / Linux 的内置输入法。
- 改 rapp 的 Dart 一侧行为、设置项、通道消息格式。
- 公开分发(TestFlight 外部、App Store)。

不能出现:

- rapp 的任何行为变化:按键、连发、补发、type-to-compose、设置、状态行、构建(`scripts/build-ios.sh`)都和 0.15.0 一样。
- 同一段按键逻辑在两处各有一份。
- 没接实体键盘时,试做编辑器的行为和现在不同(系统软键盘、系统输入法照旧)。
- 引擎部署期间卡住打字:就绪前按键照常交给系统输入法。

## 3. 约束

- 引擎包、词库版本和下载校验沿用 rapp 现状:LibrimeKit-iOS v0.2.2(librime 1.16.1)、雾凇 927e1cf、OpenCC 表取自同版本 rime-deps;`fetch.sh` 核对 sha256,下载物和词库都不进仓库。
- 最低 iOS 17(rapp 插件现状);试做编辑器是 iOS 18,不冲突。
- **许可证与仓库(用户定,2026-11-20)**:RimeKit 是公开仓库,放在与 rapp 同一个 GitHub 账号下,名为 `rime-kit`,代码用 **GPL-3.0**(与 rapp 相同)。雾凇也是 GPL-3.0,不进仓库,构建时下载。rapp 已知并接受(rapp 设计 §3)。玄霜写作(Apache-2.0)iOS 第一阶段只自用、不公开发行(设计 §2 **[用户定]**),所以眼下没问题;玄霜写作 iOS 公开发行前,RimeKit 代码和词库的 GPL 要一起处理。RimeKit 的 README 列出各库和数据的许可证。
- **公开仓库是交接 rapp 的前提**:rapp 是公开仓库,合并即发版,子模块必须指向能拉取的地址。所以 rapp 分支在 RimeKit 推到 GitHub 之前只留在本地;建仓库和推送在真机检查通过后、经用户同意再做。
- **rapp 的规矩**:rapp 的 main 由 rapp-49 合并,合并即自动发版。rapp 的改动走分支,真机检查过了才交给 rapp-49。
- **玄霜写作的规矩**:规范 [ios.md](../../spec/platform/ios.md)「不做」里的「自定义输入法或键盘扩展」(当时是 [我的判断])被这次的用户决定推翻,先改规范(AGENTS.md 第 1 条)。内嵌引擎不是键盘扩展,系统输入法照样可用。
- **真机安装要开发签名**。本会话不自行签名;装 Duo 那一步由用户执行构建安装命令,或者用户当场明确同意后由我执行。
- 推送、建 GitHub 仓库都要用户同意;在那之前 RimeKit 只在本机。

## 4. 做法

| 做法 | 取舍 |
|---|---|
| **A 独立仓库 RimeKit,各 app 以 git 子模块引用(推荐,用户认可「按你说的来」)** | 一份代码;每个 app 钉在 RimeKit 的某个提交上,升级是一次子模块更新,可以单独回归。`fetch.sh` 在子模块目录里跑,`binaryTarget(path:)` 和 `.copy("RimeData")` 原样可用。代价是多一个仓库,clone 要带 `--recurse-submodules` |
| B 以 SwiftPM 远端依赖(git URL + tag)引用 | 最“标准”,但 RimeKit 的十个 xcframework 和词库都是下载后 git 忽略的,SwiftPM 拉下来的远端包里没有它们;LibrimeKit 的发布物是 tgz 不是 SwiftPM 认的 zip,`binaryTarget(url:)` 用不了。要先自己重新打包发布二进制,这一轮代价太大 |
| C 各 app 拷一份,靠脚本同步 | 最省事,但正是「两处各一份」,违背「同步和一致」 |

## 5. 设计

### 5.1 RimeKit 仓库

本机 `~/git/rime-kit`,从 rapp `gui/packages/rapp_rime/ios/rapp_rime/` 和 `scripts/fetch.sh` 拆出来。【我定的】不保留 rapp 的提交历史,首个提交说明来源(rapp 提交号和路径)。

```
rime-kit/
  README.md          它是什么、怎么接入、怎么升级 librime 和雾凇、版本和许可证(从 rapp_rime README 搬)
  Package.swift      targets:CRime(头文件)、RimeKeys(纯 Swift 按键策略)、RimeKit(引擎 + 控制器)、RimeKitUI(UIKit 候选行)
  Sources/...
  Tests/RimeKeysTests  现有按键测试原样搬
  scripts/fetch.sh   下载、核对、展开到 git 忽略的 Frameworks/、Sources/CRime/include/、Sources/RimeKit/RimeData/
```

- `RimeKeys` 照搬 `RappRimeKeys`(`RimeKeyMap`、`PressLedger`、`RepeatPolicy`、`ReplayPolicy`、`ChordPolicy`、`LoadPolicy`),和测试一起;保留「只编按键部分、在 macOS 上跑测试」的开关(现在的 `RAPP_RIME_KEYS_ONLY`,改名 `RIME_KIT_KEYS_ONLY`)。
- `RimeKit` 里有两样:
  - `RimeEngine`:照搬。用户目录的位置改为由宿主传入(rapp 传现在的 `Documents/Rime`,行为不变)。
  - `RimeInput`:把 `RappRimePlugin` 里除通道以外的全部逻辑原样搬进来(开关、加载时机、`handlePress`、`replay`、连发、补发、Shift 组合、键盘接入与断开、进后台上屏)。对外是 Swift 方法 + 两个回调:
    - 方法:`configure(enabled:dictionary:)`、`setActive(_:)`、`handlePress(_:began:) -> Bool`、`replay(hid:characters:modifiers:) -> Bool`、`select(_:)`、`page(next:)`、`flush()`、`interrupt()`、`clear()`、`redeploy()`、`userFolder`、`version`、`keyboardAttached`。
    - 回调:`onUpdate(RimeUpdate)`、`onStatus(RimeStatus)`。`RimeUpdate` 是有类型的结构(上屏文字、组字和光标、候选行、高亮、能否翻页、中英、要删的字数),内容与现在 `RimeEngine.update` 的字典一一对应;`RimeStatus` 是状态、错误信息、是否接着实体键盘。
- `RimeKitUI`:UIKit 宿主用的两样,rapp 不用这个 target(它的候选行和宿主逻辑在 Dart),以后的 UIKit 宿主都用它。
  - `RimeCandidateBar`:候选行,照 rapp 的候选行画(序号、候选、高亮、‹ ›、右端「中 / 英」标记和「内 / 系」小按钮,部署中显示「部署中…」),点候选、翻页、点小按钮经回调交还宿主。
  - `RimeTextViewAdapter`【我定的】:把 `RimeInput` 接到一个 `UITextView` 上。rapp 里这一半在 Dart 的 `RappRime` / 编辑器里,UIKit 宿主由它统一承担,第 4 期不再另写:
    - 「启用」的判定:宿主开关、「内」、接着实体键盘同时成立;
    - 把 `RimeUpdate` 落到文字上:上屏、组字(见 §5.3)、删字;
    - 上屏规则:失去焦点、宿主要切换内容前(宿主调 `flush()`)、进后台时按原文上屏;点「系」时清掉组字、不上屏;
    - 按住 Shift 或 Control 时点了屏幕,发 `interrupt`(`ChordPolicy`),免得抬起 Shift 误切中英;
    - 摆放候选行(见 §5.3)。
  - rapp 的 Dart 一侧和 `RimeTextViewAdapter` 各有一份「宿主怎样用引擎」的规则,这是两种界面框架各一层薄适配,不是按键逻辑本身;按键逻辑只在 `RimeKeys` / `RimeInput` 一处。【我定的】RimeKit README 列出这几条规则,改规则时两边一起改。

### 5.2 rapp 一侧

在 rapp 的分支上(【我定的】`feat/rime-kit`,worktree 里做):

- `gui/packages/rapp_rime/ios/rapp_rime/` 里的源码、测试、`Frameworks/`、`RimeData` 去掉,改为 git 子模块 `gui/packages/rapp_rime/rime-kit`(或 rapp 根下 `vendor/rime-kit`,留给执行的人)。插件的 `Package.swift` 按路径依赖子模块里的 `RimeKit`。
- `RappRimePlugin` 只剩:通道方法 → `RimeInput` 方法;`onUpdate` / `onStatus` → 原样的通道消息(键名、取值和现在逐字段相同)。`SessionPlugin` 里调 `RappRimePlugin.shared?.handlePress` / `replay` 的地方不变。
- `scripts/fetch.sh` 改为调用子模块里的那份;`scripts/build-ios.sh` 照旧先跑它。README 指向 RimeKit。
- Dart 一侧(`lib/`、`rime_glue.dart`、设置)不动。
- 回归:按键测试(macOS 上 `swift test`)、`flutter test`、`cargo test --workspace`、macOS 构建、iOS 模拟器构建、`tools/sim/sim.sh` 的 `builtin` `repeat` `compose` 三个场景截图与 0.15.0 一致;再在 Duo 上过一遍 rapp 设计 §7 的 1、7、8、11、12 条。全部通过才交给 rapp-49。

### 5.3 玄霜写作试做编辑器

`~/git/sumiwrite-ios-spike` 本身不进版本管理(试做,用完即弃);RimeKit 以本机路径依赖接入。【我定的】在它目录里 `git init` 一个本地仓库只为记录这次改动,不推送。

- 试做里只写接线:建一个 `RimeTextViewAdapter` 挂到 `SumiTextView` 上。
- 按键:`SumiTextView` 的 `pressesBegan` / `pressesEnded` / `pressesCancelled` 先交给适配器(内部调 `RimeInput.handlePress`),吃掉的不再调 `super`。现有的方向键回调照旧在前面。
- 组字:【我定的】适配器用 `UITextView.setMarkedText(_:selectedRange:)` 显示组字,上屏时用 `insertText` 替换掉标记文字。有 `markedTextRange` 时不交给内核(ios.md §2.2 的判定)照样成立。如果真机上系统对标记文字有干扰,退回 rapp 的办法:组字不进文字,只在光标处叠一层带下划线的显示。
- 组字中切页【我定的】:内置输入法的组字可以由我们上屏,所以切页(按钮、⌘[ / ⌘])先调适配器 `flush()`,按原文上屏后照常切页;`canSwitch` / `canPerformAction` 改为「系统输入法在组字时拦住,内置输入法的组字先上屏再放行」。系统输入法组字时照旧提示「请先完成输入」。
- 候选行(用户定,2026-11-20):**盖住下一行**。`RimeCandidateBar` 带不透明底色,叠在光标所在行的下一行上,从正文左缘开始,打字时不随光标横移;那一行正文被挡住。接着实体键盘时一直占这一行,不组字时只有「中 / 英」和「内 / 系」。【我定的】细节:
  - 放在渐隐遮罩外面,不被渐隐;
  - 聚焦打字模式下当前行居中,候选行位置因此固定;不在聚焦打字模式时,候选行跟着光标所在行上下移动(换行时移动,同一行里打字不动);
  - 光标所在行已是视区最后一行时,先把正文滚上去一行,让候选行留在视区里。
- 开关:试做里总是启用,只有候选行上的「内 / 系」;点「系」后按键交给系统输入法。不做设置页。
- 「我的目录」:试做的 Info.plist 打开文件共享,「文件」→ 试做 app → `Rime` 里放了 `default.yaml` 就用它,规则同 rapp。
- 失去焦点、切页、进后台时,组字按原文上屏(与 rapp §6.3 同一条规则,由适配器执行)。
- 打字音:引擎吃掉的按键照样发声(按键种类按 `RimeUpdate` 判断:上屏算普通键,空格选词算空格),【留给执行的人】细节。

### 5.4 玄霜写作规范

在 sumiwrite 仓库(单独一个小分支,只改文档):

- [ios.md](../../spec/platform/ios.md)「不做」里删掉「自定义输入法」,保留「键盘扩展」;新增一节「实体键盘的内嵌输入法」:用 RimeKit,规则与 rapp 一致,候选行盖住下一行,状态 `[计划:iOS]`,试做结果写进 §8。
- ios.md 里「有组字时不切页」的写法改为:系统输入法组字时拦住;内置输入法的组字先按原文上屏再切页。
- [later.md §6.1](../../spec/platform/later.md) 同步一句。
- `docs/check.sh` 输出 OK。

## 6. 验收

- RimeKit:`RIME_KIT_KEYS_ONLY=1 swift test` 全过;`fetch.sh` 在干净目录下跑通;iOS 模拟器上能编出 `RimeKit` 和 `RimeKitUI`。
- rapp:§5.2 的回归全部照过,行为与 0.15.0 一致。
- 试做编辑器,Duo 真机(用户在场):
  1. 接实体键盘,系统输入源是简体拼音或英文时,打拼音都由内置输入法接管,没有系统候选条。
  2. 组字在光标处带下划线;候选在下一行,打字时不横移。
  3. 空格、数字选词;‹ › 翻页;点候选上屏。
  4. Shift 切中英,标记跟着变。
  5. 按住退格、按住字母连发;快打长句不丢键。
  6. 点「系」切回系统输入法,再点「内」切回来,两边都对。
  7. 拔掉实体键盘,软键盘和系统输入法照旧。
  8. 内置输入法组字中切页或切到后台,组字按原文上屏,不丢;切到「系」用系统拼音组字时切页,照旧提示「请先完成输入」。
  9. 从正文中间续写:候选行盖住下一行、不被渐隐;光标在视区最后一行时正文先上滚一行,候选行留在视区里。
  10. 强杀重开,正文完整(试做原有的保存不受影响)。

## 7. 留给执行的人

- 子模块放在 rapp 的哪个路径;`Package.swift` 怎么按路径引用子模块里的包,同时不破坏 macOS 构建(rapp 的 macOS 构建现在也要先跑 fetch,见 rapp 已知坑)。
- `RimeUpdate` 的字段名;Flutter 适配层把它还原成字典时逐字段对照现有 Dart 测试。
- `RimeCandidateBar` 的具体画法(字体、间距随宿主主题传入)。
- 试做编辑器里打字音和引擎的配合细节。
- 每一步的测试怎么组织。

## 8. 我定的,一览

- 共享方式用 git 子模块(§4 A)。仓库名 `rime-kit`,公开、GPL-3.0 是用户定的;推送前先只在本机。
- 不保留 rapp 的提交历史(§5.1)。
- 用户目录由宿主传入,rapp 传现在的位置(§5.1)。
- 候选行和 `UITextView` 接线都做进 UIKit target `RimeKitUI`,rapp 暂不用(§5.1)。
- rapp Dart 一侧与 `RimeTextViewAdapter` 各一层宿主规则,README 列出、两边一起改(§5.1)。
- 内置输入法组字时切页:先上屏再切;系统输入法组字时照旧拦住(§5.3)。
- 候选行盖住下一行是用户定的;放在渐隐遮罩外、非聚焦模式跟着行上下移、视区底部时先滚一行,是我定的(§5.3)。
- rapp 分支名 `feat/rime-kit`,worktree 里做,回归与真机检查过了才交给 rapp-49(§5.2)。
- 试做编辑器用 `setMarkedText` 显示组字,不行再退回叠层显示(§5.3)。
- 试做里总是启用,只有「内 / 系」,不做设置页(§5.3)。
- 试做目录里 `git init` 本地仓库记录改动,不推送(§5.3)。
- 玄霜写作规范的改动走单独的文档小分支(§5.4)。
- 装 Duo 需要开发签名:由用户执行,或用户当场同意后我执行(§3)。

## 9. 顺序

1. 建 RimeKit 仓库,搬代码,按键测试和模拟器构建通过。
2. rapp 分支改为引用 RimeKit,回归通过(真机部分可以和第 3 步一起在 Duo 上做)。
3. 试做编辑器接 RimeKit,模拟器上跑通,再装 Duo 做第 6 节的真机检查。
4. 玄霜写作规范改动。
5. 真机检查都过了:经用户同意,在 GitHub 建公开仓库 `rime-kit` 并推送;rapp 分支的子模块指向它之后,再交给 rapp-49。
