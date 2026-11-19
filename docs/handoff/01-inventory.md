# 01 清单:Sumi 代码与资产在 note.md 中的位置与归属

本文逐目录列出玄霜写作(Sumi Write,插件 ID `notemd.sumi`)目前散落在 note.md 仓库里的代码与资产,给出归属判定。基线:note.md `main` 969f8e73,宿主 tag `v6.1117.1`,插件 0.1.16。

归属判定与迁入期次以设计文档 `docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md`(note.md 仓库 `docs/sumiwrite-extraction` 分支,提交 `0c11629f`;该分支尚未推送到任何远端,暂不公开,见 [04-known-gaps §2.2](04-known-gaps.md))的 §5.2 归属表和 §8 分期为准(下称“设计”)。设计没有明说的条目,由本文判定并标 **[我的判断]**,附一行理由。

## 读法

- **规模**:`文件数 / 行数`,实测。文件数含目录下全部文件(不含 `node_modules`、`target`、`dist`);行数只统计文本源码与文档(`.rs .ts .tsx .svelte .js .mjs .py .sh .m .h .c .toml .md .json .css .swift`),不含 `*.lock`、二进制与压缩包。数字会随源仓库变动,以迁移当期实测为准。
- **归属**:`sumiwrite` 或 `note.md`。
- **迁入期次**:`1`、`2`、`3`,或 `不迁`。期次定义见设计 §8:1 = 内核、服务契约、同步服务;2 = 插件壳、资源、插件侧脚本;3 = 实时编辑会话下沉为共用 `session/`;4 = iOS 新建(不涉及现有代码)。
- 契约名称 `host-contract v1` 见 [03-notemd-contract.md](03-notemd-contract.md)。已知缺口见 [04-known-gaps.md](04-known-gaps.md)。

## 1. 总表(对应设计 §5.2)

