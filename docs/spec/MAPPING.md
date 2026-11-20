# 旧规范去向对照(MAPPING)

本文件把 note.md 源仓库 `docs/superpowers/specs/` 下所有玄霜写作(Sumi Write)旧规范,逐文档、逐章节对应到现行规范。基线是 note.md `main` 的 `969f8e73`,宿主 tag `v6.1117.1`。

## 读法

- **去向**只有三种:
  - 现行规范的文件与小节(`00`–`05`、[platform/](platform/)),或 ADR、handoff 契约;
  - `已退役`:说明由哪项后来的决定取代;
  - `留在 note.md`:发布记录、验收证据、实施过程,以及只属于宿主或配套输入法的内容。它们不迁入 sumiwrite,原文仍在 note.md 仓库,以冻结 tag 为准。
- **(待补)**:旧规范里仍然有效、但现行目标小节还没写进去的内容。去向一栏写的是它应该落到的位置。
- **出入**:代码与旧规范不一致时,说明栏用一句话写明,并链接 [04-known-gaps](../handoff/04-known-gaps.md)。
- **退役名称**:退役名称不得作为现行行为出现在 `docs/spec/`;允许出现在 `docs/spec/MAPPING.md`、ADR 的「放弃的方案」段、以及 `docs/handoff/04-known-gaps.md` 的出入条目。本文件文末「退役名称与路径」是完整对照;其他现行文件只写现行名称。
- **旧章节**一栏的行号对应基线 `969f8e73` 上的旧文件。
- 主规范指 `2026-11-07-immersive-write-design.md`。主规范每个 `## ` 标题各占一行,§2 拆成 §2.1–§2.5,其余有实质内容的 `###` 小节也单列。

## 1. 主规范

