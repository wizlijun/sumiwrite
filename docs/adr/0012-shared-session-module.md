# 0012 会话层下沉为共用 Rust 模块,不在 Swift 里重写

类型:新
状态:已决定(第 0 期);第 3 期执行,切分方式由第 3 期计划定。
记录日期:2026-11-18;出处为抽离设计 §5.2、§8、§10.2。归属标注沿用设计原文:**[用户定]** 是用户明确选择的,**[我的判断]** 是设计者补全、用户可推翻的。

## 背景

“数据不丢、合并正确”靠的不只是内核,还有内核之上的会话层。按 [0006](0006-plugin-backend-vs-host-session.md) 的切法,这一层目前分在两个进程里:

- 宿主 `src-tauri/src/sumi/`(基线共约 8.7k 行,其中 `mod.rs` 4858 行):单一编辑 owner、组字防护、本机输入日志(`journal.rs`)、崩溃恢复(`recovery.rs`)、凭据逻辑(`auth.rs`、`credentials*.rs`),与 Tauri 命令注册、窗口、钥匙串、原生桥对接混在一起。
- 插件后台:`sync.rs`(1972 行)、`coordinator.rs`(1028 行)、`durability.rs`(2926 行),共约 6k 行,负责同步客户端、同步协调与持久化。

这些代码测试最重(宿主侧另有 `lifecycle_tests.rs`、`recovery_tests.rs`)。iOS 版需要同样的会话语义:组字期间暂缓远端更新、输入线程不等锁、强杀后正文不丢、离线重连后合并正确(设计 §10.2、§10.3 M2/M3)。

## 决定

- **会话与同步逻辑不在 Swift 里重写** **[我的判断]**(设计 §10.2)。
- **第 3 期把实时编辑会话中与 Tauri 无关的部分下沉成共用 Rust 模块 `session/`,宿主只留薄适配** **[我的判断]**(设计 §5.2 归属表)。下沉范围按设计列举为 owner、组字防护、输入日志、恢复、凭据逻辑,加上插件后台的同步协调与同步客户端(设计 §10.2 架构图中 `session` 一层的内容)。
- 命令注册、窗口、系统钥匙串与原生桥对接留在 note.md 宿主(设计 §5.2)。
- **第 4 期 iOS 直接用 `session/`**,经 UniFFI 暴露给 Swift 薄适配层(见 [0010](0010-ios-uikit-textkit2-uniffi.md))。
- 具体切分方式(哪些函数下沉、进程边界如何保留、`sumi-protocol` 的服务契约如何对应)留给第 3 期计划;本 ADR 不预设。

## 放弃的方案

设计 §10.2 记录的:

- **Swift 重写会话层**:放弃。理由是这些逻辑是数据不丢、合并正确的关键,测试也最重;在 Swift 里再写一遍,就违反“两端实现不分叉”的反目标(设计 §2)。

设计 §4.4 放弃“纯 Swift 重写内核”的理由(两套实现要永远对齐,风险最高)同样适用于会话层,但设计没有为会话层单独列比较表。

## 后果

得到的:

- 桌面与 iOS 共享一套 owner、组字、日志、恢复与同步语义,现有测试随代码一起保护两端。
- 宿主侧会话代码变薄,桌面上改会话逻辑有机会只发插件包或只发 sumiwrite 构建物,而不必每次配套发宿主——前提是契约不变(设计 §5.3 第 4 部分)。

付出的:

- **第 3 期必须先于 iOS(第 4 期)**:iOS 的 M2(存储与崩溃恢复)、M3(同步与配对)都依赖 `session/`;第 3 期拖延,iOS 只能做到 M0/M1。iOS 的排期因此绑在一次高风险的宿主重构上。
- **要动最敏感的代码**:下沉的正是保证正文不丢的那部分。重构期间要保证 note.md 每一期都能照常构建和发版(设计 §2),桌面已有的真实独立进程测试、强杀恢复测试必须原样通过;宿主改依赖就要配套发宿主。
- **两进程变成一个模块,形状不一致**:桌面上这些逻辑横跨宿主进程与插件后台进程,中间隔着 stdio JSON-RPC 与收据/重放协议([0006](0006-plugin-backend-vs-host-session.md));iOS 是单进程。共用模块要同时适配“跨进程”与“进程内”两种部署,否则桌面侧仍得保留一份专用胶水。这层抽象如何定,`[未定]`。
- **平台差异要在下沉时解决**:插件后台 WebSocket 的 `rustls-tls-native-roots` 在 iOS 上很可能不可用(未实测),证书校验方式要换([0010](0010-ios-uikit-textkit2-uniffi.md));钥匙串在 macOS、Linux(`credentials_linux.rs`)与 iOS 上各不相同,凭据逻辑只能下沉与平台无关的部分。
- `session/` 目录到第 3 期才建;本期不建空目录(设计 §6)。

## 来源

- 抽离设计 §2、§4.4、§5.2、§5.3、§6、§8、§10.2、§10.3:note.md 源仓库 `docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md`(note.md 仓库 `docs/sumiwrite-extraction` 分支,提交 `0c11629f`;该分支尚未推送到任何远端,暂不公开,见 [04-known-gaps §2.2](../handoff/04-known-gaps.md))
- 宿主会话代码:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/journal.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/recovery.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/auth.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/credentials_linux.rs
- 插件后台:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/sync.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/coordinator.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/durability.rs
- 组字期间暂缓远端更新:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md
