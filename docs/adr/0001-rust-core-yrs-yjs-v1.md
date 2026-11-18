# 0001 内核用 Rust,CRDT 用 Yrs,线格式为 Yjs V1

类型:补记
状态:已采纳;现行于基线 v6.1117.1 的 macOS 与 Linux 桌面代码。
记录日期:2026-11-18;决定出处为主规范(2026-11-07)与 `write-core` 的现行代码。

## 背景

玄霜写作要求同一页跨设备同时编辑、离线后重连自动合并,并明确不接受“整篇后写覆盖”或单写者锁(主规范 §1)。同时,正文要在 macOS AppKit、Linux GTK、将来的 iOS 等多个原生编辑面之间保持字节级一致。这要求一个与界面无关、可被多种宿主嵌入的文本与合并内核,以及一份所有客户端都遵守的线格式。

## 决定

- **内核语言是 Rust**:`write-core` 是平台无关的 crate,负责 Markdown 编辑、source map、Yrs CRDT、行时间与 SQLite 持久化,不依赖 Tauri 或任何 UI(macOS 计划 §文件结构;主规范 §8 职责边界)。
- **CRDT 实现固定为 Yrs `=0.24.0`**(精确版本锁定,`features = ["sync"]`)。
- **线格式是 Yjs update V1 与 state-vector V1。** 同步服务端用 Yjs 13.6.33 做解码与校验;互操作用双向黄金夹具验证:Rust 编码器产出 `yrs-v1.json`,Worker 侧 `interop.mjs` 在 Yjs 中以倒序、重复到达的方式应用并产出反向夹具,`yjs_reverse_interop` 回归读入。协议变更时两份夹具必须一起重新生成。
- **偏移单位统一为 UTF-16**:Yrs 显式配置 `OffsetKind::Utf16`,与 Y.Text 对齐。编辑器范围一律是 UTF-16,但已提交编辑的起止必须落在扩展字素边界上,不得切开代理对或用户可见字素。
- **LF 是唯一规范换行。** 首次外部导入时的 CRLF 正规化须明确记录(主规范 §3)。
- 每个活副本使用新的随机 u32 client ID,加载时拒绝复用;`skip_gc=true` 保留因果状态。

## 放弃的方案

旧文档未记录当时比较过的其他 CRDT 库或内核语言。选择依据只记录了正面理由:Yjs 的 update 支持重复、乱序应用与 state vector 增量补齐;Yrs 以兼容 Yjs 协议为目标并提供 FFI(主规范 §6.1)。

旧文档里唯一成文的反向结论是:ESP32 不能预先假定可运行完整 Yrs,但“不在 macOS 首版强行实现第二套自制 CRDT”——受限设备走代理或完整内核,待硬件 PoC 后再定(主规范 §6.4)。

## 后果

得到的:

- 桌面宿主、插件后台、将来的 iOS 共用同一份合并语义;反目标“iOS 与桌面的 CRDT 实现分叉”在源头上被堵住(设计 §2)。
- 服务端可以用成熟的 Yjs 解码做轻量结构校验,不必自写二进制解析。

付出的:

- **两种语言各持一份线格式实现**(Rust 的 Yrs、TypeScript 的 Yjs)。任何一侧升级都可能静默改变编码,所以版本必须精确锁定,升级 Yrs 或 Yjs 都是一次协议级变更:重生成两份夹具、全部客户端与服务一起过互操作测试。
- **UTF-16 是对 Rust 不友好的约定。** Rust 侧到处要显式换算,GTK 的字符偏移也要严格转换(Omarchy 原生规范);ESP32 的 Draftor 是 UTF-8 字节定位,接入需要绑定 revision 的 UTF-8↔UTF-16↔字素三重映射(主规范 §6.4)。
- **历史只增不减。** `skip_gc=true` 加上不可变时间事件,当前没有压缩协议;本机 checkpoint 只清理 SQLite delta 尾部,不清 Yrs 内部 tombstone。正文上限 1,000,000 个 UTF-16 单元,但二进制状态与事件数要另行用真实输入实测;短正文不代表小历史(`WIRE.md`)。P0 实测 10 万次逐键输入产生约 13.26 MB(主规范 §6.2)。
- iOS 要经 FFI 使用这套内核,构建成本记在 [0010](0010-ios-uikit-textkit2-uniffi.md)。

## 来源

- 主规范 §1、§3、§5.3、§6.1、§6.2、§6.4:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md
- macOS 实施计划(`write-core/` 职责、跨语言与行身份门禁):https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/plans/2026-11-07-immersive-write-macos.md
- 内核说明与线格式:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md 、https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/WIRE.md
- Yrs 版本锁定:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/Cargo.toml
- UTF-16 与 `skip_gc` 配置:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/document.rs
- 互操作夹具与测试:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/tests/fixtures/yrs-v1.json 、https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/tests/document.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/scripts/interop.mjs
- Yjs 13.6.33 锁定:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/package.json
- GTK 偏移换算:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-10-sumi-omarchy-native.md