| 旧文档 | 旧章节 | 去向 | 说明 |
|---|---|---|---|
| `2026-11-07-immersive-write-design.md` | 0. 最终决定总览与解释顺序(L7–33) | [00-product.md](00-product.md) 读法、§1.1、§1.2;其余各行分散到对应主题文件 | “工程细则”的含义并入 00 读法。总览表各行的去向见本表 §1–§9。本地化名称一行**已退役**,由 `2026-11-11-sumi-brand-name.md` 取代。“统一 Qt”与“Delphi 类方案”**已退役**,见 [ADR 0005](../adr/0005-native-text-controls.md)。L33 的退役清单只收在本文件。“固定规格或全屏”一行见 [04](04-editing-experience.md)「专注窗口与全屏」;固定规格怎么选仍是 [未定] |
| `2026-11-07-immersive-write-design.md` | 1. 需求与成功标准(L35–50) | [00-product.md](00-product.md) §1.1、§1.3、§2.1 | “以 Omawrite 的 Qt 技术路线为首选原型参考”**已退役**,由 GTK3 TextView/Overlay 路线取代(见 `2026-11-10-sumi-omarchy-native.md`、[notemd-desktop §6.1](platform/notemd-desktop.md))。“沉浸窗口只有全屏与固定尺寸两种形态”见 04「专注窗口与全屏」。末段“首版是 macOS 客户端……”是首版范围的历史表述,不再写进规范 |
| `2026-11-07-immersive-write-design.md` | 2. 用户体验(L52) | [04-editing-experience.md](04-editing-experience.md)、[01-pages-and-storage.md](01-pages-and-storage.md) §2 | 只有标题,内容拆在下面 §2.1–§2.5 |
| `2026-11-07-immersive-write-design.md` | §2.1 一页纸(L54–63) | [00 §1.1](00-product.md);[01 §2.2、§3.1–§3.3](01-pages-and-storage.md);[04「按需工具与状态提示」](04-editing-experience.md) | 翻页、总览、空白页、废纸篓、按需出现的入口 |
| `2026-11-07-immersive-write-design.md` | §2.2 排版与窗口(L64–92) | [04](04-editing-experience.md)「排版默认值」「留白随字号缩放」「主题」「光标」「专注窗口与全屏」;[05-fonts.md](05-fonts.md) 全文 | 旧字体组合与 Terminus 比较**已退役**,见文末。内置字体方案**已退役**,由按需下载取代([ADR 0007](../adr/0007-fonts-on-demand.md))。宿主与插件包体积的验收方法**留在 note.md** |
| `2026-11-07-immersive-write-design.md` | §2.3 输入法边界(L93–106) | [04「输入法边界」](04-editing-experience.md);[platform/later.md §6.1](platform/later.md) | 由每个平台各自实现的定制输入法见 later §6.1 |
| `2026-11-07-immersive-write-design.md` | §2.4 macOS 常用编辑快捷键契约(L107–137) | [04「快捷键语义」](04-editing-experience.md);[notemd-desktop §5.1](platform/notemd-desktop.md) | 平台无关的语义写在 04,macOS 键位表写在 §5.1,Linux 差异写在 §6.2 |
| `2026-11-07-immersive-write-design.md` | §2.5 光标动态验收(L138–146) | [04「光标」](04-editing-experience.md) | 规则(竖线、4 秒呼吸、常亮)进 04。验收方法与离屏探针**留在 note.md**。水平光标**已退役**,由竖线光标取代 |
| `2026-11-07-immersive-write-design.md` | 3. 原生 rich 与 Markdown 的边界(L147–160) | [02 §1.1–§1.3](02-markdown-and-line-time.md) | |
| `2026-11-07-immersive-write-design.md` | §3.1 剪贴板:Markdown复制与文本化粘贴(L161–174) | [04「复制与剪切」「粘贴」](04-editing-experience.md);[02 §1.1](02-markdown-and-line-time.md) | |
| `2026-11-07-immersive-write-design.md` | 4. 平台选型与性能判断(L175–195) | [ADR 0005](../adr/0005-native-text-controls.md);[notemd-desktop §5.2、§6.1、§7.1](platform/notemd-desktop.md);[later §1–§3](platform/later.md) | 统一 Qt 桌面路线**已退役**,由“每个平台用各自的原生控件”取代(ADR 0005)。Delphi 类候选**已退役**(ADR 0005) |
| `2026-11-07-immersive-write-design.md` | §4.1 Omarchy 原生编辑路线(L196–213) | [notemd-desktop §6.1、§6.2](platform/notemd-desktop.md) | Qt 6 原型路线(L198–202)**已退役**,由 GTK3 TextView/Overlay 取代。现存规则:避开 Super 绑定(§6.1、§6.2);Arch `.pkg.tar.zst` 按架构逐个验收,不能拿 `.deb` 或另一架构的包作证(§6.1),目前只有 x86_64 有依赖与 CLI 验收,安装后 GUI 启动和 aarch64 都是 [未定];六个显式配色、默认 `dim`,显式选择不会被系统主题改掉(§6.1)。出入:旧规范的“主题可跟随系统”没有实现,标 [未定],见 [04-known-gaps](../handoff/04-known-gaps.md)。平铺环境下固定尺寸窗口的协商仍是 [未定],见 04「专注窗口与全屏」 |
| `2026-11-07-immersive-write-design.md` | §4.2 性能目标与证据范围(L214–227) | [00 §1.3](00-product.md) 第 8 条 | 首版目标表与测量口径已写入,数值标(工程细则),全部未实测,第 8 条整条仍是 [未定]。见 [04-known-gaps](../handoff/04-known-gaps.md) |
| `2026-11-07-immersive-write-design.md` | 5. 数据模型和 Markdown(L229) | [01](01-pages-and-storage.md)、[02](02-markdown-and-line-time.md) | 只有标题 |
| `2026-11-07-immersive-write-design.md` | §5.1 页面模型(L231–241) | [01 §1.1、§1.2、§2.1](01-pages-and-storage.md) | |
| `2026-11-07-immersive-write-design.md` | §5.2 文件格式:正文与伴随元数据分离(L242–292) | [02 §2.1、§2.2](02-markdown-and-line-time.md);[notemd-desktop §2.1](platform/notemd-desktop.md)(路径);[ADR 0003](../adr/0003-portable-files-and-sqlite-history.md) | 现行路径是 `inbox/writings/YYYY-MM-DD-NN.writing.md`,同目录有 `YYYY-MM-DD-NN.writing.meta.json`。路径属于桌面 vault 投影,所以写在 notemd-desktop §2.1。旧路径**已退役**,见文末 |
| `2026-11-07-immersive-write-design.md` | §5.2.1 为什么不逐行塞时间注释(L293–298) | [02 §2.3](02-markdown-and-line-time.md);[ADR 0002](../adr/0002-single-ytext-line-time.md) | 结论进 02 §2.3,理由进 ADR。逐行内嵌时间**已退役**,由 sidecar 取代。marked 探针证据**留在 note.md** |
| `2026-11-07-immersive-write-design.md` | §5.2.2 CRDT 与文件布局解耦(L299–304) | [02 §2.2](02-markdown-and-line-time.md);[03 §1.1](03-sync.md);[ADR 0002](../adr/0002-single-ytext-line-time.md) | 尾部 HTML/YAML 行表**已退役**,由 sidecar 取代 |
| `2026-11-07-immersive-write-design.md` | §5.2.3 持久化、投影与恢复契约(L305–326) | [01 §4.1–§4.3、§5.1–§5.5](01-pages-and-storage.md);[notemd-desktop §2.1–§2.3、§2.5、§8.1](platform/notemd-desktop.md);[handoff 契约 §1.4、§1.6、§3](../handoff/03-notemd-contract.md) | 最终持久屏障(L313)见 01 §5.5 与契约 §1.6 E1;持久回执(L309)见 01 §5.4 与契约 §1.6 E2;落盘保证见 notemd-desktop §8.1;sidecar 配对与隐藏(L321)见 notemd-desktop §2.5。出入:旧规范要求正文与 sidecar 一起改名,代码改为宿主拒绝改名和另存为;旧规范说读和 flush 都不越过前序写,代码只在 load、observe 和 flush 前排空。删除、搜索、索引、分享里的配对未核实,标 [未定]。见 [04-known-gaps](../handoff/04-known-gaps.md) |
| `2026-11-07-immersive-write-design.md` | §5.3 行身份与时间(L327–355) | [02 §3.1–§3.4](02-markdown-and-line-time.md);[ADR 0002](../adr/0002-single-ytext-line-time.md) | |
| `2026-11-07-immersive-write-design.md` | 6. 独立实时同步服务(L356) | [03-sync.md](03-sync.md) | 只有标题 |
| `2026-11-07-immersive-write-design.md` | §6.1 推荐结构(L358–381) | [03 §1.2、§8.3](03-sync.md);[ADR 0004](../adr/0004-cloudflare-sync-private-pairing.md) | WebSocket 休眠的细节只写在 `write-sync-worker/README.md` 里,**留在 note.md** |
| `2026-11-07-immersive-write-design.md` | §6.2 协议草案(L382–401) | [03 §1、§3、§4、§5](03-sync.md) | |
| `2026-11-07-immersive-write-design.md` | §6.3 身份、数据恢复和运维(L402–413) | [03 §2、§7、§8](03-sync.md) | |
| `2026-11-07-immersive-write-design.md` | §6.4 ESP32 的交付边界(L414–440) | [later §3.1](platform/later.md) | |
| `2026-11-07-immersive-write-design.md` | 7. Vault 投影与外部修改(L441–462) | [notemd-desktop §2.1–§2.6、§3.1、§3.2](platform/notemd-desktop.md);[01 §4.2](01-pages-and-storage.md) | 同 UUID 副本(L459)见 notemd-desktop §2.6 与 01 §4.2:恢复副本总分配新 UUID,一页只观察自己文件名下的那对文件。出入:别名与内容分叉的自动检测、移动改名后按 UUID 找回,代码里都没有,标 [未定],见 [04-known-gaps](../handoff/04-known-gaps.md) |
| `2026-11-07-immersive-write-design.md` | 8. note.md 集成范围(L463–495) | [notemd-desktop §1、§3](platform/notemd-desktop.md);[00 §3.1](00-product.md);[handoff 契约 §1–§3](../handoff/03-notemd-contract.md) | “Linux 的 Qt 依赖不得进入 macOS/Windows 构建”(L478)**已退役**:Linux 不再用 Qt,这条随之失效 |
| `2026-11-07-immersive-write-design.md` | §8.1 插件与宿主的更新边界(2026-11-10补充)(L496–513) | [notemd-desktop §4.1、§4.2](platform/notemd-desktop.md);[later §4.2](platform/later.md) | |
| `2026-11-07-immersive-write-design.md` | 9. 全平台里程碑(L514–526) | [00 §2.1](00-product.md);[ios.md §4.1、§4.2](platform/ios.md);[later §1–§3、§6.1](platform/later.md) | 原 P3 的“Qt 6 原型”**已退役**,由 GTK3 取代。“5–8 工程周”的估算**已退役**,只是历史规划。原 P2“移动电量/后台重连”的退出条件见 ios §4.2 |
| `2026-11-07-immersive-write-design.md` | 10. 已冻结与后续决策(L527–532) | [00 §4.3](00-product.md);[later §3、§6](platform/later.md);[ADR 0001](../adr/0001-rust-core-yrs-yjs-v1.md) | “验收门槛只是目标”这条口径并入 00 读法的状态标签 |
| `2026-11-07-immersive-write-design.md` | 11. 实施、验收与发布约束(L533–544) | **留在 note.md**;发版配合见 [handoff 契约 §4](../handoff/03-notemd-contract.md) | 授权、签名、Wrangler 流程和证据要求都属于 note.md 的发版规程。性能门槛见 [00 §1.3](00-product.md) 第 8 条,首版目标未实测 |
| `2026-11-07-immersive-write-design.md` | 12. 需求与实施状态的维护(L545–551) | **留在 note.md**;状态口径由 [00 读法](00-product.md) 的状态标签取代 | L549“2026-11-08 首版验收期间的历史边界”是历史记录,不进规范 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-08 首次公开版本」(L552) | **留在 note.md** | 发布记录,作为 00 §1.1 状态行的证据 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-08 平缓呼吸修复版」(L558) | [04「光标」](04-editing-experience.md) | “减少动态效果不覆盖用户的光标选项”进 04。6 秒周期**已退役**,由 4 秒取代。发布记录**留在 note.md** |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-08 呼吸周期最终调整」(L563) | [04「光标」](04-editing-experience.md) | 4 秒周期,最低透明度 0.25 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-08 轻量字体交付调整」(L568) | [05「按需下载与状态显示」「回退与离线」](05-fonts.md);[ADR 0007](../adr/0007-fonts-on-demand.md) | 内置字体**已退役**。Terminus **已退役**(不收为隐藏选项)。单字体实测证据**留在 note.md** |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-08 独立后台迁移」(L576) | [00 §3.1](00-product.md);[ADR 0006](../adr/0006-plugin-backend-vs-host-session.md) | 细节见本表 `2026-11-08-plugin-payload-extraction.md` 各行 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-08 轻量宿主与插件后台正式发布」(L581) | **留在 note.md** | 发布记录 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-08 本地化与蓝磷追加范围」(L588) | [04「主题」](04-editing-experience.md)(`crt-blue`);[00 §1.2](00-product.md) | 显示名称**已退役**,由 `2026-11-11-sumi-brand-name.md` 取代,见文末。“语言切换只改显示”的规则在 00 §1.2 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-09 键盘音效追加范围」(L592) | [04「打字音」](04-editing-experience.md) | 24 个播放节点、增益数值等音频实现细节**留在 note.md**(源码 `src-tauri/src/sumi/sound.rs`) |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-09 蓝磷、本地化与键盘音效发布记录」(L605) | **留在 note.md** | 发布记录 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-09 全屏快捷键追加」(L614) | [notemd-desktop §5.1](platform/notemd-desktop.md)(⌘Return);[§6.2](platform/notemd-desktop.md)(Linux F11) | Linux 上的 Cmd/Win/Super+Enter **已退役**,由 F11 取代(`2026-11-10-omarchy-plugin-shortcuts.md`) |
| `2026-11-07-immersive-write-design.md` | 2026-11-09 P0：本机正文优先与崩溃恢复（覆盖此前保存边界）(L620–633) | [01 §5.1–§5.3](01-pages-and-storage.md) | 验收清单与故障注入方法**留在 note.md** |
| `2026-11-07-immersive-write-design.md` | §12「历史:6.1109.2/0.1.7五行聚焦打字」(L635–652) | **已退役** | 由「居中渐隐聚焦重构」取代,见文末。只有进入判定(2 秒内 4 次有效输入、组字算输入)沿用,见 [04「聚焦打字」](04-editing-experience.md) |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-09 写作底部状态提示收起」(L654) | [04「按需工具与状态提示」](04-editing-experience.md);[01 §5.3](01-pages-and-storage.md) | 未持久草稿和保存失败的提示必须一直可见,这条见 01 §5.3 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-09 聚焦打字、隐藏提示与本机安全整合发布」(L663) | **留在 note.md** | 发布记录 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-09 居中渐隐聚焦重构」(L668–688) | [04「聚焦打字:当前行居中渐隐」](04-editing-experience.md) | 现行契约,包括 10 秒停顿、1.2 秒慢显、0.2 秒快淡 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-09 居中渐隐与停笔动画:macOS发布状态」(L690) | **留在 note.md** | 发布记录 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-09 聚焦上下移动与新建空白页修正」(L695) | [04「聚焦打字」](04-editing-experience.md) | |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-09 上下导航与空白首行居中:macOS发布状态」(L704) | **留在 note.md** | 发布记录;也是 [notemd-desktop §4.1](platform/notemd-desktop.md) 所引的“三层更新”先例 |
| `2026-11-07-immersive-write-design.md` | §12「2026-11-10 导航后首键恢复聚焦与回车渐隐修正」(L709–722) | [04「聚焦打字」](04-editing-experience.md) | 规则是首键恢复、回车后上文可见。不可变行字形缓存、布局不重入是 AppKit 实现细节,**留在 note.md**(`tauri-plugin-native-editor/native/`) |

