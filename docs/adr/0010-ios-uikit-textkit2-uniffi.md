# 0010 iOS 用 UIKit UITextView + TextKit 2 做编辑面,经 UniFFI 调用 Rust 内核

类型:新
状态:已决定(第 0 期);第 4 期 M0 验证这条路线能否成立。
记录日期:2026-11-18;出处为抽离设计 §4.4、§10.2、§10.3。归属标注沿用设计原文:**[用户定]** 是用户明确选择的,**[我的判断]** 是设计者补全、用户可推翻的。

## 背景

桌面的文档语义全在 Rust 内核 `write-core`:Yrs CRDT、行时间、三方合并、SourceMap、候选会话(见 [0001](0001-rust-core-yrs-yjs-v1.md)、[0002](0002-single-ytext-line-time.md))。iOS 版必须与桌面同页并发编辑并字节级一致(设计 §10.1)。编辑面又要满足与桌面相同的体验约束:系统输入法正常组字、选词,自绘光标,正文避让键盘(设计 §10.1;[0005](0005-native-text-controls.md) 在桌面上的同类决定)。

## 决定

- **Swift 原生界面 + Rust 内核** **[用户定]**(设计 §4.4)。
- 分层(设计 §10.2):
  - SwiftUI 外壳:纸页概览、设置、配对。
  - UIKit 编辑面:`UITextView` + TextKit 2,自绘光标。
  - Swift 薄适配层:把 UIKit 回调转成会话调用,读写钥匙串。
  - UniFFI 边界。
  - Rust:`session`(单一编辑 owner、组字期间暂缓远端更新、本机输入日志、崩溃恢复、同步协调与同步客户端)与 `core`(文档、SourceMap、存储、候选会话)。
- 内核编成 XCFramework,经 UniFFI 生成 Swift 接口。**编辑事务形状与桌面原生桥一致**:原生回调带修订号和可见 UTF-16 范围,由内核做最小的规范 Markdown 事务(内核 README 第 9 行的既有规定)。
- 组字中的文字不进 CRDT,组字期间到达的远端更新先暂存(内核 README 既有规定,iOS 照做)。持久化在后台线程,输入线程不等锁。
- 会话不在 Swift 里重写 **[我的判断]**,理由与切分见 [0012](0012-shared-session-module.md)。
- 最低系统 iOS 17 / iPadOS 17 **[我的判断]**:TextKit 2 在该版本上足够稳定,自用场景不需照顾旧设备。
- 第一个里程碑 M0 只验证 FFI:XCFramework 构建,Swift 侧加载现有互操作夹具,往返结果须与 Rust 测试一致;不成立就回到设计 §4.4 重选(设计 §10.3)。

## 放弃的方案

设计 §4.4 记录的:

- **纯 Swift 重写内核**:少一层 FFI;但两套实现要永远对齐,风险最高。
- **Tauri Mobile 等跨平台壳**:已排除——不是原生,IME 和键盘避让做不好。

设计未记录在 UIKit 编辑面与 SwiftUI `TextEditor`、第三方 iOS 文本控件之间做过比较;未记录比较 UniFFI 与手写 C ABI 或其他绑定生成器。

## 后果

得到的:

- CRDT、行时间、三方合并只有一份实现;iOS 与桌面用同一组互操作夹具(`write-core/tests/fixtures/`)验收。
- 编辑事务接口与桌面原生桥同形,规范只写一次。

付出的:

- **FFI 构建成本**(设计 §4.4 只写了“多一层 FFI”;下面的构建与测试成本是本 ADR 补充,设计未提及):每次内核或会话改动都要重新交叉编译 iOS 设备与模拟器目标、打 XCFramework、重新生成 Swift 绑定;CI 要多一条 Apple 工具链流水线。UniFFI 的类型映射、错误与回调线程模型都要专门测试,崩溃栈跨两种语言。
- **UTF-16 与字素边界在 Swift 侧再验证一次**(本 ADR 补充,设计未提及):内核要求编辑落在扩展字素边界,UIKit 给的是 `NSRange`(UTF-16);转换错误会被内核拒绝,表现为输入丢字,必须用中英文与 emoji 真机测(M1)。
- **TLS 根证书要换**(设计 §10.2):插件后台的 WebSocket 用 `tokio-tungstenite` 的 `rustls-tls-native-roots`(`plugins-src/write/backend/Cargo.toml`)。这套根证书加载方式在 iOS 上很可能不可用,**未实测**;会话下沉时要换证书校验方式,具体换成什么 `[未定]`。
- **抬高设备门槛**:iOS 17 以下的设备不能用;这是设计者判断,用户可推翻。
- **自绘光标与 TextKit 2 的组合在 iOS 上没有先例证据**(本 ADR 补充,设计未提及):桌面 macOS 抑制系统细线的做法用的是 AppKit API,不能直接搬;M1 的真机验证是这条路线的第二道关。
- 若 M0 失败,§4.4 的用户选择需要重新决定,第 4 期的排期随之推迟。

## 来源

- 抽离设计 §4.4、§10.1、§10.2、§10.3:note.md 源仓库 `docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md`(note.md 仓库 `docs/sumiwrite-extraction` 分支,提交 `0c11629f`;该分支尚未推送到任何远端,暂不公开,见 [04-known-gaps §2.2](../handoff/04-known-gaps.md))
- 编辑事务与组字规定:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md
- 互操作夹具:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/tests/fixtures/yrs-v1.json
- WebSocket 与 TLS 依赖:https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/Cargo.toml
