# 0003 便携文件是 YAML 头 + Markdown 正文 + JSON sidecar;完整历史在 SQLite

类型:补记
状态:已采纳;现行于基线 v6.1117.1 的 `write-core` 与桌面插件后台。
记录日期:2026-11-18;布局由用户确认(主规范 §5.2 标“用户已确认”),持久化契约见主规范 §5.2.3。

## 背景

纸页要同时满足三件事:在 note.md 和任何编辑器里都是一篇可读的普通 Markdown;带着行时间可以迁移;离线编辑和崩溃后不丢字、能继续与其他设备合并。一份文件做不到全部:能完整恢复离线同步上下文的是 CRDT 因果状态,它既不可读也不小。

## 决定

- **便携文件对**:`<名>.writing.md` 是一个小 YAML 头(`type: Writing Page`、`write_schema: 1`、`page_id`、`write_epoch`、`write_metadata: sidecar-v1`)加原样 Markdown 正文;同目录 `<名>.writing.meta.json` 保存逐行哈希、first/last 时间与来源。两者以 `page_id`、epoch、正文哈希配对,不靠文件名认定同一页。
- **完整 CRDT 历史只在 SQLite**:客户端 SQLite(WAL、`synchronous=FULL`)保存 checkpoint、按 revision 连续的 delta、未确认 outbox、远端 inbox、去重收据与投影基线。这不是可随意删除的缓存。两份便携文件不替代它。
- 投影只从已提交状态生成;文件写入与 SQLite 提交分别报告(`Committed` 与 `Saved`)。
- 迁移能力分层:只有 MD 可恢复正文身份;MD + 匹配 sidecar 还可恢复行时间快照;只有一致的数据库状态才能恢复完整离线同步上下文。裸文件恢复一律建新 UUID、epoch 1。

文件在 vault 里放在哪,是桌面投影的事,见 [0009](0009-page-store-vs-vault-projection.md)。

## 放弃的方案

旧文档记录的被否决方案:

- **尾部 HTML 注释内的 YAML 行表**(把行表追加在正文末尾)。这是 sidecar 之前的草案,被用户确认的 sidecar 布局取代(主规范 §5.2)。旧文档没有为它单列否决理由;同节的一般性分析是:行内、尾部或 sidecar 的差别主要落在文件体积、解析/投影、工具兼容和恢复流程上,不改变 CRDT 正文(主规范 §5.2.2)。
- **逐行内嵌时间注释**:因破坏 CommonMark 围栏、硬换行与块结构而否决,详见 [0002](0002-single-ytext-line-time.md)。
- **把全部时间嵌入单个 Markdown 的另一套格式**:首版明确不支持;保留行时间的迁移用同一 revision 的 MD + sidecar ZIP 归档(主规范 §5.2.3)。

## 后果

得到的:

- 正文对外部工具完全透明;note.md 的 Source 模式、grep、git 看到的都是用户写的字。
- 行时间可以随文件对迁移,又不进入可编辑正文。

付出的:

- **两个文件没有跨文件原子性。** 两次 rename 不构成事务;投影器必须串行写、校验配对、记录完成日志,并处理 sidecar 迟到、缺失、孤儿、哈希失配与复制别名等状态(主规范 §5.2.3、§7)。这部分代码与测试是桌面投影里最重的一块。
- **SQLite 是事实源,意味着它丢了就只能降级恢复。** 复制目录里的两个活动文件不是一致性备份;只靠文件对无法继续原页的离线合并。
- **Vault 传输工具不懂配对。** Git、iCloud 之类把两个文件各自 LWW 或文本合并,不等于 CRDT 合并;规范要求优先让同步服务承担实时同步,vault 传输只作归档,无法排除时走三方导入(主规范 §7)。
- sidecar 在文件树、搜索、索引和分享里的隐藏规则必须由宿主显式实现,不能假定 `.json` 会被自动忽略。
- 持久化耐久性以 WAL + `synchronous=FULL` 为起点,进程崩溃与断电要分别验证,不能超出实测范围承诺零损失。

## 来源

- 主规范 §0、§5.2、§5.2.1–§5.2.3、§7:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md
- 便携文件与 SQLite 的分工:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md
- sidecar 是物化快照而非第二真相:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/WIRE.md
- WAL 与 `synchronous=FULL`:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/storage.rs
- 投影与三方导入:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/projection.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/import.rs
