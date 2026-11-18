# 01 · 纸页与存储

本文件定义纸页是什么、怎样排序和导航、新建与删除的规则、以及本机如何保存。状态标签与证据的读法见 [00-product.md](00-product.md#读法)。

**两层存储**:纸页存储和 vault 投影是两层,不能混为一谈。

- **纸页存储**:每个客户端都有,本机事实源是内核 SQLite。本文件只讲这一层。
- **vault 投影**:只属于桌面插件,见本文 §4.2 和 [platform/notemd-desktop.md](platform/notemd-desktop.md)。

## 1. 纸页模型

### 1.1 身份与摘要

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/catalog.rs?plain=1#L70 · https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/contract.ts?plain=1#L53 · https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs?plain=1#L828 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L18

- **身份**:每页的身份是一个随机 UUID。
  - 这个 UUID 由发起新建的客户端生成,同时用作这次新建的幂等请求号,见 §3.1。
  - 身份不含日期,不随正文变化。
- **没有文件名概念**:总览、翻页和界面文案里只出现摘要,从不出现文件名或日期。磁盘上的文件名只是 vault 投影的派生物,见 [platform/notemd-desktop.md](platform/notemd-desktop.md)。
- **摘要**:取正文前 80 个字符,去掉首尾空白,随正文变化。正文为空时显示“空白的一页”。
- **身份之外的页状态**:每页还有三项状态,都和正文分开存放:
  - `epoch`:身份纪元
  - `generation`:生命周期代际,见 §3.3
  - 顺序锚点:见 §2.1

  正文、页身份和行时间的共享结构见 [02-markdown-and-line-time.md](02-markdown-and-line-time.md)。

### 1.2 设备本地状态不共享

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/catalog.rs?plain=1#L39 · https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs?plain=1#L859 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L18

以下状态只属于本机,不随纸页同步:

- 光标、滚动位置、窗口尺寸、键盘高度
- 当前页 `activePage`
- 显示偏好:主题、字体、字号、行距、宽度、底部留白、光标动效

本机偏好存在 SQLite 的 `sumi_preferences` 表。

## 2. 顺序与导航

### 2.1 顺序键

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/catalog.rs?plain=1#L48 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md?plain=1#L23 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

**新建时**:新页以当前页为锚点(`after_id`)插入。没有当前页时,锚点为空,新页挂在根下。

**顺序的计算**:

- 每页的锚点就是它的顺序键。
- 全局顺序从根开始,按锚点深度优先展开。
- 同一锚点下有多个子页时,按页 UUID 的字典序排列。并发新建因此在所有设备上收敛到同一顺序,不需要协调。
- 已删除的页仍参与展开,只是不显示,所以删除不会打乱其后各页的顺序。
- 分批传输目录时,子页可能先于锚点到达。此时子页暂按确定顺序显示,等锚点到达后归位。

**注意**:同一锚点下已有子页时,新页不一定紧挨着当前页。是否紧挨着,由 UUID 排序决定。这一点与旧规范“插在当前页之后”的字面要求有出入,已记入 known-gaps。

### 2.2 上一页、下一页与总览

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs?plain=1#L3751 · https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/src/main.ts?plain=1#L264 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L16

**翻页**:

- 上一页、下一页只在未删除的页之间按 §2.1 的顺序移动。
- 在最后一页按“下一页”,会新建一张空白页,不做自动分页。
- 在第一页按“上一页”,停在当前页。

**切换的前提**:

- 正在输入法组字时不切换,当前编辑面还有未完成的保存时也不切换。这两种情况都会提示先完成输入。
- 另一个编辑面占用目标页时,也拒绝切换。

**总览**:

- 分“继续书写”和“废纸篓”两组,每组按 §2.1 的顺序列出摘要。
- 点击“继续书写”里的一项,打开该页。点击“废纸篓”里的一项,恢复该页。
- 每行的 × 把该页移到废纸篓。

总览是否分页加载:基线代码一次列出全部页,没有分页。[未定]

## 3. 新建、空白页与废纸篓

### 3.1 新建的幂等

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs?plain=1#L880 · https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs?plain=1#L3729 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L18

- **哪些操作会产生新页**:新建、“下一页”和删除。删除当前页且没有剩余页时会产生新页,见 §3.3。
- **请求号**:这些操作都必须带请求号 `requestId`(UUID)。新页的 UUID 就是这个请求号。
- **创建标记**:新页的头部记一个创建标记 `sumi_creation`,内容是 `{request_id, after_id, kind, owner}`。
- **重试**:用同一请求号重试时,宿主找到已提交的那一页直接返回,不会再建一页。即使当前页在此期间已经变化,也是如此。

### 3.2 空白页不生成文件

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/catalog.rs?plain=1#L24 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/catalog.rs?plain=1#L77 · https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs?plain=1#L2545 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

**“不落盘”的含义**:空白页不生成任何可见文件,但纸页存储里有它。

- **新建时**:
  - 纸页立即写入本机 SQLite 目录,并作为目录操作同步到服务端。
  - 此时首次书写日期和序号都为空,没有文件名,不产生投影文件。
- **首次写入非空内容时**:才确定首次书写日期和当日序号,从此有文件名,见 [03-sync.md](03-sync.md) §6。
- **一直没写的空白页**:留在总览里,显示为“空白的一页”,可以照常移到废纸篓。基线代码不会自动清理它。

### 3.3 废纸篓与恢复

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs?plain=1#L3757 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/catalog.rs?plain=1#L88 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/src/index.ts?plain=1#L460 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L18

**删除**:

- 删除是墓碑,不清除正文。删除使生命周期代际 `generation` 加一。
- 删除前的旧编辑带着旧代际,会被拒绝,不会让已删除的页复活。见 [03-sync.md](03-sync.md) §5。
- 删除当前页时,先确保目标页已在本机。目标页取其后第一张未删除页,没有就取其前一张,两者都没有就新建一张空白页。离线时如果目标页准备失败,当前页不删除。

**恢复**:恢复必须显式执行,同样使代际加一。

**重试与占用**:

- 删除和恢复的重试是幂等的,代际不会被推进两次。
- 另一个编辑面占用该页时,拒绝删除或恢复,草稿不会被自动丢弃。

**离线**:

- 离线时,删除和恢复进入本机目录发件箱,联网后按原 `opId` 提交。
- 本机还有未完成的删除或恢复时,服务端回来的旧状态不会覆盖本机的这次操作。

**永久清除与保留期**:基线代码里没有永久清除、清空废纸篓或到期自动清理。生产环境的 30 天是 R2 备份对象的生命周期,不是废纸篓的保留期,见 [03-sync.md](03-sync.md) §8.1。[未定]

## 4. 纸页存储

### 4.1 SQLite 是本机事实源

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/storage.rs?plain=1#L263 · https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/backend/src/durability.rs?plain=1#L602 · https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L162 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L56

**事实源**:本机的唯一事实源是内核的 SQLite 库。SQLite 以 WAL 模式运行,`synchronous=FULL`。库里保存:

- 每页的完整状态检查点(checkpoint)和按修订号连续的增量(`document_deltas`)
- 内容发件箱与收件箱
- 纸页目录(`sumi_catalog`)与目录发件箱
- 去重键
- 投影基线

**提交与确认**:

- 一次被接受的编辑,原子地追加:精确修订号的增量、发件箱或收件箱确认、目录与代际标记。
- 增量提交成功之前,编辑不算持久。

**检查点**:每页的检查点在以下两种情况之一发生时写入完整状态,并删掉已覆盖的增量:

- 最后一次输入后空闲 250 ms(工程细则)
- 连续有未保存修改满 2 s(工程细则)

**载入**:载入时读取检查点和连续的增量,一起重放。增量缺失或损坏,就拒绝载入,不猜测。

**归属与形态**:

- 桌面上,这个库归插件后台进程所有,宿主只持有即时内存副本。取舍见 [../adr/0006-plugin-backend-vs-host-session.md](../adr/0006-plugin-backend-vs-host-session.md)。
- 完整 CRDT 历史放在 SQLite,便携文件不能替代它。见 [../adr/0003-portable-files-and-sqlite-history.md](../adr/0003-portable-files-and-sqlite-history.md)。
- iOS 上,同一内核库放在应用沙盒内。[计划:iOS]

### 4.2 纸页存储与 vault 投影的分层

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-08-sumi-release.md?plain=1#L30 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L18

**纸页存储**:§4.1 所述,每个客户端都有。

**vault 投影**:

- 把已提交的状态写成 vault 里的一对便携文件。
- 外部对这对文件的修改,按投影基线做三方合并导入。
- 投影是可重建的派生物,不是事实源。
- 它只属于桌面插件:路径、命名、去抖与外部编辑合并,全部写在 [platform/notemd-desktop.md](platform/notemd-desktop.md)。分层理由见 [../adr/0009-page-store-vs-vault-projection.md](../adr/0009-page-store-vs-vault-projection.md)。

**便携文件格式**:与平台无关,见 [02-markdown-and-line-time.md](02-markdown-and-line-time.md) §2。

**iOS**:只有纸页存储,没有 vault 投影,改由系统分享导出 Markdown。[计划:iOS]

### 4.3 迁移层级与导出

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/export.rs?plain=1#L10 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L18

**能恢复到什么程度,取决于手里有什么**:

| 手里有的数据 | 能恢复的内容 |
|---|---|
| 只有 Markdown 文件 | 只恢复正文,不伪造时间 |
| Markdown 加上校验匹配的 sidecar | 同时恢复行身份和已知的首次、最后与来源值 |
| 完整的 SQLite 库 | 同时恢复同步上下文 |

**从便携文件恢复**:总是建一张**新的** UUID 页,`epoch` 为 1,不冒用原页身份。能从同步日志完整恢复 CRDT 时,应优先走那条路。

**导出**:有两种。

- **Markdown**:只含正文,不含身份头和逐行时间。
- **归档**:一个 ZIP,内含同一修订号的 `page.writing.md` 与 `page.writing.meta.json`。

导出会拒绝替换符号链接及其目标。

## 5. 本机正文优先与崩溃恢复

### 5.1 本机正文优先

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L146 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-09-sumi-local-safety-release.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs?plain=1#L840 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L49 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L28

**本机库可信,投影可重建**:

- 本机 CRDT 库是可信来源。
- 投影文件可能缺失、过期或冲突。此时:
  - 不阻止打开、阅读或续写一张已验证的本机纸页。
  - 已改动的外部文件受到保护,不被覆盖。
  - 用户可以选择“保留外部文件并重新写出此页”。

**一致的观察**:后台用同一个保存执行器,在同一个作业里观察正文、投影基线和那对文件,避免分开观察造成的竞态。

**保存状态**:分四档,本机保存和投影分开报告。

| 状态 | 含义 |
|---|---|
| `saving` | 本机保存中 |
| `saved` | 已保存 |
| `projection-pending` | 正文已保存,投影待完成 |
| `error` | 保存失败或有未持久草稿 |

冲突时不报告投影成功。

**同步状态**:另行显示,见 [03-sync.md](03-sync.md) §4.1。

### 5.2 输入保护日志

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/journal.rs?plain=1#L1 · https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/durability.rs?plain=1#L1 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L7

**先记日志,再确认**:宿主向编辑面确认一次输入之前,先把这次编辑同步提交到一个最小的本机输入保护日志。日志记录:

- 精确的操作身份
- 页、`epoch`、`generation` 和修订号
- 更新字节与摘要

**写盘方式**:

- 日志用 SQLite WAL 且 `synchronous=FULL`,每次提交在确认前落盘。
- 日志和检查点都请求最强的落盘保证,即 SQLite 的 `fullfsync` 与 `checkpoint_fullfsync`。这项设置在哪些平台上会连驱动器缓存一起刷写,见 [platform/notemd-desktop.md](platform/notemd-desktop.md)。

**回收与重放**:

- 只有拿到后台的持久回执后,日志条目才被回收。
- 重新打开时,先把日志幂等重放进纸页存储,再载入页面。

**互斥**:同一写作空间同时只允许一个宿主进程使用日志,另一进程会被拒绝。

**边界**:这不等于完整的历史撤销,也不承诺任何环境下绝对零丢失。没有做过物理断电实验。

### 5.3 写入失败与未持久草稿

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L146 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-09-sumi-local-safety-release.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L28

**日志写入失败时**:

- 不报告成功。
- 草稿保持可见,暂停编辑,允许复制。
- 明确告诉用户这段内容尚未保存。
- 重试沿用同一个操作 ID。

**不能绕过未持久的草稿**:关闭窗口、切换纸页、停用插件都不行。宿主会拒绝,或者要求先完成保存。

**来自同步的冲突**:不覆盖本机草稿,见 [03-sync.md](03-sync.md) §4.2。
