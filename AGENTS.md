# AGENTS.md

给在本仓库工作的 agent 的规程入口。人确认后生效;agent 可以提议修改本文件,不可自行放宽。

1. **现行规范在 `docs/spec/`。** 改行为先改规范,再改实现;旧规范到新规范的去向见 `docs/spec/MAPPING.md`。
2. **边界归属。** 原生编辑桥、宿主内 Sumi 界面与适配、插件 SDK、签名与上架归 note.md,不在本仓库改。跨边界的改动先改 `docs/handoff/03-notemd-contract.md` 并升契约版本。
3. **状态与证据。** 规范每个小节必须有状态行;已交付必须带证据链接,写不出出处就标 `[未定]`,不要猜。提交前跑 `bash docs/check.sh`,必须输出 `OK`。
4. **红线。** iOS 与桌面共用同一套 Rust 内核与会话模块,不得在 Swift 里重写 CRDT、行时间、合并或恢复逻辑。
5. **凭据只放引用,不放秘密。** Bundle ID、签名身份、账号 ID、密钥一律只写引用位置。
6. **退役名称。** 退役名称不得作为现行行为出现在 `docs/spec/`;允许出现在 `docs/spec/MAPPING.md`、ADR 的「放弃的方案」段、以及 `docs/handoff/04-known-gaps.md` 的出入条目。退役名称与取代者的对照见 `docs/spec/MAPPING.md` 文末;`bash docs/check.sh check_retired` 扫描 `docs/spec/`(不含 `MAPPING.md`)、`docs/handoff/` 00–03、`README.md` 与本文件。
7. **改模块先跑模块测试。** 改了 `core/`、`protocol/`、`sync/` 里的任何文件,提交前跑该模块 README「Verification」段(`sync/` 为 README 开头)列出的测试命令,全部通过才提交;只改文档的提交跑 `bash docs/check.sh` 即可。

约定:文档用简体中文;提交信息用英文祈使句。
