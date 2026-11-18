# 0004 同步服务用 Cloudflare Worker + Durable Object + R2,私有单用户、配对码接入

类型:补记
状态:已采纳;现行于基线 v6.1117.1 的 `write-sync-worker` 与桌面插件后台。
记录日期:2026-11-18;决定出处为主规范 §6 与同步服务 README。

## 背景

首版必须支持同页跨设备并发编辑与离线重连自动合并(主规范 §1)。需要一个只同步纸页及必要元数据、不上传整个 vault 的独立服务;它要给出“已可靠保存”的确认、能从备份恢复,并且由一个人自己运维。

## 决定

- **形态**:Cloudflare Worker 处理鉴权、HTTP API 与 WebSocket 升级;每个写作空间对应一个 SQLite Durable Object(`SumiSpace`),页面目录、删除状态与增量在同一串行边界内落盘;R2(`sumi-sync-backups`)保存冻结版本的分段增量与校验清单,不在逐键同步路径上。WebSocket 使用 hibernation,重唤醒从持久库恢复。
- **服务端不物化整页**:P0 容量测试后,DO 改为不可变增量日志中转,不在 DO 内构造整页 Y.Doc;完整候选文档的语义校验由客户端 Rust 完成,服务端只做鉴权、页身份、世代、包结构、配额与轻量因果索引校验。
- **私有、单用户、多设备,无公开注册**:没有匿名页面端点。首台设备由部署管理员用 `PROVISION_KEY` 调 `POST /admin/provision` 开通;已配对设备调 `POST /v1/pair` 生成**一次性、300 秒有效**的邀请(256 位随机密钥 + 绑定空间的 HMAC),新设备经 `POST /v1/pair/redeem` 兑换自己的设备凭据。
- **令牌**:设备用长期凭据调 `POST /v1/token` 换取**900 秒**有效的访问令牌;服务端只存设备密钥的 SHA-256。设备可列举与撤销,撤销同时作废其令牌、活动连接与它签发的邀请。
- 管理密钥与签名密钥只在服务端;配对界面不出现管理密钥。首版是 TLS 传输加云端受控存储,**不宣称端到端加密**。

## 放弃的方案

旧文档记录的:

- **浏览器账号登录**:曾是待定首版方案,后被单人空间的设备配对取代,列为后续独立扩展(主规范 §6.3)。
- **在 DO 内构造整页 Y.Doc**:初版做法,P0 容量测试暴露 DO 内存风险后改为日志中转(主规范 §6.1、§6.2)。
- **KV 作实时正文权威库**:明确不用(主规范 §6.1)。
- **每页一组微服务**:初版按个人空间设计,接受热点边界,不提前拆分(主规范 §6.1)。

旧文档未记录与 Cloudflare 以外的托管方案(自建服务器、其他云)做过比较。

## 后果

得到的:

- 每个空间一个串行协调点,目录与增量的一致性不需要分布式锁。
- 没有注册、没有密码,攻击面小;运维只是一个 Worker 与一个 R2 桶。

付出的:

- **平台锁定在 Cloudflare 的 DO 语义上**(SQLite DO、hibernation、单行/BLOB 限额)。迁到别处等于重写服务端。
- **硬限额**:单增量原始包最多 16 MB,空间增量日志配额 64 MB,客户端一次完整回放最多 65 MB(主规范 §6.2);超额时只能保留本机待同步内容。这些数字需要上线前用真实负载再定。
- **客户端负担更重**:服务端不验证整页语义,非法操作要靠客户端检测后隔离并 `resync_required`;state vector 目前只是客户端提示,重连回放的是固定版本的完整日志。
- **单用户是部署形态的代价**:任何一台已配对设备都被信任管理整个空间;首台设备开通需要能接触管理密钥的人。公开发行要补的身份层见 [0011](0011-ios-personal-use-identity-layer.md)。
- 计费随消息数、活跃时间、SQLite 写入与 R2 请求增长;用户没有授权 Workers 付费升级(主规范 §11),不能承诺免费或固定成本。
- 邀请 5 分钟过期、256 位密钥不适合手输,决定了 iOS 第一阶段的配对方式(设计 §10.1)。

## 来源

- 主规范 §1、§6.1–§6.3、§11:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md
- 同步服务接口与运维:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md
- 时限常量 `authSeconds: 900`、`invitationSeconds: 300` 与各项限额:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/src/protocol.ts
- DO 与 R2 绑定:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/wrangler.toml
- 设计 §10.1(邀请文本配对):note.md 源仓库 `docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md`(尚未提交到任何 tag,见报告)