| 现位置 | 规模(文件 / 行) | 依赖 | 归属 | 迁入期次 | 备注 |
|---|---|---|---|---|---|
| `write-core/` | 39 / 6674 | 无 note.md 内部依赖;`Cargo.toml` 声明 MIT 但无 LICENSE 文件(设计 §6) | sumiwrite | 1 | 编辑内核。含 `WIRE.md`、`examples/`、`tests/`。迁入时把 MIT 声明改为 Apache-2.0(设计 §12) |
| `sumi-protocol/` | 7 / 393 | `write-core`(`Cargo.toml:10`) | sumiwrite | 1 | 宿主与插件后台的内部服务契约,不是同步线协议;iOS 不使用。`Cargo.toml` 没有许可声明,迁入时补 Apache-2.0。宿主 `src-tauri/Cargo.toml:39-40` 与插件后台 `Cargo.toml:12-13` 都直接依赖它和 `write-core` |
| `write-sync-worker/` | 33 / 3566 | 依赖源仓库根下 `worker/` 的 Wrangler、`tsc`、`vitest`,以及根目录 `.env`、`worker/wrangler.toml`,详见第 5 节 | sumiwrite | 1 | 同步服务。行数含 `package-lock.json`(本行是例外,其余行不计 lock 文件)。迁入前必须先解开第 5 节的三处依赖 |
| `plugins-src/write/`(不含 `resources/`) | 28 / 10692 | 反向依赖 note.md 的四样东西,详见第 4 节 | sumiwrite | 2 | 桌面插件壳:`src/`(前端)、`backend/`(插件后台,含 `sync.rs`、`coordinator.rs`、`durability.rs`;这些后台文件第 2 期随插件壳整体迁入,第 3 期再把其中与宿主无关的同步协调部分切出下沉到 `session/`,设计 §8、§10.2)、`manifest.v2.json`、构建配置。0.1.16 对应此处 `manifest.v2.json` |
| `plugins-src/write/resources/` | 24 / 1309(json 与 txt 共 12 个文件;另 12 个 WAV 音效) | 无 | sumiwrite | 2 | 打字音效(`sounds/`)、字体目录与许可来源文件(`sumi/`)。字体本体不入包,按需下载 |
| `src/lib/sumi/i18n.ts` | 1 / 109 | 被插件壳和宿主两边引用,详见第 4 节 | sumiwrite | 2 | 插件界面文案。宿主 `SumiRecovery.svelte:3`、`NativeFileView.svelte:13` 也用,处理方式由第 2 期计划定(设计 §5.2) |
| `src/lib/sumi/`(除 `i18n.ts`) | 8 / 475 | 宿主前端、Tauri 调用 | note.md | 不迁 | `files.ts`、`focus.ts`、`geometry.ts`、`recovery.ts`、`session.ts` 与对应测试。宿主内的 Sumi 界面适配(设计 §5.2「宿主内 Sumi 界面与 Tauri 适配」) |
| `src/components/SumiRecovery.svelte`、`src/components/NativeFileView.svelte` | 2 / 289 | `src/lib/sumi/`、Tauri | note.md | 不迁 | 宿主内 Sumi 界面,设计 §5.2 点名;另有同目录的 `SumiRecovery.test.ts`、`NativeFileView.actions.test.ts` 等测试一并留下 |
| `src-tauri/src/sumi/` | 17 / 8685 | Tauri、`plugin_runtime`、原生桥 `tauri-plugin-native-editor`、`write-core`、`sumi-protocol` | 拆分:见第 2 节 | 3(可下沉部分)/ 不迁(宿主适配部分) | 实时编辑会话。按文件判定见第 2 节 |
| `tauri-plugin-native-editor/` | 47 / 12442 | AppKit / GTK;被宿主 `src-tauri` 编译进去 | note.md | 不迁 | 原生编辑桥,是宿主能力(设计 §3、§5.2),含 `native/*-probe.m` 探针。桌面独立应用评估通过后才会随之迁入(设计 §9) |
| `packaging/omarchy/fcitx5-sumi-candidates/` | 8 / 138(另含源码压缩包) | Linux 宿主打包流程 | note.md | 不迁 | Fcitx5 for Sumi 打包。设计 §5.2 判定随 Linux 宿主打包 **[我的判断]**。输入法本身是独立项目,不并入 |
| `notemd-plugin-sdk/` | 3 / 749 | `plugin-protocol`(note.md 根下,设计未列) | note.md | 不迁 | 插件 SDK。sumiwrite 的插件壳按 tag 引用它(设计 §5.3)。注意它再依赖 `plugin-protocol/`,见第 4 节 |
| `plugins-registry/` | 14 / 2448(不含 `node_modules`) | Cloudflare Worker | note.md | 不迁 | 插件市场。设计 §5.2 判定 |
| `scripts/release-plugins.sh`(其中 `release_sumi()`) | 1 个函数,`:351` 起 | 签名密钥、公证、minisign | note.md | 不迁 | 签名、公证、上架留在 note.md(设计 §5.3 第 5 条) |
| `docs/superpowers/reports/*sumi*` | 68 个文件 | 无 | note.md | 不迁 | 历史发布证据。新规范链接到宿主 tag、提交号与这些路径 |
| `docs/superpowers/specs/*sumi*` 及其他旧规范 | 文件名含 `sumi` 的 15 份(含本设计文档) | 无 | sumiwrite(内容重写) | 本期(第 0 期) | 旧文档留在原处不删;新规范见 `docs/spec/`。旧文档文首加指引的动作放第 1 期(设计 §7.2) |
| `scripts/sumi/` | 63 / 3995(含子目录) | 逐条目见第 3 节 | 拆分:见第 3 节 | 2 / 不迁 | 逐条目判定 |
| `plugins-src/shared/shortcuts.ts` | 1 / 25 | 插件壳 `main.ts:2` 引用 | note.md(暂定) | 待第 2 期计划 | 设计 §5.3 第 2 条:共享快捷键 TypeScript 的处理方式由第 2 期计划定。实测(grep `shared/shortcuts`)另有插件引用它:`plugins-src/next/src/App.svelte:2` 与 `plugins-src/next/src/components/` 下的 `CreateIdeaSheet.svelte`、`ReminderSheet.svelte`、`MetadataSheet.svelte`、`CreateTaskSheet.svelte`,以及 `plugins-src/idea-spark/src/App.svelte:47` 与 `lib/shortcuts.test.ts:3`。它是多个插件共用的文件,所以留在 note.md,sumiwrite 若需要就复制一份 **[我的判断]** |

补充:iOS/iPadOS 应用(`apps/ios/`,第 4 期)在 note.md 里没有对应现存代码,不在本清单范围。

## 2. `src-tauri/src/sumi/` 按文件判定

