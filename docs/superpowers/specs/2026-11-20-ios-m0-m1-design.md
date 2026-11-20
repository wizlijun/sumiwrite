# iOS 第一步:M0 内核过 FFI 与 M1 编辑面 设计

状态:已认可(2026-11-20)。

## 1. 为什么

用户的话(2026-11-20):

- 「sumiwrite 先发布一个 ios 客户端到我 duo 上。」
- 在「装试做 / 合一新试做 / 正式开工」中选了「正式开工 iOS 版」;签名与安装选「你来跑」,即由用户自己执行。
- 得知 [ios.md §6.1](../../spec/platform/ios.md#61-第-3-期完成) 要求第 3 期(`session/` 下沉)完成后才能开工、而 M0/M1 只用到 `core/` 之后,选了「按你推荐,M0/M1 先行」。

所以这一轮要做的是:在本仓库正式建 iOS 应用,先完成 M0 与 M1,让用户能在自己的 iPhone(Duo)上用真内核写字。M2 起仍按原规范等第 3 期。

背景(已读过的事实):

- 本仓库还没有 iOS 代码。本机有两个一次性试做,均未进版本管理:界面试做 `~/git/sumiwrite-ios-spike`(纯 Swift 编辑面,约 1.2k 行)与 M0 内核试做 `~/git/sumiwrite-m0-spike`(`write-core` 经 UniFFI,约 0.8k 行)。结论见 [ios.md §8](../../spec/platform/ios.md#8-试做记录)。
- `core/` 已是本仓库的内核(0.2.0)。互操作夹具在 `core/tests/fixtures/yrs-v1.json`,Yjs 夹具在 `sync/tests/yjs-v1.json`。
- 工具链 `1.99.0` 目前只装了 `aarch64-apple-darwin`,iOS 两个目标还要装。
- 本仓库没有 CI。本机已装 XcodeGen。
- 共享内嵌输入法 RimeKit 有单独的设计(`2026-11-20-rime-kit-design.md`,待认可)。它原定挂到界面试做上;正式编辑面出来后,改挂到本设计的编辑面上更合理。这件事在那份设计里改,不在本设计范围内。

## 2. 目标、不做的、不能出现的

目标:

1. **M0**:`core/` 编成 XCFramework,经 UniFFI 给 Swift 用。Swift 侧跑互操作夹具,结果与 Rust 一致(规范 §4.1 的验证口径)。
2. **M1**:一页纸的正式编辑面。TextKit 2、自绘光标、六种主题、字号与行距、中文组字、撤销与重做,每次上屏都经内核成为一次事务。
3. 用户能用一条命令把应用签名并装到自己的设备上。
4. 规范先改,再实现:放宽 §6.1,并把 M0/M1 定下的工程答案写回 ios.md。

不做(本轮):

- 多页、纸页概览、废纸篓,以及崩溃恢复的保证(M2)。
- 同步、配对、钥匙串(M3)。
- iPad 打磨,以及撤销以外的硬件键盘快捷键(M4);TestFlight(M5)。
- 导出、按需下载字体(05-fonts,§7.4 未定)。M1 只用系统字体。
- 挂接 RimeKit(见 §1 背景)。
- CI 流水线。

不能出现的:

- Swift 里出现任何 CRDT、行时间、合并或恢复逻辑(AGENTS.md 红线)。FFI 层只做类型转换和加锁。
- 编辑面显示的正文与内核正文悄悄分叉。内核拒绝一次编辑时,必须以内核为准重置编辑面。
- 正常退到后台或关闭应用后,正文丢失。
- 改动 note.md,或在仓库里写入 Bundle ID、团队 ID 等发行信息(AGENTS.md 第 5 条)。

## 3. 约束

- 技术栈与分层按 [ADR 0010](../../adr/0010-ios-uikit-textkit2-uniffi.md):UIKit `UITextView` + TextKit 2,SwiftUI 外壳,UniFFI。最低系统 iOS 17 / iPadOS 17。
- Rust 工具链钉在 1.99.0,与其他模块一致。
- 编辑事务的形状按 [ios.md §2.2](../../spec/platform/ios.md#22-编辑事务的形状):有标记文本(组字中)时不交给内核;按字素求差异,换算成 UTF-16 范围,带修订号调用内核替换。
- 产品规则按 [04-editing-experience](../../spec/04-editing-experience.md):主题色值、光标外形与动态、聚焦打字、打字音。界面试做踩过的坑按 [ios.md §3.3](../../spec/platform/ios.md#33-编辑面的已知坑) 的解法做。
- 文档用简体中文,提交信息用英文祈使句。

## 4. 做法

前一轮已经比较过四种做法:装界面试做、装 M0 试做、两者合一的新试做、正式开工。用户选了正式开工。正式开工本身又有两条路:

- **严格等第 3 期**:符合现行 §6.1,但第 3 期还没立计划,而且要改的正是归档目录任务 6、7 正在改的宿主文件,最早也要等归档目录合并之后。Duo 上很久装不上东西。
- **M0/M1 先行**(用户选的):M0 与 M1 只用到 `core/`,先在仓库里正式做;M2 起等第 3 期。代价是 M1 的应用没有输入日志和恢复保证,只适合用户自己试写。

试做代码可以参考,但不直接搬进仓库:正式代码按本设计和规范重写。可以照抄的是已验证过的解法,例如 §3.3 的滚动锁、空行光标、轮换播放节点。

## 5. 设计

### 5.1 目录与构建

```
apps/ios/
  README.md                 作用、构建、Verification 段、签名引用
  project.yml               XcodeGen 工程描述(生成的 .xcodeproj 不进仓库)
  Signing.example.xcconfig  签名占位,复制为 Signing.local.xcconfig(git 忽略)后填写
  ffi/                      Rust crate sumi-ios-ffi:core/ 的 UniFFI 包装
    src/lib.rs
    src/bin/uniffi-bindgen.rs
    src/bin/golden.rs       用同一份内核生成夹具比对基准
  scripts/
    build-core.sh           交叉编译、打 XCFramework、生成 Swift 绑定、复制夹具与基准
    install-device.sh       用户执行:签名构建并安装到指定设备
  SumiWrite/                应用源码(SwiftUI 外壳、UIKit 编辑面、薄适配层)
  SumiWriteTests/           XCTest:M0 夹具比对、M1 差异换算等
```

- **签名**(我定的):`project.yml` 从 `Signing.local.xcconfig` 读取 `DEVELOPMENT_TEAM` 与 `PRODUCT_BUNDLE_IDENTIFIER`。这个文件被 git 忽略;仓库里只有占位模板,README 写明去哪里填。模拟器构建与测试不需要它。
- **工具链**:`build-core.sh` 用 `cargo +1.99.0`,目标为 `aarch64-apple-ios` 与 `aarch64-apple-ios-sim`,不含模拟器 x86_64;并设置 `IPHONEOS_DEPLOYMENT_TARGET=17.0`,与应用一致。README 写明一次性安装目标的命令。这回答 §7.7。
- **安装**:`install-device.sh <设备名或 UDID>` 用 `xcodebuild -allowProvisioningUpdates` 构建,再用 `xcrun devicectl device install app` 安装。由用户执行;agent 只跑模拟器。

### 5.2 FFI 层(M0)

- 用 UniFFI `=0.32.2` 过程宏,不写 UDL。文档与存储各包成一个对象,内部加互斥锁。
- 全部同步调用。错误映射成 Swift 枚举,至少区分修订过期、偏移非法(切开字素)、容量、存储错误。
- 暴露的面只覆盖 M0、M1 要用的内核能力:建文档或从库打开、带修订号的 UTF-16 替换、正文与修订号、按行快照(行 ID、首写与末写时间、时间来源)、撤销与重做、合并更新、库的写入与检查点。
- 这些回答 §7.1 中只涉及 `core` 的部分;回调与线程归属留给 `session/`。

### 5.3 M0 验收:XCTest 夹具比对

- `build-core.sh` 把 `core/tests/fixtures/yrs-v1.json`、`sync/tests/yjs-v1.json` 复制进测试包。`golden` 用同一份内核生成两样东西:一份「桌面写的库」(检查点加其后的增量),一份比对基准。比对基准是按与 Swift 完全相同的步骤跑一遍夹具后得到的完整快照。
- XCTest 在模拟器上跑,覆盖 M0 试做的自检项:
  - 内核加载;
  - Rust 夹具三种合并方式;
  - Yjs 夹具;
  - 读桌面写的库;
  - iOS 写库并重开;
  - 两种错误分别可捕获。
- 比对逐字段进行,包括行 ID、首写与末写时间、时间来源。期望值都来自基准文件,Swift 不复述任何期望值。这回答 §7.6。
- 性能测量不进自动测试,留作 README 里的手工项。

### 5.4 M1 编辑面

- **显示什么**:与桌面一样显示富文本视图,不显示 Markdown 源码。按 [`core/README.md`](../../../core/README.md)「Host integration」第 3 条,用 `SourceMap::new(body, revision)` 得到可见文本与样式段,编辑面显示可见文本并按样式段上样式(标题、粗体、斜体、删除线、引用、列表、链接,见 [02 §1.2](../../spec/02-markdown-and-line-time.md#12-富文本视图支持的语法))。YAML 头与各类 ID 不显示;受保护的块(02 §1.3)原样显示,不能就地改写。直接键入的 `#`、`*` 等字符由内核按字面转义,与桌面一致([04「粘贴」](../../spec/04-editing-experience.md#粘贴))。粘贴纯文本时按 04 走 `SourceMap::apply_markdown_paste`,合法 Markdown 作为源插入。源码视图、格式命令(⌘B 等)、富文本(带样式)粘贴的换算、复制时导出 Markdown 不在 M1;复制沿用系统默认,复制的是可见文字。
- **输入路径**:`textViewDidChange` 时若 `markedTextRange` 为空,就按字素求编辑面与当前可见文本的公共前后缀,得到可见 UTF-16 范围,带修订号调用 `SourceMap::apply_edit`,由内核做最小的规范 Markdown 事务。每次被接受后重建 `SourceMap`,刷新样式;可见文本有变化时(例如内核规范化)以内核为准更新编辑面。内核拒绝时,以内核为准重置编辑面,并把光标放回合理位置。差异计算与范围换算写成可单测的纯函数,覆盖中英文、emoji、组合字。
- **撤销**(我定的,回答 §7.8):关掉 `UITextView` 自带的撤销栈,改为一个转发给内核 `undo` / `redo` 的 `UndoManager` 子类。这样三指手势、摇一摇和硬件键盘的 ⌘Z / ⇧⌘Z 都走内核。撤销粒度跟内核走:内核撤销不合并相邻事务(`capture_timeout_millis: 0`),与桌面一致。撤销后重建 `SourceMap`,光标放在变化区的末尾;`canUndo` / `canRedo` 由内核给出,FFI 需要暴露这两个查询。
- **外观**:六种主题的色值、光标外形(宽度为字号 / 11,限制在 2–3 pt)、呼吸或常亮、聚焦打字,都按 04。字号与行距可调,偏好存在 `UserDefaults`。设置用 SwiftUI 弹层;菜单按钮放在编辑区之外的一条里(§3.3)。
- **键盘避让**:编辑区底边约束到 `keyboardLayoutGuide`,接上硬件键盘、软键盘收起后收回留白(§3.2)。
- **打字音**(我定的):M1 就带上。按 04 的规则,样本是 `apps/notemd-plugin/resources/sounds/` 的 WAV,构建时复制进应用包,不在 `apps/ios/` 另存一份。默认音色 `typewriter`,`thock` 的抬起声等 M4 有了硬件键盘的抬起事件再说,用常驻 `AVAudioEngine` 加轮换节点。音频会话用 `ambient` 并与其他应用混音,随静音键静音,按 iOS 惯例回答 §3.4 的待定项。
- **VoiceOver**(回答 §7.10 的最低线):自绘光标对无障碍隐藏。VoiceOver 仍能读正文,并报告插入点与选区。
- **为 RimeKit 留口**:编辑面的 `pressesBegan` / `pressesEnded` 先经过一个可替换的按键处理入口。默认不处理、交回系统。

### 5.5 M1 的保存(我定的)

M1 只有一页纸,但要能在 Duo 上真正用。做法如下:

- 用内核自带的 SQLite 库存这一页,放在 Application Support。写法按 `core/README.md`「Host integration」第 1、2、4 条:
  - 第一次启动由应用 `Document::new` 建页(新 UUID 作 page_id),立刻用 `Store::commit_local_with` 落下初始完整状态;
  - 之后每次被接受的事务用 `commit_local_delta_with` 追加增量,退到后台时 `checkpoint_with`;
  - 每次启动用新的 Yjs client ID(`fresh_client_id`),不复用上次的。
- 写库在后台串行队列上做,输入线程不等锁。退到后台时用 `beginBackgroundTask` 争取时间,把队列写完再做检查点。
- 启动时打开同一页,恢复光标与阅读位置。光标用内核的 `SelectionAnchor` 存(可序列化),存在 `UserDefaults`;解析失败时退到文末。
- 写库失败(我定的):照桌面 `draft_error` 的做法,保留可见文字,禁止继续修改,编辑区外的那一条显示「保存失败」。M1 不做自动重试。
- 这里没有输入日志,也不承诺强杀后一定不丢。最后几毫秒的输入可能丢,这条保证留给 M2 的 `session/`。
- 库格式就是内核的格式,M2 不需要为它另做迁移。如果 M2 改了库的位置或工作区结构,由 M2 的计划负责把 M1 这一页接过去。

### 5.6 规范与规程改动(先于实现)

- [ios.md](../../spec/platform/ios.md):
  - §6.1 改为「M0、M1 可在第 3 期之前开工;M2 起要等第 3 期完成」;
  - 开头的「本仓库里也没有 iOS 代码」随实现更新;
  - M0、M1 交付后,§4.1 与相关小节的状态改为已交付,并附证据;
  - §7.1、§7.6、§7.7、§7.8、§7.10 与 §3.4 静音键的答案写回对应小节。
- [02-migration-plan](../../handoff/02-migration-plan.md) 第 4 期:前置条件改为与 §6.1 一致。
- `AGENTS.md` 第 7 条:模块清单加上 `apps/ios/`,测试命令写在其 README 的 Verification 段。AGENTS.md 要人确认后才生效,认可本设计即视为确认这一处。
- 状态与证据按 AGENTS.md 第 3 条;提交前跑 `bash docs/check.sh`。

## 6. 验收

M0,agent 在模拟器上跑:

- `cargo +1.99.0 test --manifest-path apps/ios/ffi/Cargo.toml` 通过;
- `xcodebuild test`(iOS 模拟器)跑完 §5.3 的夹具比对,全部通过。

M1,自动部分:差异计算与可见 UTF-16 换算、经 `apply_edit` 落到源码、拒绝后重置、撤销转发、写库后重开的单元测试通过。

M1,手工部分:用户在 Duo 上执行,agent 给出清单。

1. 拼音输入中英文,选词上屏,正文与内核一致;
2. emoji 与组合字;粘贴 `# 标题`、`**粗体**` 等 Markdown 后显示为富文本,直接键入的 `#`、`*` 按字面保留;
3. 撤销与重做;
4. 全程看不到系统细线光标,呼吸与常亮都对;
5. 六种主题、字号、行距;
6. 聚焦打字时画面不跳;
7. 打字音随静音键;
8. 接上硬件键盘时留白收回;
9. 划掉应用再打开,正文、光标位置还在。

## 7. 留给执行的人

- 具体的 Swift 文件划分、类型命名、SwiftUI 设置面板的样子。
- 应用图标先用占位图(§6.2 把正式图标留给发行事务)。
- 显示名用「玄霜写作」。
- FFI 对象的具体方法签名,只要满足 §5.2 的能力清单。

## 8. 我定的,一览

1. 代码放 `apps/ios/`,用 XcodeGen,生成的工程不进仓库。
2. 签名信息只在 git 忽略的 `Signing.local.xcconfig` 里;安装脚本由用户执行。
3. XCFramework 只含真机 arm64 与模拟器 arm64;工具链钉 1.99.0。
4. M0 验收改为 XCTest,在模拟器上跑,不再放进应用里自检。
5. 撤销交给内核,用转发型 `UndoManager` 接管系统撤销手势;粒度跟内核,每次事务一步。
6. M1 带打字音,随静音键。
7. M1 用内核的 SQLite 存一页,不承诺强杀不丢;写库失败时照桌面停写并提示,不重试。
8. 光标存成内核的 `SelectionAnchor`,放在 `UserDefaults`。
9. 认可本设计即确认 AGENTS.md 第 7 条加入 `apps/ios/`。

## 9. 顺序

1. 规范改动(§5.6),跑 `docs/check.sh`。
2. M0:`ffi/`、`build-core.sh`、XCTest 夹具比对。
3. M1:编辑面、外观、保存、打字音,以及单元测试。
4. 交付:给用户安装命令与手工清单;用户在 Duo 上过一遍之后,把证据写回 ios.md。

归档目录的计划正在 note.md 侧执行(任务 6 起)。本计划只动本仓库的 `apps/ios/` 与文档,两边互不阻塞;具体排期由实施计划定。