## 2. 其他旧文档

| 旧文档 | 旧章节 | 去向 | 说明 |
|---|---|---|---|
| `2026-11-08-plugin-payload-extraction.md` | 目标与范围第 1 条、Power Mode 资源契约 | **留在 note.md** | Power Mode 不属于玄霜写作 |
| `2026-11-08-plugin-payload-extraction.md` | 目标与范围第 2 条(后台与宿主的分工) | [00 §3.1](00-product.md);[ADR 0006](../adr/0006-plugin-backend-vs-host-session.md) | 设置界面仍在插件里;平台原生后台可执行文件负责字体下载与校验、SQLite 持久化与 Markdown 投影、网络与同步;宿主保留编辑面、输入法、焦点与系统服务桥接;后台接管的工作不能让每次按键等待 IPC |
| `2026-11-08-plugin-payload-extraction.md` | 目标与范围第 3 条(范围边界) | **留在 note.md** | 不拆 Memory/Habitat、不移除共享的公式/图表/分享编辑器、不新建动态库插件体系、宿主包与插件包体积分别报告,都是宿主的拆分边界,不约束玄霜写作 |
| `2026-11-08-plugin-payload-extraction.md` | Sumi 服务与保存边界 | [00 §3.1](00-product.md);[ADR 0006](../adr/0006-plugin-backend-vs-host-session.md);[01 §4.1、§5.2](01-pages-and-storage.md);[handoff 契约 §1.4](../handoff/03-notemd-contract.md) | `Committed`/`Saved` 的区分、回执与数据同事务提交、同一 `op_id` 内容不同则拒绝,见 [01 §5.4](01-pages-and-storage.md) 与 [handoff 契约 §1.6 E2](../handoff/03-notemd-contract.md)。崩溃后的重放顺序未在代码中逐条证明,标 [未定] |
| `2026-11-08-plugin-payload-extraction.md` | 凭据与字体 | [notemd-desktop §5.2](platform/notemd-desktop.md)(Keychain);[05「按需下载与状态显示」](05-fonts.md) | |
| `2026-11-08-plugin-payload-extraction.md` | 验收与发布、实际发布结果(2026-11-08) | **留在 note.md** | 发布记录 |
| `2026-11-10-omarchy-plugin-shortcuts.md` | 已发现、目标 | [notemd-desktop §6.2](platform/notemd-desktop.md);[04「快捷键语义」](04-editing-experience.md) | Linux 应用命令以 Ctrl 为主修饰键、Super 留给桌面、全屏用 F11。审计过程**留在 note.md** |
| `2026-11-10-omarchy-plugin-shortcuts.md` | 用户补充窗口和全屏需求 | [notemd-desktop §1.2、§6.2](platform/notemd-desktop.md);[04「全屏字号」](04-editing-experience.md) | 末段“正文固定底部”**已退役**,由 `2026-11-10-sumi-stationary-nonfocus-input.md` 取代 |
| `2026-11-10-sumi-decoration-input.md` | 全文 | **留在 note.md** | GTK 装饰层输入穿透是实现修复与发布证据。行为要求(点击、滚轮到达正文)已是 04 和 notemd-desktop §6.1 的默认前提 |
| `2026-11-10-sumi-fcitx-candidates.md` | 行为、实现 | [notemd-desktop §6.3](platform/notemd-desktop.md) | D-Bus 接口与候选呈现规则在 §6.3。“非专注模式正文输入行固定底部”**已退役**,由 `2026-11-10-sumi-stationary-nonfocus-input.md` 取代 |
| `2026-11-10-sumi-fcitx-candidates.md` | 验证 | **留在 note.md** | |
| `2026-11-10-sumi-focus-stability.md` | 行为要求 | [04「非聚焦输入」](04-editing-experience.md)(无滚动条);[04「聚焦打字」](04-editing-experience.md) | 重复居中得到同一像素位置、动画结束后不跳动,见 04「聚焦打字」的“位置稳定”。Linux 已交付,macOS 无同等验收,标 [未定] |
| `2026-11-10-sumi-focus-stability.md` | 根因与最小改动、验证 | **留在 note.md** | GTK 取整修复 |
| `2026-11-10-sumi-linux-audio-session.md` | 范围(宿主对插件进程环境的义务) | [handoff 契约 §1.6 E3](../handoff/03-notemd-contract.md) | Linux 插件进程的环境白名单必须带 `XDG_RUNTIME_DIR`,打字音才能连上音频服务 |
| `2026-11-10-sumi-linux-audio-session.md` | 问题与证据、验收 | **留在 note.md** | 排障证据与验收记录 |
| `2026-11-10-sumi-macos-fcitx-bridge.md` | 接管身份与通信、消息与显示所有权 | [notemd-desktop §6.3](platform/notemd-desktop.md)「macOS 接口」 | |
| `2026-11-10-sumi-macos-fcitx-bridge.md` | 原生展示 | [notemd-desktop §6.3](platform/notemd-desktop.md) 候选呈现规则 | Fcitx 端的候选过滤补丁属于 Fcitx5 for Sumi 独立项目,**留在 note.md**(配套输入法仓库) |
| `2026-11-10-sumi-macos-fcitx-bridge.md` | 验收门槛 | **留在 note.md** | |
| `2026-11-10-sumi-omarchy-native.md` | 集成方案评审 | [notemd-desktop §6.1](platform/notemd-desktop.md);[ADR 0005](../adr/0005-native-text-controls.md);`viewportWidth` 见 [handoff 契约 §1.1](../handoff/03-notemd-contract.md) | 取代主规范 §4.1 的 Qt 路线。Tauri 运行时补丁、`Arc` 共享是宿主实现,**留在 note.md**。RTF 粘贴规则见 [04「粘贴」](04-editing-experience.md) |
| `2026-11-10-sumi-omarchy-native.md` | 必须保持的契约 | [04「输入法边界」](04-editing-experience.md);[01 §5](01-pages-and-storage.md);[notemd-desktop §3.1、§6.1](platform/notemd-desktop.md) | |
| `2026-11-10-sumi-omarchy-native.md` | 验收计划、交付状态 | **留在 note.md** | |
| `2026-11-10-sumi-omarchy-release.md` | 全文 | **留在 note.md** | 发布计划与门禁。现行打包事实(只有 x86_64)见 [notemd-desktop §6.1](platform/notemd-desktop.md) |
| `2026-11-10-sumi-stationary-nonfocus-input.md` | 全文 | [04「非聚焦输入」](04-editing-experience.md);[notemd-desktop §6.3](platform/notemd-desktop.md) | 取代旧的底部锚定。验证方法**留在 note.md** |
| `2026-11-11-omarchy-amd64-ime-release.md` | 范围 | [notemd-desktop §6.3](platform/notemd-desktop.md)「Linux 打包」 | addon 包名、版本约束、前置条件 |
| `2026-11-11-omarchy-amd64-ime-release.md` | 流程与验收、发布门禁发现的修复与固定核心来源 | **留在 note.md** | BOM/CRLF 修复属于宿主编辑器与 moraya-core |
| `2026-11-11-release-input-method-companion.md` | 全文 | [notemd-desktop §6.3](platform/notemd-desktop.md)「macOS 分发」;发版脚本**留在 note.md**,见 [handoff 契约 §4](../handoff/03-notemd-contract.md) | 旧参数名见文末 |
| `2026-11-11-sumi-brand-name.md` | 显示规范 | [00 §1.2](00-product.md) | “Faitc5 名称保留”一句**已退役**,由 `2026-11-12-fcitx5-name-correction.md` 取代 |
| `2026-11-11-sumi-brand-name.md` | 验收与发布 | **留在 note.md** | |
| `2026-11-11-sumi-ime-key-feedback.md` | 问题、协议与实现 | [04「输入法按键反馈」](04-editing-experience.md);[notemd-desktop §6.3](platform/notemd-desktop.md)(`SetActiveWithTyping`、`TypingKey`) | 128 条未配对上限等是实现细节,**留在 note.md** |
| `2026-11-11-sumi-ime-key-feedback.md` | 验收与交付 | **留在 note.md** | |
| `2026-11-11-sumi-ime-sound.md` | 全文 | [04「输入法按键反馈」](04-editing-experience.md) 第一条 | 组字变化时发声。根因与验证**留在 note.md** |
| `2026-11-11-sumi-platform-parity.md` | P1–P10 清单 | P2→[04「聚焦打字」](04-editing-experience.md);P3、P4→[04「打字音」](04-editing-experience.md);P5→[04「全屏字号」](04-editing-experience.md);P6→[04「底部留白」](04-editing-experience.md);P7→[notemd-desktop §6.3](platform/notemd-desktop.md);P9→[notemd-desktop §6.2](platform/notemd-desktop.md);P1、P8→[notemd-desktop §6.4](platform/notemd-desktop.md);P10→[01 §5.4](01-pages-and-storage.md)、[handoff 契约 §1.6 E2](../handoff/03-notemd-contract.md) | P10 的回声识别与异载荷拒绝已写入 01 §5.4;完整性未逐条证明,标 [未定] |
| `2026-11-11-sumi-platform-parity.md` | 已对齐、实现约束 | [notemd-desktop §6.2](platform/notemd-desktop.md) | 必要的平台差异 |
| `2026-11-11-sumi-platform-parity.md` | 附加任务(中英文边界自动空格) | **留在 note.md** | 属于 Fcitx5 for Sumi 独立项目(00 §4.3),不是编辑器规则 |
| `2026-11-11-sumi-window-startup.md` | 全文 | [notemd-desktop §1.2](platform/notemd-desktop.md);[04「排版默认值」](04-editing-experience.md)(启动时全屏);偏好字段 `startFullscreen` 见 [handoff 契约 §1.1](../handoff/03-notemd-contract.md) | |
| `2026-11-11-writing-plugin-groups.md` | 全文 | **留在 note.md** | 宿主插件市场分类,不是玄霜写作的规则 |
| `2026-11-12-fcitx5-name-correction.md` | 全文 | [00 §1.2](00-product.md) | 正式名 Fcitx5 for Sumi。产品内部 Bundle ID、目录名不变 |
| `sumi-ime-cross-platform.md` | 1. 目标与范围;2. 术语与坐标;3. 共同视觉要求 | [04「输入法边界」](04-editing-experience.md);[notemd-desktop §6.3](platform/notemd-desktop.md) 候选呈现规则 | 文首“打字机输入法”的旧称**已退役**,见文末 |
| `sumi-ime-cross-platform.md` | 4. 两种模式的布局(§4.1–§4.2) | [notemd-desktop §6.3](platform/notemd-desktop.md) | §4.2 取代早期“正文输入行也固定底部” |
| `sumi-ime-cross-platform.md` | §4.3 窄窗口与较长候选 | [notemd-desktop §6.3](platform/notemd-desktop.md) | 见 §6.3「分页、截断与编号」:最多 4 行是上限并随视区收紧,本地分页能到达全部候选,按字形边界省略,编号用引擎原索引。真机物理验收 [未定] |
| `sumi-ime-cross-platform.md` | 5. 输入行为与数据完整性 | [04「输入法边界」](04-editing-experience.md);[01 §5.3](01-pages-and-storage.md) | |
| `sumi-ime-cross-platform.md` | 6. 稳定性、滚动和全屏 | [04「非聚焦输入」「聚焦打字」](04-editing-experience.md) | 无滚动条已写入。重复定位不抖动见 04「聚焦打字」的“位置稳定” |
| `sumi-ime-cross-platform.md` | 7. 输入上下文与故障回退 | [notemd-desktop §6.3](platform/notemd-desktop.md) | |
| `sumi-ime-cross-platform.md` | 8. 跨平台实现边界 | [notemd-desktop §6.3](platform/notemd-desktop.md);[later §6.1](platform/later.md) | |
| `sumi-ime-cross-platform.md` | 9. 验收清单 | **留在 note.md** | |
| `sumi-ime-cross-platform.md` | 10. 给其他平台实现者的摘要 | [notemd-desktop §6.3](platform/notemd-desktop.md) | 内容与 §1–§8 重复 |

