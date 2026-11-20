# 03 · 同步

本文件定义同步的现行规则,包括:

- 线格式
- 身份与配对
- 目录与幂等
- 并发与离线合并
- 代际
- 首次书写日期与序号
- 隔离与恢复
- 运维与备份

状态标签与证据的读法见 [00-product.md](00-product.md#读法)。

**接口细节以同步服务 README 为准**:各端点的请求和应答字段、WebSocket 消息、超时与重试预算都写在那里,本文不重复抄录。

- README 链接:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md
- 选型理由见 [../adr/0001-rust-core-yrs-yjs-v1.md](../adr/0001-rust-core-yrs-yjs-v1.md) 与 [../adr/0004-cloudflare-sync-private-pairing.md](../adr/0004-cloudflare-sync-private-pairing.md)。

## 1. 线格式

### 1.1 Yjs V1 更新

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/WIRE.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L183 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

**格式与版本**:

- 线上传输的是 Yjs update V1 与 state-vector V1。
- 内核用 Yrs,版本锁定 0.24.0。
- 与 Yjs 13.6.33 做互操作测试:Rust 生成的夹具在 Yjs 中以逆序、重复到达的方式回放,验证结果一致。

**每页一个文档,有三个共享根**:

| 根 | 类型 | 内容 |
|---|---|---|
| `page` | Y.Map | `schema: 1`、UUID `page_id`、正整数 `epoch`、UUID `root_line_id`。同一 epoch 内身份不可改 |
| `body` | Y.Text | 只含规范的 LF Markdown。每个 LF 带属性 `next_line_id`,指向下一行的身份 |
| `timing` | Y.Map | 键是 UUID,值是不可变的时间事件。任何更新都不得删除或覆盖已有事件 |

`timing` 事件的语义见 [02-markdown-and-line-time.md](02-markdown-and-line-time.md) §3。

**客户端 ID**:每个活副本使用新的 32 位客户端 ID,包括后台持久化副本。

- 载入时,拒绝已在状态中出现过的客户端 ID。
- 收到会推进本机活跃客户端 ID 的远端更新,视为 actor 冲突并拒绝。

### 1.2 服务端只做中继

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L32 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L34

**适用范围**:本节是服务端规则,与客户端平台无关。

**服务端的形态**:每个空间对应一个 Cloudflare Worker 后面的 SQLite Durable Object,外加 R2 备份。

**只做中继**:

- 服务端保存不可变的增量日志,并逐包做有界的线格式校验:
  - actor 时钟
  - 父链接
  - 受保护的 map 字段
  - 删除区间
- 服务端从不物化 Y.Doc。
- 正文、行与时间的完整语义,由客户端负责校验。

**确认的含义**:更新的确认(ack)表示“这段不透明字节及其操作身份已持久保存”,不表示其因果依赖都已解决。依赖未解决的,确认里带 `validationPending`。

### 1.3 与内部协议 `sumi-protocol` 的区别

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/sumi-protocol/src/service.rs?plain=1#L5 · https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/sync.rs?plain=1#L671 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L56

**适用范围**:客户端这一侧,macOS 与 Linux 的插件带的是同一套后台代码。

**两套协议,互不相干**:

- `sumi-protocol` 是宿主与插件后台进程之间的内部契约:握手、能力、持久化回执,以及身份、邀请、令牌等共享类型。它**不是**同步线协议。内部契约见 [../handoff/03-notemd-contract.md](../handoff/03-notemd-contract.md) §1.4。
- 同步线协议有两部分:
  - HTTP 与 WebSocket 接口,由同步服务实现。
  - 客户端,即插件后台的 `sync.rs`。

**WebSocket 握手**:以 `hello` 开始,协议版本固定为 1,版本不符即断开。

## 2. 身份与凭据

### 2.1 空间、设备、凭据与纸页分层

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/sumi-protocol/src/sync.rs?plain=1#L6 · https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/sync.rs?plain=1#L62 · https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L112 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L24

**身份层与纸页数据分开**,包括:

- 同步服务地址
- 空间 ID
- 设备 ID
- 设备凭据

纸页、目录和正文都不含凭据。换一套身份,不改变纸页的身份。

**同步服务地址**:必须是 HTTPS 源,不带路径、查询串或内嵌凭据。只有测试可以用本机回环地址上的 HTTP。

**设备凭据**:

- 内容:一个 256 位随机秘密,加上一个与空间绑定的 HMAC 路由证明。服务端只保存它的 SHA-256。
- 存放:长期凭据只放在操作系统提供的安全存储里,不进 Markdown、sidecar、日志或插件包。各平台用哪种安全存储、条目叫什么,见 [platform/notemd-desktop.md](platform/notemd-desktop.md)。
- iOS 同样只放系统安全存储,见 [platform/ios.md](platform/ios.md)。[计划:iOS]

**身份由签名声明决定**:服务端根据签名声明确定空间,调用方自己填的身份头一律被替换。

**部署形态**:当前是私有、单用户、多设备。按设计 §10.4,规范把“单用户”写成当前部署形态,不写成协议假设。服务端文档的说法是:任何已配对设备都被信任来管理它所在的个人空间(README L14)。

### 2.2 令牌与吊销

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L11 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/src/protocol.ts?plain=1#L18

**适用范围**:本节是服务端规则,与客户端平台无关。令牌的获取与刷新,由两平台共用的插件后台完成。

**访问令牌**:

- 设备用 `{spaceId, deviceId, deviceSecret}` 换取短期访问令牌,有效期 900 秒(工程细则)。
- 每个新的 WebSocket 握手前,都先取一个新令牌。
- WebSocket 上令牌过期时,以 `4001 token_expired` 关闭。

**吊销**:

- 吊销一台设备,会同时吊销它的令牌刷新、访问令牌、活跃连接,以及它发出、尚未使用的邀请。
- 每个 HTTP 请求和每条 WebSocket 消息都检查是否已吊销,单凭签名令牌不能绕过。

**有界计数**:认证尝试次数,以及设备、邀请、连接的数量都有上限,见 §8.2。

### 2.3 配对流程与时限

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L13 · https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/main.ts?plain=1#L486 · https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L183

**适用范围**:邀请的格式、时限与兑换都是服务端规则,与客户端平台无关。客户端加入的流程见第 3 步的单独标签。

**没有公开注册**:没有公开注册,也没有匿名的纸页端点。

**流程分四步**:

1. **首台设备**:由部署工具用管理员密钥开通,得到第一套设备凭据。
   - 管理员密钥只在服务端和部署者本机,从不出现在配对界面、宿主偏好、Markdown、sidecar、插件包或邀请里。
   - 签名密钥也只在服务端。
2. **生成邀请**:已配对的设备生成邀请。
   - 邀请内容是 `{spaceId, code, expiresAt}`:含 256 位随机秘密和与空间绑定的 HMAC。
   - 邀请只能用一次,有效期 300 秒(工程细则)。
   - 已配对设备的设置里提供生成邀请的入口,把邀请文本显示出来供复制。界面细节见 [platform/notemd-desktop.md](platform/notemd-desktop.md)。
3. **加入**:新设备填入两项,然后兑换邀请,得到与首台设备同样结构的凭据包。客户端加入的真实验收只在 macOS 上做过,证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L183。Linux 共用同一配对界面与后台代码,但没有真实配对的验收记录。[已交付:macOS]
   - 同步服务地址
   - 邀请文本
4. **设备管理**:设备列表可以查看;吊销即时生效,见 §2.2。

**约束**:

- 开通首台设备的那台机器,在它发出的邀请被兑换之前,必须保持有效。吊销一台设备会连带吊销它的邀请。
- 扫码配对不在现行范围内。

**iOS**:用粘贴邀请文本加填写服务地址的方式加入,见 [platform/ios.md](platform/ios.md)。[计划:iOS]

## 3. 纸页目录与操作幂等

### 3.1 目录

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L22 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/catalog.rs?plain=1#L109 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

**服务端目录是只追加的变更流**:

- 带游标,可以分页拉取。
- 含墓碑。
- 每项记录:
  - 页 UUID
  - `epoch`、`generation`
  - 是否已删除
  - 首次书写日期与序号
  - 顺序锚点 `after_id`
  - 版本

**顺序**:按 [01-pages-and-storage.md](01-pages-and-storage.md) §2.1 计算。离线新建的页,必须在它锚点所在的那次新建之后提交。

**新建**:新建空白页时,首次书写日期为空,见 §6。

**合并到本机**:客户端把远端目录合并进本机目录时,遵守两条:

- 不丢弃本机尚未提交的删除或恢复操作。
- 远端代际比本机旧时,保留本机状态。

### 3.2 `opId` 幂等

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/src/index.ts?plain=1#L343 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/catalog.rs?plain=1#L66 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

**所有写操作都带 `opId`**,包括新建、删除、恢复和内容更新。

- 同一设备的 `opId` 必须唯一,并且在重试时保持不变。
- 服务端按“设备 + `opId`”记住请求指纹和应答。
  - 用原 `opId` 原样重试,得到原应答。
  - 用同一个 `opId` 发不同的内容,返回 409 `operation_id_reused`。

**离线与超时**:

- 离线时,目录操作进入本机目录发件箱,内容更新进入本机内容发件箱,联网后按原 `opId` 提交。
- 超时不代表没有提交。重试必须沿用同一个 `opId` 和完全相同的负载。

**和宿主请求号的区别**:宿主的新建请求号 `requestId` 是另一层的幂等,保证同一次新建只产生一张页,见 [01-pages-and-storage.md](01-pages-and-storage.md) §3.1。

## 4. 并发与离线合并

### 4.1 本机先持久,再发送

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs?plain=1#L834 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L18

**发出的时机**:客户端先把编辑持久化到本机,见 [01-pages-and-storage.md](01-pages-and-storage.md) §5。持久化之后,编辑才从发件箱发出。

**收到的时机**:远端更新先持久进收件箱,再合并进编辑会话。

**界面**:同步状态与本机保存状态分开显示。同步状态包括:

- 是否已连接
- 待发送数量
- 离线时显示“本机写作”

离线不影响本机写作。

### 4.2 合并语义

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-08-sumi-release.md?plain=1#L42 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L183 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L65

**自动合并**:同一页上多台设备的并发编辑和离线编辑,经 CRDT 自动合并,所有文字都保留。这里不用整篇后写覆盖,也不用单写者锁。

**组字与撤销**:

- 输入法组字期间到达的远端更新,先持久排队,组字提交后再合并。
- 撤销/重做只撤本设备自己的操作,保留远端文字。

**过期结果不覆盖新输入**:远端合并结果在后台算好,提交前要核对四项:

- 修订号
- 页与 `epoch`
- 因果状态
- 活跃 actor

结果已过期就丢弃重算,绝不覆盖新打的字。

**冲突不丢草稿**:服务端以 409 拒绝时,客户端必须保留本机草稿,不得覆盖。拒绝的原因包括:

- 状态冲突
- 代际冲突
- epoch 冲突

**跨平台验证的范围**:本节的合并语义在两平台共用的内核里实现,Linux 上内核测试通过(见状态行)。

- 跨设备真实远端合并(包括组字期间收到远端更新、撤销保留远端文字)只在 macOS 发布验收中核对过,证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-08-sumi-release.md?plain=1#L42。[已交付:macOS]
- Linux 只有共用代码与自动化测试,没有跨设备生产联调,原话是“远端投影及同步内核测试不等同于跨设备生产联调”,见 https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L65。已记入 known-gaps。

### 4.3 重连回放

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L28 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L48

**适用范围**:服务端规则与客户端平台无关;客户端一侧由 macOS 与 Linux 共用的插件后台实现。Linux 侧没有跨设备生产联调,见 §4.2。

**回放什么**:重连或首次拉取一页时,服务端按 `journal-v1` 格式分块回放这一页的增量日志。

**冻结的参数**:第一次应答冻结三项参数,后续请求必须原样回传:

- 日志版本
- 代际
- 隔离修订号

**校验与合并**:每块都带哈希。所有块收齐并校验无误之后,才合并。

**重新开始的条件**:

- 中途中断,就丢弃不完整的传输,从头回放。
- 代际或隔离修订号变化,也要从头回放。

**状态向量**:服务端不发布权威的 CRDT 状态向量。客户端提交的状态向量只做校验;v1 为了正确性,总是回放完整日志。

## 5. 代际与删除恢复

### 5.1 代际

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/src/index.ts?plain=1#L402 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/src/index.ts?plain=1#L460 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/catalog.rs?plain=1#L88 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

**适用范围**:服务端规则与客户端平台无关;客户端一侧的代际处理在两平台共用的内核目录里。

**代际怎样变化**:每页有生命周期代际 `generation`,删除和恢复各使它加一。

- 本机执行删除或恢复时,也立即加一,让这一转换之前的编辑立刻可区分。
- 请求里记录的是转换前的预期值。

**内容更新**:必须同时带上与服务端一致的 `epoch` 与 `generation`,否则被拒绝:

| 情况 | 应答 |
|---|---|
| 页已删除 | 409 `page_deleted` |
| `epoch` 不符 | 409 `epoch_mismatch` |
| 代际不符 | 409 `generation_mismatch` |

离线写下的旧编辑因此不会让已删除的页复活。

**删除与恢复本身**:也要带预期代际。代际不符,或者状态本来就是目标状态,返回 409 `invalid_lifecycle_transition`。重试幂等,见 §3.2。

**epoch**:同一页的 `epoch` 变化,需要走恢复流程。从便携文件恢复时,总是新建一张 UUID 页,见 [01-pages-and-storage.md](01-pages-and-storage.md) §4.3。

## 6. 首次书写日期与文件序号

### 6.1 分配规则

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/src/index.ts?plain=1#L420 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/catalog.rs?plain=1#L77 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

**适用范围**:服务端规则与客户端平台无关;客户端一侧的暂定与改号在两平台共用的内核目录里。

**新建的空白页**:首次书写日期和序号都为空,没有文件名。

**首次写入非空内容时**:

- 第一个含非空内容的更新,必须带 `firstWriteDate`,格式为 `YYYY-MM-DD`。取值是发起设备在首次有效输入时的本地日期。
- 服务端在同一个事务里原子地确定日期,并分配当日序号:当日最大序号加一。

**分配之后的约束**:

- 多台设备并发首写时,以服务端先接受的那个日期为准。
- 此后不再改名。
- 序号把已删除的页也计算在内,永不复用。
- 文件名为 `<日期>-<序号>.writing.md`,序号至少两位并补零,超过 99 继续增长,不截断。

**离线首写**:

- 本机先按同样规则暂定日期与序号。
- 服务端确认的序号与本机暂定的冲突时,本机把尚未被服务端确认的那一页改到下一个可用序号,并重新写出投影。
- 已被服务端确认的页之间发生冲突,视为错误,不自动处理。

文件名只在桌面归档投影里使用,见 [platform/notemd-desktop.md](platform/notemd-desktop.md)。

## 7. 隔离与恢复

### 7.1 隔离

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L34 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/src/index.ts?plain=1#L413 · https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/coordinator.rs?plain=1#L555

**适用范围**:服务端规则与客户端平台无关;客户端一侧由 macOS 与 Linux 共用的插件后台实现。Linux 侧没有跨设备生产联调,见 §4.2。

**直接无效的操作**:当前就能判定无效的操作,直接回滚,不入日志。

**事后被证明无效的操作**:一个先前处于待定状态的操作,可能被后到的合法依赖证明为无效。此时服务端:

- 隔离那个先前的操作,保留合法依赖。
- 提升该页的隔离修订号。
- 广播 `resync_required`。

此后回放不再包含被隔离的记录。

**已连接的客户端**:收到 `resync_required` 后,必须做到以下几点:

- 停止合并这一页。
- 保留本机草稿。
- 不得用覆盖 Markdown 的方式去清除可疑内容。

**未定事项**:“从干净日志重建,再重放本机发件箱”这条恢复路径,在基线上还没有实现。被隔离的页目前只能停在“停止合并、保留草稿”的状态。[未定]

### 7.2 空间恢复

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L10 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/CLOUD-ACCEPTANCE.md?plain=1#L26

**适用范围**:本节是服务端规则,与客户端平台无关。

**从备份恢复**:由管理员执行。它总是:

- 新建一个空间,不覆盖原空间。
- 不复活原空间的凭据。

客户端要显式与替换后的空间重新配对。

**恢复前的校验**:

- manifest
- 分段的名称、顺序、大小和哈希
- 记录分帧
- 线格式身份
- 目录锚点

任一失败就清掉未开通的日志,同一个暂存空间可以重试。

**不备份的内容**:设备秘密不进备份。

## 8. 运维与备份

### 8.1 备份

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L56 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/CLOUD-ACCEPTANCE.md

**适用范围**:本节是服务端规则,与客户端平台无关。

**做法**:

- 在某一修订号冻结日志与目录。
- 把日志切成不可变分段上传 R2,最后写 schema 2 的 manifest。每个分段有自己的 SHA-256。
- 所有对象都成功之后,才更新“上次备份”。
- 失败的上传保留冻结作业,重启后续传同样的对象键。
- 同时只有一个待办作业。
- 等待 R2 网络期间,编辑照常进行。

**节奏与保留**:

- 新建页或有内容更新后,自动排程;此后每天一次(工程细则)。
- 生产环境给 R2 设 30 天生命周期规则(工程细则)。

**验收状态**:2026-11-07 的云端验收已通过,其中包括冻结的 R2 备份恢复到一个凭据隔离的新空间。但 README 仍把“已部署环境的恢复演练”列为验收门槛。两者的关系见 known-gaps。

### 8.2 限额

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/src/protocol.ts?plain=1#L3 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L38

**适用范围**:本节是服务端规则,与客户端平台无关。客户端回放与正文上限由两平台共用的插件后台和内核强制。

下列上限全部是工程细则。超限时明确拒绝,不截断历史。

| 项 | 上限 |
|---|---|
| 单个 HTTP 更新(原始字节) | 16 MB(工程细则) |
| 单个 HTTP JSON 请求 | 24 MB(工程细则) |
| 单个 WebSocket 更新(原始字节) | 256 KB(工程细则) |
| 单条 WebSocket 消息 | 400 KB(工程细则) |
| 回放分块 | 64 KB(工程细则) |
| 单包 struct 数 | 500,000(工程细则) |
| 每空间原始日志总量 | 64 MB(工程细则) |
| 每空间页数 | 1000(工程细则) |
| 记住的操作数 | 200,000(工程细则) |
| 设备 / 连接 / 订阅 | 32 / 16 / 8(工程细则) |
| 客户端回放(含分帧) | 65 MB(工程细则) |
| 正文 | 1,000,000 个 UTF-16 单元,由内核强制(工程细则) |

### 8.3 部署形态

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L62 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/CLOUD-ACCEPTANCE.md

**适用范围**:本节是服务端规则,与客户端平台无关。

**定位**:

- 同步服务是本产品专用的私有服务,只同步纸页及必需的元数据,不同步 vault。
- 生产访问一律走 HTTPS/WSS。
- 服务不是端到端加密的,产品也不作这样的宣称。

**部署工具**:按固定顺序运行,从不打印秘密值:

1. preflight
2. prepare
3. bucket
4. deploy
5. secrets
6. retention
7. verify
8. verify-source

**额度**:服务运行在共享的 Cloudflare 免费额度上,分组索引并不能让额度变成无限。

**每次部署都要有验收证据**:代码部署成功、匿名健康检查通过,都不能证明服务已经可用。以下三项必须各有明确的验收证据:

- 开通首台设备
- 真实网络性能
- 生产恢复

**可移植性**:服务端换实现或换部署方式时,线格式(§1)和接口(README)保持不变。部署细节的归属见 [../handoff/01-inventory.md](../handoff/01-inventory.md)。[未定]
