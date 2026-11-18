# 04 已知缺口与未决项

基线:note.md `main` 969f8e73,宿主 tag `v6.1117.1`,插件 0.1.16。凡代码与旧规范不一致,以基线代码为准,现行规范按代码写;这里记下分歧,供后续各期计划和规范修订取用。

- 标注:**[用户定]**、**[我的判断]** 沿用设计原标注;本文自己的判断也标 **[我的判断]**。`[未定]` 表示没有找到足够的出处。
- 源路径都指 note.md 仓库;“现行”指本仓库中反映当前行为的规范位置。
- 旧规范与现行文件的对照见 [../spec/MAPPING.md](../spec/MAPPING.md)。

---

## 1. 体验对齐清单 P1–P10 的现状

来源:旧规范 `docs/superpowers/specs/2026-11-11-sumi-platform-parity.md`(基线 `eff8c327`,宿主 6.1110.8 / Sumi 0.1.13),验收记录 `docs/superpowers/reports/2026-11-11-sumi-platform-parity.md`。修复提交在该报告里列出,随后被重放进发布 tag `v6.1111.1`(宿主 6.1111.1 / Sumi 0.1.14,`git log v6.1110.8..v6.1111.1`),原提交也在 `v6.1111.3` 及以后的 tag 中。

| 编号 | 原差异 | 现状 | 依据 |
|---|---|---|---|
| P1 | 回车后上方所有行消失(macOS) | **未核实**。用户反馈“现在看好像修复了”,记录为未再出现,根因未确证,没有故障红测 | 验收记录 L21([链接](https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/reports/2026-11-11-sumi-platform-parity.md?plain=1#L21));现行 [notemd-desktop §6.4](../spec/platform/notemd-desktop.md) |
| P2 | 首次进入聚焦:mac 固定首键 2 秒窗,Linux 滑动 2 秒窗 | **已解决**。两端都用滑动 2 秒窗、≥4 次(提交 `f0343d3f`,重放为 `91c0fb82`) | [CHANGELOG v6.1111.1 L17](https://github.com/wizlijun/note.md/blob/v6.1111.1/CHANGELOG.zh-CN.md?plain=1#L17)“聚焦输入使用滚动两秒计数”;现行 [04 聚焦打字](../spec/04-editing-experience.md) |
| P3 | 失败草稿 mac 仍发声,Linux 停止 | **已解决**(`93775741` / `0341b8db`) | 同上 L17“保存失败后暂停的草稿不再触发打字音效” |
| P4 | 快捷键 mac 可发声,Linux 不响 | **已解决**,mac 向 Linux 对齐(`93775741` / `0341b8db`) | 同上 L17“命令快捷键……不再触发打字音效” |
| P5 | 全屏字号 Linux 有有界放大,mac 无 | **已解决**。两端共用同一计算,退出恢复(`35611925` / `c94c4488`);隔离宿主的全屏进入、退出与持久字号 GUI 核对通过 | 同上 L17;验收记录 L11、L25;现行 [04 全屏字号](../spec/04-editing-experience.md) |
| P6 | 底部留白:mac 聚焦以全高计算,Linux 扣除 | **已解决**(`f0343d3f` / `91c0fb82`) | 同上 L17“聚焦布局与内嵌候选尊重底部留白”;现行 [04 底部留白](../spec/04-editing-experience.md) |
| P7 | 聚焦候选下方正文:mac 位移留白,Linux 覆盖 | **部分**。macOS 候选不再重复扣除底部保留区(`f7e5c147` / `86e11a01`);完成标准允许两端绘制机制不同,共规的代码与单测已写入现行规范;两端真机物理验收 `[未定]` | 验收记录 L12;现行 [notemd-desktop §6.3](../spec/platform/notemd-desktop.md) |
| P8 | 正式宿主加物理输入法的 GUI 证据不全 | **未解决**。Linux amd64 有实包 GUI 与 7 项私有 D-Bus 真实拼音回归;macOS 真机物理组字终验未执行 | `reports/2026-11-11-omarchy-amd64-ime-release/README.md` L7、L27;`reports/2026-11-11-sumi-macos-ime-plugin-release/README.md` L17;现行 [notemd-desktop §6.3、§6.4](../spec/platform/notemd-desktop.md) |
| P9 | Linux 没有 Shift+Return 硬换行映射 | **部分**。代码已有(`e5c323d8` / `e76b3f75`),Linux 随 v6.1111.4 发布;没有 Linux GTK 实机证据 | 验收记录 L10;现行 [04 Return 与缩进](../spec/04-editing-experience.md)、[notemd-desktop §6.2](../spec/platform/notemd-desktop.md) |
| P10 | 本机编辑经云端回送后,收据冲突阻塞设置 | **已解决**(`08d42615` / `45e07d39`):相同编辑的回声幂等,不同载荷仍拒绝。“回声幂等”的完整性在契约里仍标 `[未定]` | [CHANGELOG v6.1111.1 L19](https://github.com/wizlijun/note.md/blob/v6.1111.1/CHANGELOG.zh-CN.md?plain=1#L19);现行 [01 §5.4](../spec/01-pages-and-storage.md)、[03-notemd-contract.md](03-notemd-contract.md) §1.6 |

---

## 2. 未决决策

### 2.1 旧主规范 §10 留下的

旧主规范 `2026-11-07-immersive-write-design.md` §10“已冻结与后续决策”冻结了配对协议、字体目录、Yrs/Yjs 版本、UTF-16 索引、行身份与时间编码、原生 tab、最低系统和服务限额,并留下以下几项待定。至今仍未定:

- **ESP32 板型、显示与输入硬件**:没有选定。现行 [platform/later.md §3.1](../spec/platform/later.md) `[未定]`。
- **后续平台的字体子集**:没有交付;约束“子集字库不能宣称覆盖完整桌面字库”保留。现行 [05-fonts.md 回退与离线](../spec/05-fonts.md) `[未定]`。
- **定制输入法项目**:桌面已有独立项目 Fcitx5 for Sumi,不并入本仓库,只写对接契约(设计 §2 **[我的判断]**);其他平台怎么做未定。现行 [later.md §6.1](../spec/platform/later.md)、[notemd-desktop §6.3](../spec/platform/notemd-desktop.md)。
- **验收门槛、工期与备份保留期只是目标**:旧主规范 §10–§11 要求性能、物理输入法、VoiceOver、外部容量门禁未通过时必须明确保留。基线发布报告原话是“完整性能/PM10k、能耗/内存及网络可见 p95 矩阵仍未完成”(`reports/2026-11-08-sumi-release.md` L49)。现行 [00-product.md §1.3](../spec/00-product.md) 第 8 条 `[未定]`。

### 2.2 本期交接中留给后续各期的

- `core-vX.Y.Z` 与 `host-contract` 版本是否联动;服务协议 `VERSION=1` 与 `host-contract v1` 的关系。见 [03-notemd-contract.md](03-notemd-contract.md) §7。
- sumiwrite 交给 note.md 签名的构建物与校验清单格式(契约 §5)。
- `shortcuts.ts` 的复制或引用、`i18n.ts` 宿主侧是否留一份、`verify-release.py` 是否拆分——第 2 期定([01-inventory.md](01-inventory.md) §6)。
- `session/` 的切分方式、`external.rs` 的落点、`journal.rs`/`durability.rs` 的接口抽取、同一模块如何适配桌面跨进程与 iOS 单进程——第 3 期定([ADR 0012](../adr/0012-shared-session-module.md))。
- 桌面独立的第 1 条标准“明显多于”没有量化门槛([later.md §4.1](../spec/platform/later.md))。
- **设计与计划文档尚未公开**:本仓库引用的 `docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md` 及第 0 期计划在 note.md 仓库的 `docs/sumiwrite-extraction` 分支上(提交 `0c11629f`),该分支尚未推送到任何远端,公开读者打不开。推送 note.md 分支后把引用改为固定提交的 blob 链接;何时推送由用户定。见 [02-migration-plan.md](02-migration-plan.md) 第 1 期前置条件。
- iOS 的 Bundle ID、开发者账号、应用图标(设计 §11),钥匙串服务名与访问组、沙盒目录、撤销是否由 CRDT owner 管理(现从桌面推断)、输入日志写入失败时怎样提示、iPad 快捷键表、导出文件名与 frontmatter([platform/ios.md](../spec/platform/ios.md))。
- Android 复用 `core/` 与 `session/`:这只是从“两份源码不分叉”的反目标推出来的,未经确认([later.md §2.1](../spec/platform/later.md))**[我的判断]**。

---

## 3. 未交付平台

| 平台 | 现状 | 现行 |
|---|---|---|
| Windows | **未交付**。插件二进制只有 `aarch64-apple-darwin` 与 `x86_64-unknown-linux-gnu` 两个目标(`plugins-src/write/manifest.v2.json` L8–9);宿主在其他系统上挂载原生编辑面会报不支持 | [later.md §1.1](../spec/platform/later.md)、[notemd-desktop §7.1](../spec/platform/notemd-desktop.md) |
| Intel Mac | **未交付**。manifest 没有 `x86_64-apple-darwin` 目标;`scripts/sumi/native-release.py` L10 的 `TARGETS` 却列了它,是否曾产出过 `[未定]` | — |
| Linux aarch64 | **未验收**。Arch 配方声明了 x86_64 与 aarch64,输入法 addon 只声明 x86_64;x86_64 的证据是干净容器依赖与 CLI 检查,装好后从包启动 GUI 没有证据,aarch64 没有任何验收 | [notemd-desktop §6.1](../spec/platform/notemd-desktop.md) |
| iOS/iPadOS | **计划中**,第 4 期;第一阶段自用、不公开发行(设计 §2 **[用户定]**) | [platform/ios.md](../spec/platform/ios.md) |
| Android | 只保留定位,不做新规划(设计 §2 **[我的判断]**) | [later.md §2.1](../spec/platform/later.md) |
| ESP32 | 同上 | [later.md §3.1](../spec/platform/later.md) |
| 桌面独立应用 | 只进路线图,iOS 上线后按设计 §9 评估(第 5 期,设计 §2 **[用户定]**) | [later.md §4.1](../spec/platform/later.md) |

---

## 4. 本期执行中发现的出入

来源:第 0 期任务 2–8 的执行报告、[03-notemd-contract.md](03-notemd-contract.md) §7、各规范作者在补漏轮次中的发现。已去重。每条:代码现状 vs. 旧说法;源路径;现行位置。

### 4.1 编辑体验与主题

- **主题数量**:代码有 6 个主题(`ink`、`dim`、`paper`、`sepia`、`crt`、`crt-blue`),默认 `dim`;旧主规范 §2.2 先列 4 个再追加 2 个 CRT,总览只列 4 个,也没写默认值。源:`plugins-src/write/src/contract.ts`、`src-tauri/src/sumi/mod.rs`。现行 [04 主题](../spec/04-editing-experience.md)。
- **主题跟随系统**:旧规范要求可跟随系统深浅色;代码只有 6 个显式主题,没有任何代码读取系统深浅色。源:`contract.ts`、`mod.rs` 的 `effective_appearance`。现行 [notemd-desktop §6.1](../spec/platform/notemd-desktop.md) `[未定]`。
- **GTK 系统主题是否渗入正文配色**:Linux 编辑面是 GTK3 TextView,系统 GTK 主题会不会改变它的颜色未测试。现行 [notemd-desktop §6.1](../spec/platform/notemd-desktop.md) `[未定]`。
- **设置面板与原生正文配色不同**:`ink`、`dim`、`paper` 三项,Web 面板(`plugins-src/write/src/style.css`)与宿主交给原生编辑器的值(`mod.rs`)不一致;旧规范没给色值。现行 [04 主题](../spec/04-editing-experience.md) 以原生值为准。
- **首次进入聚焦的计数**:旧主规范写 mac“首键起固定 2 秒窗”;现两端都是滑动 2 秒窗、≥4 次。源:`tauri-plugin-native-editor/src/linux_focus.rs`、CHANGELOG v6.1111.1。现行 [04 聚焦打字](../spec/04-editing-experience.md)。
- **重复居中不跳动**:只有 Linux 的修复与单测(提交 `e8e8e26a`,`linux.rs` 的 `native_focus_center_is_idempotent_offscreen`);macOS 没有同等验收。现行 [04 聚焦打字](../spec/04-editing-experience.md) macOS `[未定]`。
- **文末续写在 macOS 上**:修复已含在 macOS 发布 v6.1116.1 中,正式验收只有 Linux(6.1112.2 / Sumi 0.1.15)。源:`docs/superpowers/reports/2026-11-12-sumi-entry-release/README.md`。现行 [04 进入后从文末续写](../spec/04-editing-experience.md) macOS `[未定]`。
- **固定窗口规格**:旧主规范说可在设置选少量固定规格;偏好里没有窗口尺寸字段。源:`contract.ts`、`manifest.v2.json`。现行 [04 专注窗口与全屏](../spec/04-editing-experience.md) `[未定]`。
- **平铺窗口管理器下的固定尺寸**:Hyprland 等平铺窗口管理器怎样对待声明为固定尺寸的窗口、与 GTK 客户端装饰(CSD)怎么配合,没有结论。只在 [notemd-desktop](../spec/platform/notemd-desktop.md) 平台差异表的“窗口装饰”一行提到。`[未定]`
- **长按自动重复发声**:旧规范写“忽略自动重复”;macOS 不发声(`native/typing-monitor.h`),Linux 保留(`src/linux_typing.rs`、CHANGELOG v6.1112.1)。目标行为未定。现行 [04 打字音](../spec/04-editing-experience.md) `[未定]`。
- **光标呼吸周期**:CHANGELOG v6.1108.2 写六秒,v6.1108.5 改四秒;代码两端都是 4 秒(`native/editor.m`、`linux_focus.rs`)。只涉历史。现行 [04 光标](../spec/04-editing-experience.md)。
- **快捷键、空选区样式、粘贴、Markdown 复制在 Linux 上**:交付证据只有 macOS(v6.1108.1);Linux 只有“应用命令用 Ctrl”与“剪切先写剪贴板”两条。现行 [04 编辑操作、剪贴板](../spec/04-editing-experience.md) Linux `[未定]`。
- **候选区呈现**:旧候选规范与 v6.1110.2 更新日志写正文贴底;v6.1110.4 起改为非聚焦输入行原地不动。现行 [04 非聚焦输入](../spec/04-editing-experience.md)、[notemd-desktop §6.3](../spec/platform/notemd-desktop.md)。

### 4.2 字体

- **字体清单路径过时**:旧主规范 §2.2 指向的清单路径在基线上不存在;现位置 `plugins-src/write/resources/sumi/manifest.json`。现行 [05-fonts.md](../spec/05-fonts.md)。
- **两个 Plex 文件没有版本号**:manifest 只固定了 google/fonts 提交 `03c54f8f` 与 IBM/plex 提交 `222657a0`。现行 [05 七个字体文件](../spec/05-fonts.md) `[未定]`。
- **回退字体的描述**:旧规范写“系统等宽字体及系统中文回退”;代码的回退族名是 `Sumi System`,永不联网,不是一个选项;“等宽”未核对。源:`mod.rs` 的 `ensure_font`。现行 [05 回退与离线](../spec/05-fonts.md)。
- **许可文本是否进包**:资源目录有 6 个许可 txt 与 3 个 JSON,manifest 只把 3 个 JSON 标为 `bundled: true`;后台下载不写出许可文件(`plugins-src/write/backend/src/fonts.rs` 的测试)。许可 txt 实际是否打进插件包未核对。现行 [05 许可与来源](../spec/05-fonts.md)。
- **原生编辑桥 README 里的字体名过时**:`tauri-plugin-native-editor/README.md` 讲 `register_font_cascade` 的那段,举例时仍写着一个已退役的拉丁字体名(本文不复述),与现行字体目录不符。该 README 归 note.md,不迁;改不改由 note.md 定。现行字体清单见 [05 七个字体文件](../spec/05-fonts.md)。

### 4.3 纸页、存储与持久

- **空白页何时落地**:旧规范说“首次输入时才持久”;代码在**新建时**就写入 SQLite 目录项并向服务端发目录新建(`localDate` 为 null),只有文件要等第一次非空写入;空白页不会被自动清除。源:`src-tauri/src/sumi/mod.rs` L889、`write-core/src/catalog.rs` L70。现行 [01 §3.2](../spec/01-pages-and-storage.md)。
- **废纸篓 30 天**:旧规范暗示 30 天后清除;代码没有永久清除、清空或到期清理。30 天是 R2 备份对象的生命周期。源:`write-sync-worker/src/index.ts`、`write-sync-worker/README.md` L58。现行 [01 §3.3](../spec/01-pages-and-storage.md) `[未定]`。
- **“在当前页之后新建”**:代码以当前页为 `after_id`,同级按 UUID 排序深度优先,新页不一定紧跟当前页。源:`write-core/src/catalog.rs` L48。现行 [01 §2.1](../spec/01-pages-and-storage.md)。
- **摘要**:旧规范是“首行摘要加简短预览”;代码取裁剪后的前 80 个字符,空时显示“空白的一页”。源:`contract.ts` L53、`mod.rs` L828。现行 [01 §1.1](../spec/01-pages-and-storage.md)。
- **总览分页**:旧规范说分页;代码一次列出全部。源:`plugins-src/write/src/main.ts` L264。现行 [01 §2.2](../spec/01-pages-and-storage.md) `[未定]`。
- **Linux 上的翻页与总览没有 Omarchy 验收记录**:Linux 运行同一份插件前端与宿主代码,但 Omarchy 验收没有覆盖上一页、下一页与总览(`docs/superpowers/reports/` 下 Omarchy 系列报告与 `host-final-result.json`)。现行 [01 §2.2](../spec/01-pages-and-storage.md) 只标 macOS,Linux `[未定]`。
- **同 UUID 复制品与移动**:旧规范要求检测别名与内容分叉、移动改名后按 UUID 找候选;代码只观察本页文件名下的那对文件(`plugins-src/write/backend/src/durability.rs` L958–970),别名检测与按 UUID 移动都没有实现;从便携文件恢复总是分配新 UUID(`recovery.rs` L363–381)。现行 [01 §4.2](../spec/01-pages-and-storage.md)、[notemd-desktop §2.6](../spec/platform/notemd-desktop.md) `[未定]`。
- **持久回执的几条断言**:“检查点与云端确认不清除回执”“后台崩溃后按原序原 ID 重放”“读与 flush 不越过前面的写”三条已按 v6.1117.1 代码逐条核实(契约 §1.6 E2 列出行号:后台 `durability.rs` 没有删除 `sumi_edit_receipts` 的语句,`ack` 只删发件箱;宿主 `journal.rs` 按 `sequence` 重放并有杀进程恢复测试;`load`、`observe_page`、`flush` 前先 `drain()`)。余下限制:`list` 与 `excerpts` 不排空,不在“读不越过写”的保证之内。现行 [01 §5.4](../spec/01-pages-and-storage.md)、[03-notemd-contract.md](03-notemd-contract.md) §1.6。
- **停用、升级、重新启用的持久屏障**:只有自动化测试(`src-tauri/src/sumi/lifecycle_tests.rs`),两个平台都没有发布级实机验收(这些测试不按平台条件编译,两个平台都跑);关闭单个窗口“不停后台下载”仍未证明:代码里关窗不调用 `network.stop()`(只有 `before_exit` 调用),但没有测试断言关窗后下载与其他纸页同步继续。现行 [01 §5.5](../spec/01-pages-and-storage.md)、契约 §1.6 `[未定]`。
- **没有物理断电测试**:`fullfsync` 在 Linux 上是否刷写驱动器缓存无证据。源:`reports/2026-11-09-sumi-local-safety-release.md`、`src-tauri/src/sumi/journal.rs` L39–42。现行 [notemd-desktop §8.1](../spec/platform/notemd-desktop.md) `[未定]`。

### 4.4 Markdown 与行时间

- **`time_source` / timing 来源 0**:旧规范解释为“未知”;`write-core/WIRE.md` 把它保留给“从便携快照恢复到新 UUID 页”。现行 [02 §3.3](../spec/02-markdown-and-line-time.md)。
- **CRLF**:旧规范说规范化会被记录;代码直接拒绝 CR,要求导入前显式规范化,是否记录未定。源:`write-core/src/storage.rs` L129、`import.rs` L78。现行 [02 §1.1](../spec/02-markdown-and-line-time.md)。
- **公式与图表**:没有单独识别,按普通文本显示。源:`write-core/src/render.rs` L56。现行 [02 §1.3](../spec/02-markdown-and-line-time.md) `[未定]`。

### 4.5 同步与配对

- **HTTP 端点清单**:旧主规范缺 `/v1/pages/:id/update` 与 `/v1/pages/:id/sync`,以同步服务 README 为准(`write-sync-worker/README.md` L22–28)。现行 [03-sync.md](../spec/03-sync.md) 文首。
- **状态向量**:只做校验,v1 总是回放完整日志,服务端不发布权威状态向量(README L28)。现行 [03 §4.3](../spec/03-sync.md)。
- **隔离后的干净重建未实现**:旧规范的“从干净日志重建,再重放本机发件箱”没有实现,被隔离的页只能停在“停止合并、保留草稿”。源:README L34、`plugins-src/write/backend/src/coordinator.rs` L555。现行 [03 §7.1](../spec/03-sync.md) `[未定]`。
- **恢复演练口径不一致**:`write-sync-worker/README.md` 仍把“已部署环境的恢复演练”列为验收门槛,`write-sync-worker/CLOUD-ACCEPTANCE.md` L26 已记录冻结的 R2 备份在云端恢复到凭据隔离的新空间。需统一口径 **[我的判断]**。现行 [03 §8.1](../spec/03-sync.md)。
- **Linux 没有跨设备生产联调**:Secret Service 凭据已交付,但报告原话“远端投影及同步内核测试不等同于跨设备生产联调”(`reports/2026-11-10-sumi-omarchy-validation.md` L65);Linux 也没有真实配对的验收记录。现行 [00 §1.3](../spec/00-product.md) 第 3 条、[03 §2.3、§4.2](../spec/03-sync.md)。
- **配对文案三处不一**:邀请方界面叫“一次性配对码”,加入方叫“设备配对码”,规范叫“邀请文本”。源:`plugins-src/write/src/main.ts` L482–499、L52–55。是否统一 `[未定]`。现行 [notemd-desktop §9.2、§9.3](../spec/platform/notemd-desktop.md)。
- **邀请不含服务地址**:邀请是 `Invitation` 的 camelCase JSON(`spaceId`、`code`、`expiresAt`),桌面表单把地址和配对码分两栏填。源:`mod.rs` 的 `invitation_response`、`sumi-protocol/src/sync.rs`。iOS 无法自动带出地址,是否把地址并入邀请 `[未定]`。现行 [03 §2.3](../spec/03-sync.md)、[ios.md §3.1](../spec/platform/ios.md)、[ADR 0011](../adr/0011-ios-personal-use-identity-layer.md)。
- **邀请过剪贴板的风险**:可能被其他应用读到。这是 ADR 补充的风险,设计未提及([ADR 0011](../adr/0011-ios-personal-use-identity-layer.md))。
- **WebSocket 休眠**:只写在 `write-sync-worker/README.md`,旧规范没有。现行 [03-sync.md](../spec/03-sync.md) 以 README 为准。

### 4.6 桌面平台与宿主

- **Linux 编辑面是 GTK3,不是 Qt 6**:旧主规范 §4.1、§8 以 Qt 6 原型为 Linux 首选;代码用 GTK3 TextView overlay,变更见旧规范 `2026-11-10-sumi-omarchy-native.md`。源:`tauri-plugin-native-editor/README.md`。现行 [notemd-desktop §6.1](../spec/platform/notemd-desktop.md)、[ADR 0005](../adr/0005-native-text-controls.md)。
- **manifest `resizable:false` 与实际可缩放**:manifest 声明不可缩放(`plugins-src/write/manifest.v2.json` L37);宿主在 Linux 上对所有插件窗口强制可缩放(`src-tauri/src/desktop_policy.rs` L14–16),在 macOS 上对 Sumi 独立窗口也设为可缩放、可最大化(`src-tauri/src/plugin_runtime/windows.rs` L419–424)。现行 [notemd-desktop §1.2](../spec/platform/notemd-desktop.md)、[04 专注窗口与全屏](../spec/04-editing-experience.md)。§4.9 记录的规范内部不一致已解决。
- **owner 交接不转移上下文**:旧主规范 §8 说 Tab 与窗口切换时“转移选区、滚动与撤销上下文”;代码里第二个入口只去聚焦已有编辑面,没有转移。源:`mod.rs`。现行 [notemd-desktop §3.2](../spec/platform/notemd-desktop.md) `[未定]`,留给第 3 期。
- **投影写盘节奏**:旧规范写停笔后 0.5–1 秒;代码的检查点是距最后一次编辑 250 ms 或距首次变脏 2 s,先到先触发(`plugins-src/write/backend/src/durability.rs` 的 `checkpoint_due`);投影是否就在检查点内写盘未逐行核实。现行 [notemd-desktop §2.1](../spec/platform/notemd-desktop.md) `[未定]`。
- **投影改名**:旧规范说改名时 sidecar 一起改名;代码让宿主**拒绝**对投影改名和“另存为”(提示后不执行)。源:`src/lib/folder-view.svelte.ts`、`rename-pair.ts`、`tabs.svelte.ts` 的 `saveAs`。删除、搜索、索引、分享的成对处理未核实。现行 [notemd-desktop §2.5](../spec/platform/notemd-desktop.md)。
- **未核实的旧规则**:Source/Rich/原生三处共用一个文件 owner;改源码身份字段时暂停投影或同步。现行 [notemd-desktop §2.3](../spec/platform/notemd-desktop.md) `[未定]`。
- **全屏键与平台键位**:旧规范写一个跨平台全屏组合键;现 macOS 用 ⌘Return、⌘ 小键盘 Enter、⌃⌘F,Linux 只用 F11。Linux 另有 Ctrl+Y 重做;Esc 在 macOS 先关查找栏再打开菜单,在 Linux 直接打开菜单。Linux 的 Shift+Return、Shift+Tab、修饰键精确匹配只有单测,Ctrl+Y 与 Esc 既无单测也无实机证据。现行 [notemd-desktop §5.1、§6.2](../spec/platform/notemd-desktop.md)。
- **Fcitx5 for Sumi 在 macOS 上**:真机物理终验未执行;安装包本身未签名(`scripts/release-companions/fcitx5.json` 的 `packageSigned:false`),包内 App 已公证。现行 [notemd-desktop §6.3](../spec/platform/notemd-desktop.md) `[未定]`。
- **其余未做物理验证的**:Hyprland 分数缩放、XWayland、VoiceOver 等无障碍;性能矩阵(帧、能耗、内存、网络 p95)均未实测(`reports/2026-11-08-sumi-release.md`)。现行 [notemd-desktop §6.4](../spec/platform/notemd-desktop.md)、[later.md §6.4](../spec/platform/later.md)。
- **系统下限不同**:Sumi 原生写作要求 macOS 13(`tauri-plugin-native-editor/src/platform.rs`),宿主下限 macOS 11.0(`src-tauri/tauri.conf.json`)。有意为之,规范需写明。
- **Linux 插件进程环境**:宿主启动插件时环境白名单必须保留 `XDG_RUNTIME_DIR`,否则打字音连不上 PipeWire Pulse。已写入 [03-notemd-contract.md](03-notemd-contract.md) §1.6。

### 4.7 宿主契约与跨仓耦合

- **`host.sumi.*` 命令数**:设计写“约 20 个”;实际 UI 桥可调 20 个,另有仅供后台回调的 `host.sumi.service`。`host.sumi.sound_*` 三条在 `sound::dispatch` 里实现。契约 §7。
- **原生编辑桥不注册 JS 命令**:`tauri-plugin-native-editor` 只提供 Rust API 与 `SurfaceCommand`/`NativeEvent` 枚举;owner 状态在宿主 `mod.rs`。契约 §7。
- **契约外的跨仓耦合**:`plugins-src/write/src/main.ts` 直接 import `plugins-src/shared/shortcuts.ts` 与 `src/lib/sumi/i18n`;偏好默认值与范围在 `contract.ts` 和宿主 `Preferences` 各存一份。契约 §7,第 2 期定。
- **`Writing Page` frontmatter 没有 `generated` 署名**:是否符合 OKF §7 的人工撰写署名要求 `[未定]`。源:`write-core/src/storage.rs` 的 `serialize_pair`。契约 §3、§7。
- **没有宿主 tag 与插件版本的对应登记**:只能从 manifest 与 CHANGELOG 推断;契约把 v6.1117.1 + 插件 0.1.16 定义为 `host-contract v1`。契约 §7。
- **主窗口文件视图的 Tauri 命令**:已核实插件前端 `main.ts` 不调用这些 `sumi_*` 命令(调用点在宿主 `src/lib/sumi/{focus,session,recovery}.ts`);插件**后台进程**是否另有路径触达它们未逐文件审查 `[未定]`。契约 §1 的 B7 表。
- **设计漏列的反向依赖**:`notemd-plugin-sdk/Cargo.toml:8` 依赖 `plugin-protocol/`,`native-release.py` 的 `SOURCE_DIRS` 也列了它。见 [01-inventory.md](01-inventory.md) §6、[02-migration-plan.md](02-migration-plan.md) 第 2 期。

### 4.8 迁移相关

- **`write-core` 声明 MIT 但没有 LICENSE 文件**;`sumi-protocol` 没有声明。设计 §12 要第 1 期统一改为 Apache-2.0 **[我的判断]**。见 [02-migration-plan.md](02-migration-plan.md) 第 1 期。
- **同步服务的依赖多于设计列的三处**:另有 `link-toolchain.mjs` 软链、`deploy.sh:12` 写 `../tasks/sumi-sync`、`cloud-admin.py:11` 以源仓库根为基准、`:82` 写死 Wrangler 版本;账号 ID 只在 `worker/wrangler.toml`。见 [01-inventory.md](01-inventory.md) §5。
- **写死的源路径**:`scripts/sumi/native-release.py:11`、`test_native_release.py:42`,以及 `write-sync-worker/scripts/interop.mjs:5` 读 `write-core` 夹具,第 1 期改名后都要改。
- **读取宿主源文件的测试脚本**:`scripts/sumi/test-linux-credentials.sh` 编译 `src-tauri/src/sumi/credentials.rs`,`test_fullscreen_appearance.py` 读取 `src-tauri/src/sumi/mod.rs`;两者留在 note.md,但第 3 期切分这些文件后读取路径要核对,凭据逻辑若下沉,测试跟着拆([01-inventory.md](01-inventory.md) §3、[02-migration-plan.md](02-migration-plan.md) 第 3 期第 5 步)。
- **文件位置的更正**(给第 1–3 期计划):`journal.rs` 在宿主 `src-tauri/src/sumi/journal.rs`(由 `durability.rs` 经 `#[path]` 引入),不在插件后台;`desktop_policy.rs` 在 `src-tauri/src/desktop_policy.rs`,不在 `src-tauri/src/sumi/`。
- **规模**:原生编辑桥设计写约 12k 行,实测 `native/*.m` + `src/*.rs` 为 10,673 行(不含 .h 与 examples);宿主会话 8,685 行(`src-tauri/src/sumi/` 下 17 个文件,按 tag `v6.1117.1` 计)、插件后台三文件 5,926 行,与设计一致。
- **投影代码在内核里**:投影与三方导入在 `write-core/src/projection.rs`、`import.rs`;按设计 §5.4 投影只有桌面做,iOS 会链接到用不上的代码。是否移出内核、何时移 `[未定]`([ADR 0009](../adr/0009-page-store-vs-vault-projection.md))。
- **`sumi-protocol` 没有 README**,第 1 期验证命令只能按 `write-core` 的写法补。见 [02-migration-plan.md](02-migration-plan.md)。

### 4.9 规范内部待统一

- **macOS 独立窗口是否可缩放(已解决)**:原先 [04 专注窗口与全屏](../spec/04-editing-experience.md) 写 macOS 遵循 manifest、不可拖动改变大小,与 [notemd-desktop §1.2](../spec/platform/notemd-desktop.md) 矛盾。本仓库提交 `8b21bff` 已按代码修正 04:现写独立写作窗口在两个平台上都可以拖动改变大小。依据是基线代码 `src-tauri/src/plugin_runtime/windows.rs` L419–424:在 `#[cfg(target_os = "macos")]` 且为 Sumi 窗口时调用 `builder.resizable(true).maximizable(true).decorations(true)`;代码注释说明可缩放的原生 NSWindow 才能让绿色全屏按钮保持可用(退出全屏后也是)。两处现已一致,无待办。

### 4.10 iOS 相关

- **移动端存储位置**:旧主规范 §7 写移动端在应用私有 Documents 存 Markdown 快照与持久状态;设计 §5.4 写 iOS 只有沙盒里的纸页存储加导出 **[我的判断]**,未写放弃理由。现行 [ios.md §2.3](../spec/platform/ios.md) `[未定]`、[ADR 0009](../adr/0009-page-store-vs-vault-projection.md)。
- **iOS 导出能否保留行时间**:普通导出不含行时间,保留需导出 MD + sidecar 归档;iOS 是否提供 `[未定]`。现行 [ios.md §3.3](../spec/platform/ios.md)。
- **iOS 的 TLS**:插件后台 `tokio-tungstenite =0.28.0` 用 `rustls-tls-native-roots`,在 iOS 上可能不可用(未实测);`reqwest` 的 `rustls-tls` 在 iOS 上的根证书行为也未核实。源:`plugins-src/write/backend/Cargo.toml`。[ADR 0010](../adr/0010-ios-uikit-textkit2-uniffi.md)、[ADR 0012](../adr/0012-shared-session-module.md)。
- **身份层是否已与纸页层分开**到能换登录方式 `[未定]`([ADR 0011](../adr/0011-ios-personal-use-identity-layer.md))。
- **移动端电量与后台重连**:旧主规范 P2 阶段要求的验收项不在 M0–M5 里。现行 [ios.md §4.2](../spec/platform/ios.md) `[未定]`。
- **二维码配对**:桌面只输出邀请文本,加二维码要改桌面插件(设计 §10.1 **[我的判断]**)。现行 [later.md §6.2](../spec/platform/later.md)。