设计 §5.2:实时编辑会话中与 Tauri 无关的部分(owner、组字防护、输入日志、恢复、凭据逻辑)第 3 期下沉成共用 Rust 模块 `session/`,宿主只留薄适配;命令注册、窗口、系统钥匙串与原生桥对接留在宿主。第 3 期的验收口径:`session/` 不依赖 Tauri 和插件 SDK(设计 §8)。

| 文件 | 规模(行) | 职责与依赖 | 判定 | 备注 |
|---|---|---|---|---|
| `mod.rs` | 4858 | 会话主体,见下方职责分块;依赖 `tauri`、`tauri_plugin_native_editor`、`write_core`(`:26-29`) | 拆分:可下沉与宿主适配并存 | 第 3 期最大的一块工作。owner、远端更新暂缓、预留队列等逻辑与 Tauri 命令缠在同一个文件里,切分方式留给第 3 期计划(设计 §10.2) |
| `journal.rs` | 237 | 宿主本机输入日志,只依赖 `rusqlite`、`fs2` 与同模块类型(`:3-6`),不碰 Tauri | 可下沉(第 3 期) | 设计点名的“输入日志”。依赖 `mod.rs` 里的 `CommitReceipt`、`LocalEdit`、`Request`,下沉时需先把这些类型一并抽出 |
| `recovery.rs` | 443 | 从便携文件恢复为新页,只读源文件,依赖 `write_core`(`:1-6`) | 可下沉(第 3 期) | 设计点名的“恢复”。配套测试 `recovery_tests.rs`(287 行)同行 |
| `durability.rs` | 279 | 耐久队列,依赖 `service::Backend`、`sumi_protocol::durability`(`:5`、`:13`) | 可下沉(第 3 期) **[我的判断]** | 无 Tauri 引用,但依赖宿主到插件后台的传输 `service.rs`,下沉时需把 `Backend` 抽象成接口。理由:iOS 同样需要“先落盘再同步” |
| `credentials.rs` | 156 | 设备凭据结构与 macOS 钥匙串读写(`:76` 用 `security_framework`) | 拆分 **[我的判断]** | 设计把“凭据逻辑”下沉、“系统钥匙串”留宿主:凭据数据结构与校验可下沉,`security_framework` 调用留宿主适配;iOS 另写钥匙串适配 |
| `credentials_linux.rs` | 250 | libsecret 绑定 | 宿主适配(不迁) | 系统钥匙串对接,设计明确留宿主 |
| `auth.rs` | 407 | 钥匙串/鉴权代理,只把短期令牌交给插件后台;使用 `tauri::http`(`:334`) | 宿主适配(不迁) **[我的判断]** | 理由:紧贴 WebView 与钥匙串边界,含 Tauri 响应类型 |
| `coordinator.rs` | 59 | 宿主侧 UI/会话门面,使用 `tauri::async_runtime::spawn`(`:53`) | 宿主适配(不迁) | 网络调度已在插件后台,这里只是薄门面 |
| `service.rs` | 307 | 宿主到插件后台的私有传输,依赖 `crate::plugin_runtime`、`tauri::Manager`(`:5-6`) | 宿主适配(不迁) | 属于 `host-contract v1` 的实现侧 |
| `sound.rs` | 668 | 打字音效队列,依赖 `native::TypingSoundEvent`(原生输入监视) | 宿主适配(不迁) | 依赖原生桥。iOS 第一阶段也做打字音(2026-11-20 用户定,推翻设计 §10.1),但在 Swift 编辑面里按正文变更发声,不复用此模块,见 [ios §3.4](../spec/platform/ios.md#34-打字音) |
| `external.rs` | 125 | 已知页面文件视为投影,依赖 `write_core` | 可下沉(第 3 期)待定 **[我的判断]** | 无 Tauri 引用;但 vault 投影是桌面专有(设计 §5.4),iOS 无 vault,所以落点不是共用 `session/`,由第 3 期计划决定 |
| `fonts.rs` | 52 | 宿主侧字体桥,依赖 `service::Connector` | 宿主适配(不迁) | 字体下载在插件后台,这里只转接 |
| `paste.rs` | 103 | 剪贴板转换:`html5ever` 把 HTML 转纯文本或 Markdown,无 Tauri | 可下沉(第 3 期) **[我的判断]** | 与平台无关;iOS 粘贴同样需要同一套转换 |
| `export.rs` | 263 | 导出,使用 `tauri_plugin_dialog`(`:7`) | 宿主适配(不迁) | 保存对话框是宿主能力。iOS 另走系统分享(设计 §10.1) |
| `sync.rs` | 2 | 重新导出 `sumi_protocol::sync::Invitation`(UI 用线类型) | 宿主适配(不迁) | 随 `sumi-protocol` 按 tag 引用 |
| `lifecycle_tests.rs` | 189 | 宿主生命周期回归(`use super::*`) | 随 `mod.rs` | 跟着对应被测代码走,第 3 期切分时拆开 |
| `recovery_tests.rs` | 287 | 恢复回归(`use super::*`) | 随 `recovery.rs` | 同上 |

`mod.rs` 职责分块(按行号,近似边界,供第 3 期切分参考):

| 行范围 | 职责 |
|---|---|
| 1-130 | 模块声明、插件常量、窗口可见性与“关闭中”围栏、`plugin_window_shown`、`show_created_plugin_window` |
| 128-450 | 全局状态与核心类型:`Workspace`、`Paper`、`Owner`、`Preferences`、`PendingLocal`、`ReadingPosition`、`RemoteCandidate` 等 |
| 451-1010 | 工作区查找与授权、持久化事件处理(`durable_event`)、阅读位置、纸页创建与激活、选区与队列 |
| 1010-1710 | 编辑动作与输入应用(`apply_action`、`apply_input`)、原生回调处理(`handle_native`)、远端更新排空与组字后补排(`drain_remote_locked`) |
| 1713-2000 | 打开身份检查、偏好加载、界面语言、字体选择流程 |
| 2001-2400 | 原生挂载(`mount`)、冻结清理、`flush`、`detach` |
| 2300-2850 | 源文件保存、已知文件对账、`open_path`、投影恢复、`sumi_recover_new` 等恢复命令 |
| 2850-3410 | `sumi_*` 命令入口(挂载、冲刷、分离、聚焦、边界、可见性),以及 `before_close`、`before_exit`、`resume_*`、`cleanup_plugin` 生命周期 |
| 3408-3660 | 全屏字号、外观应用、配对请求、菜单事件、窗口边界换算 |
| 3666-3915 | `dispatch`:`host.sumi.*` 命令分发(`host-contract v1` 的主要实现面) |
| 3916-4857 | 单元测试(`mod tests`) |
| 4858 | 声明 `lifecycle_tests` |

> 只有最后两行(`mod tests` 起于 3917 行、`lifecycle_tests` 声明在 4858 行)是精确锚点;其余行范围由 `grep` 函数起始行得出,是近似值,各块之间有重叠的辅助函数。

## 3. `scripts/sumi/` 逐条目判定

判定规则(来自任务要求):运行时需要启动 note.md 宿主、链接 `tauri-plugin-native-editor`、或驱动真实窗口与输入法的,归 note.md;只依赖内核、插件壳或同步服务的,归 sumiwrite 第 2 期;拿不准的标“待第 2 期判定”并写明原因。

源仓库 `scripts/sumi/` 共 34 个一级条目(文件或目录),63 个文件,3995 行。

| 条目 | 规模(文件 / 行) | 依赖 | 归属 | 迁入期次 | 备注 |
|---|---|---|---|---|---|
| `acceptance/` | 7 / 476 | 构建与安装宿主验收包(`tauri.acceptance.json`、`build.sh`、`prepare.py`) | note.md | 不迁 | 宿主验收构建 |
| `artifact_checks.py` | 1 / 107 | 宿主 bundle id `net.notemd.app`,DMG 检查,原文件摘自宿主发版校验脚本 | note.md | 不迁 | 检查宿主安装包 |
| `audit-web-reports.mjs` | 1 / 110 | `corpus.mjs`,读取基准报告 | note.md | 不迁 | 同机编辑基准工具包的一部分,比较的是宿主 Rich 编辑器与原生桥 |
| `audit-web-reports.test.mjs` | 1 / 34 | `audit-web-reports.mjs` | note.md | 不迁 | 同上 |
| `browser/` | 5 / 179 | 宿主 `RichEditor` 与 Tauri 隔离适配 | note.md | 不迁 | 基准页入口 |
| `browser-harness.test.ts` | 1 / 52 | `browser/`、`@tauri-apps/api` 的 mock | note.md | 不迁 | 基准页冒烟测试 |
| `build.mjs` | 1 / 22 | 构建宿主 `RichEditor.svelte` 基准包 | note.md | 不迁 | 同上 |
| `corpus.mjs` | 1 / 34 | 无外部依赖,生成基准语料 | note.md | 不迁 **[我的判断]** | 本身不依赖宿主,但只服务基准工具包,单独迁走没有使用者 |
| `corpus.test.mjs` | 1 / 11 | `corpus.mjs` | note.md | 不迁 **[我的判断]** | 同上 |
| `fcitx-candidates/` | 4 / 89 | 运行原生编辑器与 Fcitx5 候选窗,驱动真实输入法 | note.md | 不迁 | 与 `packaging/omarchy/fcitx5-sumi-candidates/` 同属输入法侧验收 |
| `isolate-tauri.mjs` | 1 / 16 | 改写 Tauri 全局以隔离宿主 IPC | note.md | 不迁 | 基准工具包 |
| `isolate-tauri.test.mjs` | 1 / 13 | `isolate-tauri.mjs` | note.md | 不迁 | 同上 |
| `macos-ime-marker/` | 8 / 344 | macOS 输入法标记探针,驱动真实输入法 | note.md | 不迁 | 驱动真实输入法 |
| `native/` | 4(不含 `Cargo.lock`)/ 306 | `runner.m` 直接编译宿主 `tauri-plugin-native-editor/native/editor.m`(见 `run-native.mjs`) | note.md | 不迁 | 链接原生桥的基准运行器 |
| `native-release.py` | 1 / 164 | Developer ID 签名与公证;`SOURCE_DIRS`(`:11`)列出 `plugins-src/write/backend`、`sumi-protocol`、`write-core`、`notemd-plugin-sdk`、`plugin-protocol` | note.md | 不迁 | 签名公证留在 note.md(设计 §5.3 第 5 条)。第 1、2 期迁走目录后 `SOURCE_DIRS` 里的路径要随之改,记入 [04-known-gaps.md](04-known-gaps.md) |
| `test_native_release.py` | 1 / 80 | `native-release.py`(`:42` 断言 `SOURCE_DIRS` 内容) | note.md | 不迁 | 随被测脚本 |
| `probe-input-present.sh` | 1 / 49 | 附着到已运行的验收应用进程 | note.md | 不迁 | 需要宿主验收应用 |
| `probe-pointer/` | 4 / 458 | Wayland 虚拟指针与键盘注入,驱动真实窗口 | note.md | 不迁 | Linux 窗口驱动 |
| `README.md` | 1 / 81 | 同机基准说明 | note.md | 不迁 | 随基准工具包 |
| `run-native.mjs` | 1 / 26 | 编译并运行 `native/`,哈希 `tauri-plugin-native-editor/` 输入 | note.md | 不迁 | 同上 |
| `sample-process.mjs` | 1 / 17 | 对指定 PID 采样 | note.md | 不迁 **[我的判断]** | 不依赖宿主代码,但只用于宿主进程基准,留在基准工具包一起 |
| `serve.mjs` | 1 / 32 | 基准页本地服务 | note.md | 不迁 | 基准工具包 |
| `summarize.mjs` | 1 / 14 | 汇总基准报告 | note.md | 不迁 | 基准工具包 |
| `test_fullscreen_appearance.py` | 1 / 165 | 读取 `src-tauri/src/sumi/mod.rs`(`:153`)并执行宿主外观适配 | note.md | 不迁 | 测宿主适配。第 3 期切分 `mod.rs` 后读取路径要核对 |
| `test_verify_linux_binary.py` | 1 / 35 | `verify-linux-binary.py` | sumiwrite | 2 | 随被测脚本 |
| `test-linux-credentials.sh` | 1 / 65 | 编译宿主 `src-tauri/src/sumi/credentials.rs`(`:34`),需要 libsecret | note.md | 不迁(第 3 期复核) | 现在测的是宿主文件;第 3 期若凭据逻辑下沉,测试跟着拆。待第 3 期判定 |
| `test-macos-candidates.sh` | 1 / 19 | 编译 `tauri-plugin-native-editor/native/*-probe.m` | note.md | 不迁 | 原生探针 |
| `verify-embedded.mjs` | 1 / 82 | 检查宿主 Mach-O 内嵌资源 | note.md | 不迁 | 宿主二进制校验 |
| `verify-extracted-assets.mjs` | 1 / 62 | 检查宿主 Mach-O 与 Tauri 内嵌资源 | note.md | 不迁 | 同上 |
| `verify-linux-binary.py` | 1 / 33 | 只检查插件后台二进制的架构与可执行性;`release-plugins.sh:380` 调用 | sumiwrite | 2 | 只依赖插件产物。迁走后 `release_sumi()` 需改为引用 sumiwrite 的构建物校验,见第 4 节 |
| `verify-linux-probe.py` | 1 / 323 | 驱动运行中的 Tauri 探针窗口与合成键盘输入 | note.md | 不迁 | 驱动真实窗口 |
| `verify-release.md` | 1 / 64 | 宿主 + 插件发版校验说明 | note.md | 不迁 | 随 `verify-release.py` |
| `verify-release.py` | 1 / 627 | 读取 `src-tauri/`、`tauri-plugin-native-editor/`、`plugins-src/write/` 多处源文件并校验宿主 DMG(`:20-44`、`:334-338`) | note.md | 不迁 | 宿主发版门禁,是发版与签名流程的一部分。其中对插件资源的校验部分第 2 期是否拆出,**待第 2 期判定**:现状把宿主和插件资源混在一个脚本里 |
| `verify-sounds.py` | 1 / 84 | 只校验音效 WAV 包与 `plugins-src/write/resources/sounds`;`release-plugins.sh:394`、`:397` 调用 | sumiwrite | 2 | 只依赖插件资源。迁走后 `release_sumi()` 需改引用,见第 4 节 |

> 判定为 sumiwrite 的暂时只有三项(此结论不是最终的:`verify-release.py` 横跨宿主与插件资源两边,第 2 期拆分后可能有一部分也归 sumiwrite):`verify-sounds.py`、`verify-linux-binary.py`、`test_verify_linux_binary.py`。其余都需要宿主、原生桥或真实窗口,或属于发版门禁。`verify-sounds.py` 与 `verify-linux-binary.py` 同时被 note.md 的发版脚本调用,迁走后调用方式由第 2 期计划定。

## 4. 反向依赖:插件壳对 note.md 的依赖

设计 §3 列了三样东西。下面逐项给出源码位置;读源码时发现还有一处设计没有列出。

| 依赖 | 位置(行号) | 说明 |
|---|---|---|
| `notemd-plugin-sdk` | `plugins-src/write/backend/Cargo.toml:11`(路径依赖 `../../../notemd-plugin-sdk`);`plugins-src/write/backend/src/main.rs:3`(`notemd_plugin_sdk::serve(...)`);`plugins-src/write/backend/src/runtime.rs:3`(引入 `Host`、`NotemdPlugin`、`ServiceFuture`、`ExecuteCommandParams`、`InitializeParams`、`plugin_protocol::ActivateParams`) | 迁出后改为按 tag 引用(设计 §5.3 第 2 条) |
| `plugin-protocol`(设计未列) | `notemd-plugin-sdk/Cargo.toml:8`(路径依赖 `../plugin-protocol`);`scripts/sumi/native-release.py:11`(`SOURCE_DIRS` 含 `plugin-protocol`);`runtime.rs:3`(`plugin_protocol::ActivateParams`) | SDK 再依赖 note.md 根下的 `plugin-protocol/`,迁出后按 tag 引用 SDK 时会一并带上它。设计 §5.2 与 §5.3 未提这个 crate,记入 [04-known-gaps.md](04-known-gaps.md) |
| `src/lib/sumi/i18n.ts` | `plugins-src/write/src/main.ts:3`(`import { createI18n } from '../../../src/lib/sumi/i18n'`);`plugins-src/write/src/i18n.test.ts:2`(同一导入) | 第 2 期随插件壳迁走;宿主一侧的使用在 `src/components/SumiRecovery.svelte:3` 和 `src/components/NativeFileView.svelte:13`,不能直接断开 |
| `plugins-src/shared/shortcuts.ts` | `plugins-src/write/src/main.ts:2`(`import { isApplePlatformSync, primaryShortcut, shortcutEventBlocked } from '../../shared/shortcuts'`) | 文件仅 25 行。设计 §5.3 第 2 条:处理方式由第 2 期计划定 |
| `scripts/release-plugins.sh` 的 `release_sumi()` | `scripts/release-plugins.sh:351` 定义,`:795` 分发(`sumi) release_sumi ;;`);函数内调用:`:377` `scripts/sumi/native-release.py`、`:380` `scripts/sumi/verify-linux-binary.py`、`:394` 与 `:397` `scripts/sumi/verify-sounds.py`,构建 `plugins-src/write/backend` 与 `plugins-src/write` 前端(`:353`、`:374`、`:383`) | 签名、公证、minisign 与打包留在 note.md。迁出后这个函数要改为消费 sumiwrite 产出的待签名构建物(设计 §5.3 第 5 条) |

插件壳对 `src-tauri/` 没有源码级依赖;它们通过插件协议在运行时通信(`host.sumi.*` 命令,见 [03-notemd-contract.md](03-notemd-contract.md))。

## 5. 同步服务对源仓库的依赖

`write-sync-worker/` 当前不是自给自足的。设计 §5.2 提到三处,实际可数出下列几项,迁入第 1 期前必须解开。

| 依赖 | 位置 | 说明 |
|---|---|---|
| 根下 `worker/node_modules` 里的 Wrangler 与 `tsc` | `write-sync-worker/package.json:8-10`(`check` 用 `../worker/node_modules/.bin/tsc`,`dev` 与 `deploy` 用 `../worker/node_modules/.bin/wrangler`);`write-sync-worker/scripts/deploy.sh:5-6`、`:16`、`:22`;`write-sync-worker/scripts/cloud-admin.py:14`、`:67` | 没有自己的工具链,指向源仓库另一个项目的安装目录 |
| 工具链链接脚本 | `write-sync-worker/scripts/link-toolchain.mjs:10-18`(把 `vitest`、`@cloudflare/vitest-pool-workers`、`@cloudflare/workers-types`、`typescript`、`wrangler` 从 `../worker/node_modules` 软链进来,并要求 Wrangler 是 3.x) | 由 `pretest`、`precheck` 触发(`package.json:11-12`) |
| 根目录 `.env` | `write-sync-worker/scripts/cloud-admin.py:42`(读取 `ROOT/.env`) | 云账号凭据所在。迁出后改为 sumiwrite 自己的配置入口。按设计 §12,只放凭据引用,不放秘密 |
| `worker/wrangler.toml` 里的账号 ID | `write-sync-worker/scripts/cloud-admin.py:46`(正则取 `worker/wrangler.toml` 的 `account_id`) | `write-sync-worker/wrangler.toml` 自己没有账号 ID |
| 钉死的 Wrangler 版本 | `write-sync-worker/scripts/cloud-admin.py:82`(源码证明里写死 `'wrangler':'3.114.17'`) | 与 `link-toolchain.mjs` 要求的主版本 3 对应 |
| 钉死的兼容日期 | `write-sync-worker/wrangler.toml:3`(`compatibility_date = "2024-12-30"`);另有 `compatibility_flags = ["nodejs_compat"]`(`:4`) | 迁出后不要随意改动 |
| 源仓库根下的任务目录 | `write-sync-worker/scripts/deploy.sh:12`(日志写 `../tasks/sumi-sync/wrangler.log`) | 路径假设了 note.md 的目录布局 |
| `ROOT` 推导 | `write-sync-worker/scripts/cloud-admin.py:11`(`ROOT=Path(__file__).resolve().parents[2]`,即源仓库根) | 路径假设整体都以 note.md 仓库根为基准 |

资源名(便于核对,不属依赖):Worker 名 `sumi-sync`(`wrangler.toml:1`)、Durable Object `SumiSpace`(`:10`)、备份桶 `sumi-sync-backups`(`:18`)。

## 6. 需要记入 known-gaps 的事项

- 设计没有列出的反向依赖:`plugin-protocol/`(经 `notemd-plugin-sdk`)。
- `scripts/sumi/native-release.py:11` 的 `SOURCE_DIRS` 与 `test_native_release.py:42` 的断言写死了迁移后会变的目录路径。
- `scripts/sumi/verify-release.py` 把宿主与插件资源校验混在一个文件里,第 2 期是否拆分未定。
- `plugins-src/shared/shortcuts.ts` 被 `next`、`idea-spark` 两个插件共用(见第 1 节),留在 note.md;sumiwrite 复制一份还是改引用,由第 2 期计划定。
- `src-tauri/src/sumi/external.rs`、`durability.rs` 的下沉落点,以及 `journal.rs` 依赖的 `mod.rs` 类型怎么抽出,留给第 3 期计划。
- 同步服务依赖项里 `.env` 的迁出方式、账号 ID 的新存放位置,留给第 1 期计划。