## 退役名称与路径

规则:退役名称不得作为现行行为出现在 `docs/spec/`;允许出现在 `docs/spec/MAPPING.md`、ADR 的「放弃的方案」段、以及 `docs/handoff/04-known-gaps.md` 的出入条目。现行规范与 handoff 00–03 只写右栏的现行做法。

| 退役内容 | 出处 | 取代者 |
|---|---|---|
| 路径 `inbox/write/`、`inbox/writes`,扩展名 `.write.md` | 主规范 L33 | `inbox/writings/YYYY-MM-DD-NN.writing.md`,见 [notemd-desktop §2.1](platform/notemd-desktop.md) |
| 逐行内嵌时间注释;尾部 HTML/YAML 行表 | 主规范 L33、§5.2.1 | `.writing.meta.json` sidecar,见 [02 §2.2](02-markdown-and-line-time.md) |
| 统一 Qt 桌面路线;Delphi 类方案 | 主规范 L16、L33、§4 | 每个平台用各自的原生控件,见 [ADR 0005](../adr/0005-native-text-controls.md) |
| Linux Qt 6 原型;Omawrite 的 Qt 路线;“Linux 的 Qt 依赖不得进入其他构建” | 主规范 §1、§4.1、§8 L478、§9 P3 | GTK3 TextView/Overlay,见 [notemd-desktop §6.1](platform/notemd-desktop.md) |
| Courier Prime 组合;Special Elite + 又又意宋;思源宋体 | 主规范 L33、L83 | 六组字体,见 [05「六组选项」](05-fonts.md) |
| 旧字体设置值 `Sumi Typewriter`、`Sumi Elite` | 主规范 L83 | 迁移到第一组 `Sumi Plex`,见 [05「旧设置迁移到第一组」](05-fonts.md) |
| 研究候选 A2 Typewriter、LTR NCND Variable | 主规范 L33 | 未采用 |
| Terminus(包括作隐藏选项) | 主规范 L77、L574 | 第 6 组用 GNU Unifont 单字体,见 [05](05-fonts.md) |
| 字体随宿主或插件打包 | 主规范 §2.2、L568 | 点击后再下载,见 [ADR 0007](../adr/0007-fonts-on-demand.md) |
| 水平光标(横线) | 主规范 L33 | 稍粗的竖线,见 [04「光标」](04-editing-experience.md) |
| 6 秒呼吸周期 | 主规范 L558 | 4 秒,见 [04「光标」](04-editing-experience.md) |
| 显示名 Sumi Typewriter、玄霜打字机、すみ;“Sumi 打字机” | 主规范 §0、L588;`sumi-ime-cross-platform.md` 文首 | 玄霜写作 / Sumi Write(`2026-11-11-sumi-brand-name.md`),见 [00 §1.2](00-product.md) |
| 输入法名 Faitc5(误拼) | `2026-11-11-sumi-brand-name.md`、`2026-11-11-sumi-platform-parity.md`、`2026-11-11-omarchy-amd64-ime-release.md` | Fcitx5 for Sumi(`2026-11-12-fcitx5-name-correction.md`)。发版脚本的旧参数 `--faitc5-package` 与环境变量 `FAITC5_PACKAGE_PATH` 只作为兼容别名读取 |
| 五行聚焦:57% 锚点、当前行 +2pt、逐行缩放 1/0.97/0.93/0.88/0.82、透明度 1/0.92/0.74/0.46/0.20、约 420ms 进场;更早讨论的 61.8% | 主规范 L635–652 | 居中渐隐,见 [04「聚焦打字」](04-editing-experience.md) |
| 非聚焦时正文输入行固定在底部 | `2026-11-10-sumi-fcitx-candidates.md`、`2026-11-10-omarchy-plugin-shortcuts.md` 末段 | 输入行原地不动,只有候选固定在底部(`2026-11-10-sumi-stationary-nonfocus-input.md`),见 [04「非聚焦输入」](04-editing-experience.md) |
| Linux 上 Cmd/Win/Super+Enter 切换全屏 | 主规范 L614 | F11,见 [notemd-desktop §6.2](platform/notemd-desktop.md) |
| 5–8 工程周的人力估算 | 主规范 L525 | 只是历史规划,不再作为工期 |
| 固定尺寸窗口“几种固定规格” | 主规范 L25、L89 | 尚未定下,见 [04「专注窗口与全屏」](04-editing-experience.md) [未定] |
| “vault 投影” | [ADR 0009](../adr/0009-page-store-vs-vault-projection.md) | 归档投影,见 [ADR 0013](../adr/0013-workspace-and-archive-off-vault.md) |
