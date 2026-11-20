# 00 · 产品

本文件说明玄霜写作(Sumi Write)是什么、叫什么、做到什么算成功、在哪些平台以什么形态存在、和 note.md 的边界在哪里、以及明确不做的事。它是 `docs/spec/` 的总入口。

## 读法

- **现行规范**:只写基线上现在生效的规则,不写变更过程。旧文档中各章节的去向见 [MAPPING.md](MAPPING.md)。
- **基线**:note.md 源仓库 `main` 的 `969f8e73`,宿主发布 tag `v6.1117.1`。
- **状态标签**:每个 `###` 小节标题后的第一行是状态行。只有五种取值:
  - `[已交付:macOS+Linux]`
  - `[已交付:macOS]`
  - `[已交付:Linux]`
  - `[计划:iOS]`
  - `[未定]`

  小节内个别规则状态不同,就在该条规则末尾单独加标签。
- **证据**:`[已交付:…]` 状态行同一行带证据链接,格式为 `https://github.com/wizlijun/note.md/blob/<宿主 tag 或提交号>/<路径>`。插件没有自己的 tag,一律用宿主 tag。判断依据有三:两份 CHANGELOG、`docs/superpowers/reports/` 下的发布报告、以及代码是否存在。
- **双平台标签的证据**:`[已交付:macOS+Linux]` 要两个平台各有证据。macOS 侧取发布记录与发布报告;Linux 侧取 Linux 交付记录与 Omarchy 验收报告,即 Linux 上通过的自动化测试与实机检查。纯服务端的规则与客户端平台无关,会在正文里注明“服务端规则”。Linux 链接如果指向 Omarchy 报告里的汇总测试行(L16 插件前端、L17 write-core、L18 宿主),它的含义是“同一份代码在 Linux 上自动化测试通过”,不是逐条规则的实机验收。其中 L18 还有 4 项隔离环境测试没在那一批运行。这类证据只用于内核、格式和本机逻辑这类代码层面的规则。凡是规则涉及生产或实机行为(跨设备同步、真实配对、具体交互),而 Linux 侧没有对应的实机证据,就在该条规则末尾单独加标签,或把该小节降为 `[已交付:macOS]`,并写明缺什么。
- **工程细则**:旧规范中由实现团队补充、并非用户逐项选定的数值,例如快捷键、尺寸、时间和阈值,标 `(工程细则)`。
- **主题文件与平台文件**:平台无关的规则写在 `00`–`05` 主题文件。某个平台特有的实现写在 [platform/](platform/) 下,包括 [notemd-desktop.md](platform/notemd-desktop.md)、[ios.md](platform/ios.md)、[later.md](platform/later.md)。
- **出入与缺口**:凡出处不足、代码与旧规范不一致之处,都登记在 [../handoff/04-known-gaps.md](../handoff/04-known-gaps.md)。

## 1. 产品定义

### 1.1 一页纸的写作产品

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L182 · https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L112

玄霜写作是安静的单页写作产品:

- **屏幕上只有一页纸**:正文、光标和留白。翻页、新建、总览、外观和移到废纸篓等操作,按需在底部出现。
- **纸页即单位**:每页是一段 Markdown 正文。逐行记录首次书写和最后修改的时间。多台设备可以同时写同一页,离线写的内容自动合并。
- **规则由 sumiwrite 定义**:纸页的写作、存储、同步与呈现规则都归 sumiwrite。note.md 是宿主之一,提供原生编辑面、vault 和插件运行时(设计 §5.1)。

各主题的规则在:

- 纸页与存储:[01-pages-and-storage.md](01-pages-and-storage.md)
- Markdown 与行时间:[02-markdown-and-line-time.md](02-markdown-and-line-time.md)
- 同步:[03-sync.md](03-sync.md)
- 编辑体验:[04-editing-experience.md](04-editing-experience.md)
- 字体:[05-fonts.md](05-fonts.md)

### 1.2 命名

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L66 · https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/manifest.v2.json

| 场合 | 名称 |
|---|---|
| 中文界面 | 玄霜写作 |
| 英文界面,以及未单独指定的语言(回退) | Sumi Write |
| 日文界面 | 品牌名沿用 Sumi Write,说明文字用日文 |
| 插件 ID | `notemd.sumi`,不变 |
| 配套输入法 | Fcitx5 for Sumi |

