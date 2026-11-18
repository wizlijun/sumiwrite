# 02 · Markdown 与行时间

本文件定义四件事:

- 正文以什么为准
- 富文本视图能编辑到什么程度
- 便携文件长什么样
- 逐行时间怎样记录

状态标签与证据的读法见 [00-product.md](00-product.md#读法)。

为什么用“单个 Y.Text 加不可变时间事件”,见 [../adr/0002-single-ytext-line-time.md](../adr/0002-single-ytext-line-time.md)。

## 1. 富文本与 Markdown 的边界

### 1.1 正文以 LF Markdown 为准

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/WIRE.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-08-sumi-release.md?plain=1#L29 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L28

- **权威是 Markdown 源码**:正文的唯一权威是以 LF 换行的 Markdown 源码。展示样式不作为 CRDT 文本格式存储。
- **视图之间的关系**:
  - 富文本视图只是源码的一种呈现,隐藏 YAML 头和各类 ID。
  - 源码(Source)视图展示完整源码。
- **编辑的落点**:
  - 富文本视图里的每次编辑,都换算成对源码的最小事务。
  - 区间一律用 UTF-16 偏移。
  - 提交的编辑必须起止于扩展字素簇边界,不拆代理对,不拆字素。
- **换行符**:
  - 正文里不允许出现 CR。
  - 外部文本含 CRLF 时,导入前必须显式规范化为 LF,否则拒绝导入。
- **剪贴板**:RTF/HTML 只作为剪贴板输入,先文本化,再转成 Markdown。复制输出 Markdown 纯文本。具体行为见 [04-editing-experience.md](04-editing-experience.md)。
- **输入法组字**:组字中的文本只存在于本机编辑面,不进入 CRDT,提交后才成为一次编辑。

### 1.2 富文本视图支持的语法

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/render.rs?plain=1#L56 · https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L180 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L28

富文本视图可以直接编辑以下语法:

- 段落、显式换行
- 标题(ATX 形式)
- 粗体、斜体、删除线
- 引用
- 简单列表
- 链接

### 1.3 不支持的块原样保留

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/render.rs?plain=1#L56 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

**哪些语法受保护**:

- 代码块、行内代码
- HTML 块与行内 HTML
- 表格
- 图片
- 脚注定义
- 分隔线
- Setext 形式的标题

**怎样保护**:这些片段在富文本视图里原样保留,并受保护。

- 可以选中,但不能就地改写。
- 要修改它们,走源码视图。
- 绝不悄悄丢失或改写这些片段。

**公式与图表**:基线没有单独识别,按普通文本显示。[未定]

**并发编辑语法**:多台设备同时编辑同一段语法时,结果可能收敛成不常见的形态。所有文字都会保留,并以原始源码呈现。

## 2. 便携文件格式

### 2.1 Markdown 文件

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/storage.rs?plain=1#L56 · https://github.com/wizlijun/note.md/blob/v6.1117.1/src-tauri/src/sumi/mod.rs?plain=1#L889 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

便携文件是一对:Markdown 文件和 JSON sidecar(§2.2)。Markdown 文件由一个小 YAML 身份头加上原样的 Markdown 正文组成:

```yaml
---
type: Writing Page
write_schema: 1
page_id: <页 UUID>
write_epoch: <epoch>
write_metadata: sidecar-v1
---
```

**规则**:

- 上面五个键由内核每次写出时强制设定。
- 头里其他键原样保留。例如新建时写入的 `author` 和创建标记 `sumi_creation`(见 [01-pages-and-storage.md](01-pages-and-storage.md) §3.1)。
  - `author` 取人工署名 actor,即 `human:` 前缀,与 OKF 的署名约定一致。
- 读入时,下列任一不符,都视为不匹配:
  - `type`、`write_metadata`、`write_schema` 与上面的值不符
  - `write_epoch` 与 sidecar 不一致

**这对文件放在哪里、叫什么名字**:属于桌面 vault 投影,见 [platform/notemd-desktop.md](platform/notemd-desktop.md)。导出归档中,这对文件固定叫 `page.writing.md` 与 `page.writing.meta.json`。

### 2.2 sidecar

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/storage.rs?plain=1#L14 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/WIRE.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

sidecar 是一份 JSON,字段如下:

| 字段 | 含义 |
|---|---|
| `schema` | 固定为 1 |
| `page_id`、`epoch` | 与 Markdown 头一致 |
| `projection_id` | 每次写出新生成的 UUID |
| `body_sha256` | 只对正文求哈希,不含 YAML 头 |
| `root_line_id` | 第一行的身份 |
| `lines[]` | 每个逻辑行一项,字段见下表 |

`lines[]` 每一项的字段:

| 字段 | 含义 |
|---|---|
| `id` | 行身份 |
| `text_sha256` | 该行文本的哈希 |
| `first_written_at` | 首次书写时间;从未写过的空行为 `null` |
| `last_written_at` | 最后修改时间 |
| `time_source` | 时间来源,取值见 §3.3 |

**规则**:

- 时间一律用 RFC 3339 UTC,精确到毫秒。
- 未知键原样保留。
- 读入时逐项校验以下内容,任一不符就视为与正文不匹配,不采信其时间:
  - 正文哈希
  - 行数
  - 首行身份
  - 每行文本哈希
  - 时间格式
- sidecar 只是 CRDT 状态的物化快照,不是另一个事实源。

### 2.3 不写进正文的东西

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/WIRE.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

- 正文里不出现逐行时间注释。
- CRDT 正文里不出现时间字符串。
- CRDT 正文里不存展示样式。

行身份和时间只在 CRDT 的 `body` 换行属性与 `timing` 事件里,以及 sidecar 里。

## 3. 行时间语义

### 3.1 逻辑行

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/WIRE.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L183 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

**怎样切分逻辑行**:按 LF 切分,保留末尾的空段,也不裁剪空白。

| 正文 | 行数 |
|---|---|
| 空正文 | 1 |
| `a\n` | 2 |
| `a\n\n` | 3 |

**行身份**:

- 每行有稳定的 UUID 身份:第一行的身份是页头里的 `root_line_id`,其余每行的身份挂在它前面那个 LF 的 `next_line_id` 属性上。
- 行身份不靠行号。

**屏幕排版不产生记录**:以下变化都不产生任何行时间记录,也不改变行身份:

- 屏幕折行
- 改变窗口宽度、字号或主题

### 3.2 首次书写与最后修改

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/WIRE.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-08-sumi-release.md?plain=1#L42 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

**基本规则**:

- 一行第一次写入内容时,确定首次书写时间(first)。
- 此后每次提交的修改都更新最后修改时间(last)。
- 输入法组字期间不记录,提交时才记录。

**各种编辑下怎样变化**:

| 编辑 | 行身份 | first | last |
|---|---|---|---|
| 回车拆行 | 左半保留原身份;右半是新行 | 右半带有文字时,继承原行的 first;新起的空行没有 first | — |
| 退格合并两行 | — | 取两者较早的 | 记合并时刻 |
| 清空一行 | — | 保留原值 | 更新 |
| 改变 Markdown 源码的格式操作 | — | — | 更新 |
| 撤销/重做 | — | 不伪造 | 记录这次动作 |
| 粘贴/导入 | — | 粘贴进来的中间新行各自得到首次时间 | 记写入时刻 |

两点补充:

- 撤销/重做时,重新插入的文字用新的身份,但带着原有行的来源。
- 粘贴/导入记录的是写入发生的时刻,不是原文的创作时间。

**并发**:时间附着在存活的原始字符贡献上,而不是行号上。所以多台设备同时拆行、并行时,first 与 last 仍能收敛:

- first 取所有存活贡献中的最小值。
- last 取最大值。

### 3.3 `time_source` 取值

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/document.rs?plain=1#L213 · https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/WIRE.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

sidecar 里每行的 `time_source`,取以下四个值之一:

| 取值 | 含义 |
|---|---|
| `device` | 时间来自本产品客户端上的书写 |
| `import` | 时间来自外部导入,例如外部编辑的三方合并 |
| `mixed` | 该行同时含有上面两种来源 |
| `unknown` | 来源未知。例如只凭 Markdown 恢复的页,不伪造时间 |

**CRDT 内的编码**:`timing` 事件的形状是 `[1, at_ms, source, spans]`。

- 事件 `source`:
  - 1 表示设备时间
  - 2 表示外部导入时间
  - 0 保留给“从便携快照恢复到新 UUID 页”。这类事件只继承原值,不新增触碰。
- 继承来源用位掩码表示:1 表示设备,2 表示导入,3 表示两者都有。

完整线格式见 [03-sync.md](03-sync.md) §1.1。

### 3.4 不做逐键回放

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/WIRE.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L183 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L17

**不做什么**:产品只承诺逐行的首次书写和最后修改时间,不提供逐键回放,也不按时间线重演书写过程。

**但历史不清除**:CRDT 历史为了正确合并而完整保留,所以不能宣称“不存逐键数据”:

- 每个副本使用新的随机 32 位客户端 ID,不做垃圾回收。
- 没有重写 epoch,也没有破坏性的历史压缩。
- 恢复状态中可能含有已删除的文字。

**容量限制**:正文上限是 1,000,000 个 UTF-16 单元(工程细则)。历史容量另有限制,见 [03-sync.md](03-sync.md) §8.2。
