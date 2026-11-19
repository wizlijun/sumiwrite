# 0006 持久化、投影、同步协调、字体下载放插件后台;宿主保留内存 CRDT、实时编辑会话与原生桥

类型:补记
状态:已采纳;随宿主 6.1108.5 / 插件 0.1.4 首次公开,现行于基线 v6.1117.1。
记录日期:2026-11-18;用户于 2026-11-08 确认实施(插件资源迁移规范文首“用户已确认实施”)。

## 背景

首版时 Sumi 的持久化、投影、网络与字体全在宿主里。两个问题随之而来:宿主体积因内置字体从约 13.5 MB 涨到 70.2 MB(主规范“轻量字体交付调整”);任何业务改动都要重发宿主。但正文逐键路径又不能为了拆分而等待跨进程 IPC(插件资源迁移规范 §目标与范围)。

## 决定

按“要不要贴着输入线程”切开:

- **插件后台**(签名原生可执行文件,经现有插件子进程 / stdio JSON-RPC 与生命周期监督运行)负责:SQLite 持久化(独占数据库写所有权)、Markdown/sidecar 投影、网络传输与同步协调、字体下载校验与缓存,以及打字音效播放。代码在 `plugins-src/write/backend/`。
- **宿主**保留:即时内存 CRDT 与选区映射、实时编辑会话(单一编辑 owner、IME 事务与组字屏障、Tab/焦点)、本机输入崩溃日志、原生编辑桥,以及系统服务桥——长期设备凭据留在宿主钥匙串,配对与短期令牌经宿主的窄认证代理;CoreText 字体注册与 IME 安全应用、打字音所需的只读按键监听权限桥也留宿主(主规范“键盘音效追加范围”)。代码在 `src-tauri/src/sumi/` 与 `tauri-plugin-native-editor/`。
- **两者之间是宿主专用服务契约 `sumi-protocol`**,与 WebView 的 `ui.request` 分离;UI 不能冒充宿主绑定 vault、数据库或缓存路径。会话绑定规范化 vault、协议版本与后台进程实例,重启先重新绑定,旧实例回调被拒绝。握手 `Hello` 带版本与能力列表。
- **保存语义**:宿主输入只做内存编辑和有界入队,入队成功不等于已保存。每条编辑带稳定 `op_id`、page/epoch/generation/revision 与内容摘要;后台把收据与数据同一 SQLite 事务提交后发 `Committed`,投影完成另发 `Saved`。宿主保留未确认编辑,后台崩溃后按原顺序、原 ID 重放;同 ID 异内容拒绝。
- 迁移只转移写所有权:SQLite、文件对与字体缓存沿用原路径,不清库、不重新配对。

## 放弃的方案

旧文档记录的:

- **只拆字体就立即发布**:旧候选计划,被本方案取代;对应的宿主 6.1108.3 / 6.1108.4 草稿与 Sumi 0.1.2 / 0.1.3 未公开(插件资源迁移规范文首)。
- **新建 dylib 插件体系 / 动态加载任意原生库**:本轮明确不做,后台走现有子进程机制(插件资源迁移规范 §目标与范围;主规范 §8)。
- **让 WebView UI 代理私有服务**:不以 UI 请求代理后台服务(主规范 §8 集成表)。

## 后果

得到的:

- 持久化、同步、字体、音效的业务改动在服务契约兼容范围内只发插件包(主规范 §8.1 表)。宿主 DMG 回到 14,175,207 字节,比曾内置字体的公开版少 56,040,079 字节(迁移发布报告)。
- 输入线程从不等待 IPC、网络或磁盘。

付出的:

- **双进程的可靠性成本**:幂等收据、顺序重放、背压、实例重绑、退出/停用/升级前的排空屏障,全部要真实独立进程测试覆盖(插件资源迁移规范 §验收与发布)。宿主侧 `durability.rs`、`journal.rs`、`recovery.rs` 就是为此存在的。
- **实时编辑会话没有拆出去**:`src-tauri/src/sumi/` 约 8.7k 行(`mod.rs` 4858 行),向插件暴露约 20 个 `host.sumi.*` 命令;改会话契约、服务代理、凭据桥或输入日志仍须配套发宿主(主规范 §8.1;设计 §3)。
- **会话与同步逻辑分在两个进程两份代码里**:宿主有 owner/组字/日志/恢复,插件后台有 `sync.rs`、`coordinator.rs`、`durability.rs`(约 6k 行)。这是 iOS 不能直接复用的形状,第 3 期要把与宿主无关的部分下沉,见 [0012](0012-shared-session-module.md)。
- 宿主 `src-tauri` 仍直接依赖 `write-core` 与 `sumi-protocol`,两边要同版本构建。
- 原生后台必须单独 Developer ID 签名与 Apple 公证;市场包的 minisign 签名不能替代。

## 来源

- 插件资源与后台迁移规范:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-08-plugin-payload-extraction.md
- 迁移发布报告(体积与发布结果):https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-08-plugin-payload-extraction.md
- 主规范 §5.2.3、§8、§8.1 及“轻量字体交付调整”“独立后台迁移”两节:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md
- 服务契约与握手:https://github.com/wizlijun/note.md/blob/v6.1117.1/sumi-protocol/src/lib.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/sumi-protocol/src/service.rs
- 宿主侧:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/service.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/journal.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/durability.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs
- 插件后台:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/sync.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/coordinator.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/durability.rs
- 设计 §3(规模与依赖):note.md 源仓库 [`docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md`](https://github.com/wizlijun/note.md/blob/0c11629f976226c688d186b13d4812da31073dc2/docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md)(note.md 提交 `0c11629f`)