iOS 主屏显示名是例外:各语言一律显示 Sumi Write,见 [platform/ios §1](platform/ios.md#做)。

改名只改显示名称。以下内容都不随改名变化:

- 插件 ID、包名、协议名、数据路径
- 纸页身份
- 字体别名

已有文稿和设置继续兼容。

### 1.3 成功标准

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L183 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-08-sumi-release.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L7 · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L49

满足以下各条,才算这个产品成立:

1. **重开即续写**:再次打开时回到上次的纸页。纸页身份存在本机偏好 `activePage` 里。窗口和编辑面各有自己的落点规则:
   - 玄霜写作独立窗口新建编辑面时,光标落在正文末尾,并保证末行可见。
   - note.md 主编辑器恢复持久的阅读位置。

   见 [04-editing-experience.md](04-editing-experience.md)。
2. **行时间**:每个以 LF 分隔的逻辑行,都记录首次书写时间和最后修改时间。不做逐键回放。语义见 [02-markdown-and-line-time.md](02-markdown-and-line-time.md)。
3. **多设备并发与离线合并**:多台设备可以同时编辑同一页,离线编辑能自动合并。整篇“后写覆盖”或“单设备独占写锁”都不满足这条。语义见 [03-sync.md](03-sync.md)。跨设备真实合并只在 macOS 上验收过,证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-08-sumi-release.md?plain=1#L42。Linux 共用同一内核与客户端,但没有跨设备生产联调,见 https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-10-sumi-omarchy-validation.md?plain=1#L65。[已交付:macOS]
4. **源码完整可读**:用纯文本源码模式能读到完整 Markdown。富文本编辑时隐藏 YAML 头和各类 ID。
5. **只同步自己的数据**:同步服务只同步本产品的纸页及必需的元数据,不同步 vault 里的其他内容。
6. **偏好留在本机**:显示偏好只存本机,v1 不跨设备同步。
7. **本机正文优先**:本机已确认保存的正文,不因投影文件缺失或冲突而打不开、读不了或写不下去。见 [01-pages-and-storage.md](01-pages-and-storage.md) §5。
8. **性能矩阵**:下表只是首版目标,不是已通过的结果。基线发布报告写明性能、能耗、内存与网络 p95 矩阵仍未完成,证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-08-sumi-release.md?plain=1#L49。[未定]

   | 指标 | 首版目标(未实测) |
   |---|---|
   | 已提交的输入到实际呈现帧 | 60Hz 机器上 p95 ≤ 50ms(工程细则)。输入法里用户选词的等待另计 |
   | 稳态编辑时的主线程 | 没有可重复出现的 >100ms 停顿(工程细则) |
   | 远端提交到本机可见 | 在 RTT ≤ 100ms 的网络下,p95 ≤ 300ms(工程细则) |
   | 正常文档的投影 | 输入停止后通常 ≤ 1 秒(工程细则)。投影失败与关闭时的 flush 都要能观察到 |
   | 10 万字符热打开 | ≤ 500ms 可以输入(工程细则)。冷启动另测 |
   | 正确性 | 不丢字,不破坏组字,隐藏元数据不泄露到正文或普通复制 |

   **测量口径**:
   - 同机、同字体字号、同语料、同输入法。
   - 至少 5 次独立重复,发布构建与 debug 构建的数据分开列。
   - 1 万和 10 万字符是正常门槛,100 万字符用于压力测试。
   - 测主线程、内存、CPU 和能耗,不只测文本控件。
   - 物理输入到呈现帧必须有输入事件和显示证据。程序化 layout、rAF 或同步布局耗时都不能代替。
   - 目标没达到时,定位并记录,不为了结论更换对照条件。

Linux 的交付范围:该平台共用同一套 Markdown/CRDT/持久日志,第 3 条的跨设备部分尚无生产证据,已记入 known-gaps。

## 2. 平台与形态

### 2.1 一览

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L182 · https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L112 · https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/manifest.v2.json

| 平台 | 形态 | 状态 | 细节 |
|---|---|---|---|
| macOS(Apple Silicon) | note.md 插件 `notemd.sumi`。原生编辑面由宿主提供,持久化、同步与字体下载在插件后台进程 | [已交付:macOS] | [platform/notemd-desktop.md](platform/notemd-desktop.md) |
| Linux x86_64(Omarchy) | 同上,原生编辑面为 GTK | [已交付:Linux] | [platform/notemd-desktop.md](platform/notemd-desktop.md) |
| iOS / iPadOS | 独立应用,不依赖 note.md | [计划:iOS] | [platform/ios.md](platform/ios.md) |
| Windows、Android、ESP32、桌面独立应用 | 只保留定位,没有交付 | [未定] | [platform/later.md](platform/later.md) |

形态上分两类:

- **桌面**:保持 note.md 插件形态。理由见 [../adr/0008-standalone-repo-desktop-stays-plugin.md](../adr/0008-standalone-repo-desktop-stays-plugin.md)。
- **iOS**:独立应用。只有纸页存储,没有归档投影,见 [../adr/0009-page-store-vs-vault-projection.md](../adr/0009-page-store-vs-vault-projection.md)。[计划:iOS]

## 3. 与 note.md 的边界

### 3.1 现行分工

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L162 · https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/manifest.v2.json · https://github.com/wizlijun/note.md/blob/v6.1117.1/plugins-src/write/manifest.v2.json?plain=1#L9 · https://github.com/wizlijun/note.md/blob/v6.1117.1/CHANGELOG.md?plain=1#L112

**插件后台进程负责**:

- 本机持久化
- 归档投影
- 同步协调
- 字体下载

**宿主负责**:

- 即时内存 CRDT
- 实时编辑会话
- 原生编辑桥
- 系统凭据存储

取舍理由见 [../adr/0006-plugin-backend-vs-host-session.md](../adr/0006-plugin-backend-vs-host-session.md)。

双方互相约定的接口叫 `host-contract`。已交付的基线是 `host-contract v1`;v2 `[未定]`:待配套发版。契约全文在 [../handoff/03-notemd-contract.md](../handoff/03-notemd-contract.md)。它包括:

- 宿主命令
- 原生编辑面能力
- 后台握手
- 归档投影约定
- 发版配合

插件 manifest 的 `engines.notemd` 声明最低宿主版本。

### 3.2 代码与规范的归属

状态:[未定]

迁移完成后的归属已经定下(设计 §5.1–5.2):

- **sumiwrite 定义**:产品规则、内核、同步协议、同步服务与平台无关的会话逻辑。
- **note.md 实现**:`host-contract v1`(已交付基线);v2 `[未定]`:待配套发版。

但这一归属**尚未执行**:在基线上,源码仍全部在 note.md 仓库。逐项归属判定见 [../handoff/01-inventory.md](../handoff/01-inventory.md),迁移分期见 [../handoff/02-migration-plan.md](../handoff/02-migration-plan.md)。

## 4. 非目标

### 4.1 产品层面不做

状态:[已交付:macOS+Linux] 证据:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-sync-worker/README.md · https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-08-sumi-release.md

- 不做文件夹、标签、拖拽排序。
- 不做团队协作。
- 总览不显示文件名和日期。见 [01-pages-and-storage.md](01-pages-and-storage.md)。
- 同步服务不做公开注册、多租户或付费。按设计 §10.4,规范把“单用户”写成当前的部署形态,不写成协议层的假设。见 [03-sync.md](03-sync.md) §8.3。
- 不宣称端到端加密:同步服务不是 E2EE。
- 不做逐键回放。
- 显示偏好不跨设备同步。

### 4.2 iOS 第一阶段不做

状态:[计划:iOS]

- 不面向公众分发,不上架 App Store。
- 不做注册、多租户或付费。
- 没有 vault、文件夹和文件名的概念。
- 不做扫码配对。

细节见 [platform/ios.md](platform/ios.md)。

### 4.3 暂不推进的形态

状态:[未定]

- **Android 与 ESP32**:只保留定位。
- **桌面独立应用**:只在路线图上。
- **Fcitx5 for Sumi**:仍是独立项目,不并入 sumiwrite。

见 [platform/later.md](platform/later.md)。
