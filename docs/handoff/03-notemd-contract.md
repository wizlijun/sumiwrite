# 03 · 与 note.md 的契约(host-contract v1)

本文件记录玄霜写作(Sumi Write,插件 ID `notemd.sumi`)与宿主 note.md 之间互相约定的全部内容。对应设计文档 §5.3(五部分)。

- **基线**:源仓库 `main` 的 `969f8e73`,宿主发布 tag `v6.1117.1`。**`host-contract v1` 就是这一基线上已发布行为的快照**,不是新设计。
- **读法**:凡写“现值”的,都是从代码逐项读出的;读不出来的标 `[未定]`,并记入 [`04-known-gaps.md`](04-known-gaps.md)。代码与旧规范冲突时以代码为准,冲突记在第 7 节。
- **来源路径**一律相对源仓库 `note.md` 根目录。
- 归属判定见 [`01-inventory.md`](01-inventory.md);迁移分期见 [`02-migration-plan.md`](02-migration-plan.md)。

---

## 1. 宿主接口契约 `host-contract v1`

由 sumiwrite 定义,note.md 实现。插件 manifest 的 `engines.notemd` 继续表达最低宿主版本。

**当前 manifest 现值**(`plugins-src/write/manifest.v2.json`):

| 项 | 现值 |
|---|---|
| 插件 ID | `notemd.sumi` |
| 插件版本 | `0.1.16` |
| `engines.notemd` | `>=6.1111.1` |
| `kind` | `native`(二进制 `bin/notemd-sumi`,目标 `aarch64-apple-darwin`、`x86_64-unknown-linux-gnu`) |
| `capabilities` | `editor.native`、`editor.write`、`editor.open`、`vault.read`、`vault.write`、`editor.kit` |
| 文件视图 | `file_views[id=writing]`,`surface: native-editor`,`open_command: read-writing`,选择器为扩展名 `md` 且 frontmatter `type` 为 `Writing Page` |

宿主进入 Sumi 的授权门:`src-tauri/src/sumi/mod.rs` 的 `authorize()` 要求调用方插件 ID 恰为 `notemd.sumi`,且 manifest 同时含 `editor.native`、`editor.write`、`vault.read`、`vault.write` 四项能力,缺一项返回 `CAPABILITY_DENIED: <能力名>`。

### 1.1 表 A:`host.sumi.*` 命令

来源:`src-tauri/src/sumi/mod.rs` 的 `dispatch()`;能力映射 `src-tauri/src/plugin_runtime/host_api.rs`(`method_capability`);路由 `src-tauri/src/plugin_runtime/ui_rpc.rs`(`host.sumi.` 前缀走 `crate::sumi::dispatch`)。插件侧调用封装为 `plugins-src/write/src/main.ts` 的 `host.sumi.${method}`。

**通用规则**

- 这 20 个命令全部由 UI 桥(插件窗口的 WebView)调用,**全部**要求能力 `editor.native`(`host_api.rs`),未知方法返回 `METHOD_NOT_FOUND`。
- 参数为 JSON 对象,键名按下表原样(`pageId`、`fontFamily` 等是 camelCase)。缺少必填键时错误文案为 `缺少参数 <键名>`。
- 失败统一以 `ERR_INTERNAL` + 中文错误文案返回;用户可读的错误文案属于契约的一部分,但其措辞不保证稳定,插件不得据文案分支。**例外**:`CAPABILITY_DENIED: …` 前缀与 `METHOD_NOT_FOUND`。
- 除 `host.sumi.state`(不支持原生编辑的平台上直接返回 `available:false`)外,所有命令要求 Sumi 窗口(`window_label(notemd.sumi, "main")`)已打开,否则返回 `Sumi 窗口未打开`。
- “状态对象”指 `SumiState`(见 §1.3),由 `state_value()` 生成。

| 命令 | 参数 | 返回 | 用途 |
|---|---|---|---|
| `host.sumi.state` | 无 | `SumiState`。不支持原生编辑的平台:`{available:false, reason, pages:[], activePageId:null, preferences:<默认值>, sync:{connected:false,pending:0}, saveState:"saved"}` | 读取当前全部纸页、激活页、外观偏好、同步状态、保存状态 |
| `host.sumi.page` | `action`(必填):`create` / `open` / `next` / `previous` / `delete` / `restore`;`pageId`(`open`、`delete`、`restore` 必填);`requestId`(`create`、`next`、`delete` 必填,UUID,作新建幂等标识);`fromPageId`(可选,与当前激活页不符则拒绝) | `SumiState` | 新建、打开、前后翻页、删除到废纸篓、从废纸篓恢复。有活动编辑面或正在输入法组字时拒绝切换(`请先完成当前输入并保存纸页,再切换`);删除当前页前先预取相邻页 |
| `host.sumi.mount` | `pageId`;`bounds:{x,y,width,height}`(DOM 坐标;Linux 另可带 `viewportWidth` 用于换算为逻辑单位) | 成功:`{id, generation}`(编辑面句柄)。该页已被另一个窗口持有:`{kind:"existing_owner", page_id}` | 为纸页挂载原生编辑面并成为其 owner |
| `host.sumi.detach` | `surface:{id, generation}` | `null` | 摘下编辑面并释放 owner;句柄已过期则 `编辑面已过期`;输入法组字中被拒绝 |
| `host.sumi.bounds` | `surface:{id, generation}`;`bounds`(同 mount;Linux 可带 `viewportWidth`) | `null` | 更新编辑面位置与大小 |
| `host.sumi.visible` | `surface`;`visible:boolean`;可选 `preparePanel:boolean` | `null` | 显示/隐藏编辑面。`visible=false` 且 `preparePanel=true` 时发 `PreparePanel`(为覆盖面板做准备)而非 `SetVisible` |
| `host.sumi.focus` | `surface` | `null` | 把键盘焦点交给原生编辑面 |
| `host.sumi.focus_existing` | `pageId` | `{requested:true}` | 该页已有 owner 时,把已有编辑窗口(或主窗口的标签)提到前台;不跨越窗口传递编辑面能力 |
| `host.sumi.preferences` | `preferences`(`Preferences` 全量对象);可选 `preserveFont:boolean`(为 true 时保留当前字体、忽略 `preferences.fontFamily`) | `SumiState` | 保存外观偏好并立即应用到编辑面。取值范围见表 A 下的校验表 |
| `host.sumi.fonts` | 无 | `FontState` | 读取六个字体组合的下载状态、已选字体、待应用字体 |
| `host.sumi.font_select` | `fontFamily`(必须是已登记的字体组合别名) | `FontState` | 选用字体;未下载则在后台下载,完成后才写入偏好并应用,过程中的状态靠 `sumi-state` 推送。失败以 `sumi-error` 推送 |
| `host.sumi.fullscreen` | 可选 `queryOnly:boolean` | `{fullscreen:boolean}` | `queryOnly=true` 只查询;否则切换全屏并返回切换后的值 |
| `host.sumi.command` | `action`(必填)。`close`:隐藏 Sumi 窗口(先走 `before_close`)。其余动作作用于当前激活页:`save`(重试待提交编辑、落地原生草稿、`flush`);`zoom_in`、`zoom_out`(字号 ±2,夹在 8–96)、`zoom_reset`(回到默认 22) | `null` | 窗口与文档级命令。其他 `action` 值返回 `不支持的写作命令`;无激活页返回 `没有当前纸页`;输入法组字中拒绝 |
| `host.sumi.restore_projection` | `pageId` | `{page_id, raw, revision, recovery_path}` | 把 vault 里被外部改坏或缺失的投影文件,按本机事实源重新写出;原文件先保全到 `recovery_path`。该页有未关闭的编辑面时拒绝(草稿不丢弃) |
| `host.sumi.export` | `pageId`;`format`:`markdown`(只含正文,保存名 `Sumi Write.md`)或 `archive`(含逐行时间,保存名 `Sumi Write.zip`) | `{saved:boolean}`(用户在系统保存对话框取消则为 `false`) | 导出纸页。若该页由别处持有,拒绝;由当前窗口持有则先 `flush` |
| `host.sumi.pair` | `serviceUrl`(非空字符串);`invitation`(配对码的 JSON 字符串,字段 `spaceId`、`code`、`expiresAt`) | `SumiState` | 本设备接受配对码,加入同步空间。同步连接未初始化时返回 `同步连接正在初始化` |
| `host.sumi.invite` | 无 | `{invitation:string}`(配对码的 JSON 字符串) | 为本空间生成给另一台设备用的配对码 |
| `host.sumi.sound_state` | 无 | `SoundState` | 读取打字音效的设置、系统权限、引擎状态;若已在运行且设置一致则不重新配置 |
| `host.sumi.sound_set` | `{enabled:boolean, preset:"typewriter"\|"thock"}`(多余键被拒绝) | `SoundState` | 保存打字音效设置(偏好键 `typingSound`,与外观偏好分开存)并配置引擎 |
| `host.sumi.sound_request_permission` | 无 | `SoundState` | 仅在用户显式点击时请求系统输入监听权限(macOS/Linux);绝不在挂载或启动时调用 |

**`host.sumi.preferences` 的取值范围**(`Preferences::validate`,不合法返回 `无效的写作外观设置`):

| 字段 | 范围 |
|---|---|
| `theme` | `ink` / `dim` / `paper` / `sepia` / `crt` / `crt-blue` |
| `fontFamily` | 六个字体组合别名之一(见 §1.4) |
| `caretMotion` | `breathing` / `steady` |
| `fontSize` | 8 – 96 |
| `lineHeight` | 1 – 3 |
| `maxColumns` | 20 – 200 |
| `bottomInset` | 0 – 2000 |
| `focusTyping`、`startFullscreen` | boolean,缺省均为 `true` |

默认值(`Preferences::default`):`theme=dim`、`fontFamily=Sumi Plex`、`fontSize=22`、`lineHeight=1.6`、`maxColumns=80`、`bottomInset=0`、`caretMotion=breathing`、`focusTyping=true`、`startFullscreen=true`。该默认值在 `contract.ts` 的 `defaultPreferences` 里有一份镜像,两处必须一致。

**宿主 → 插件窗口的推送消息**(`push()` 经 `windows::push_to_window(notemd.sumi, "main", …)` 发给插件窗口,同属契约面):

| `type` | 载荷 | 含义 |
|---|---|---|
| `sumi-state` | `{state: SumiState}` | 状态变化(保存完成、字体应用完成、同步状态变化等) |
| `sumi-action` | `{action}` | 原生菜单动作转交:`new_page`、`menu`、`save`、`export`、`close`、`settings`、`zoom_in`、`zoom_out`、`zoom_reset` |
| `sumi-error` | `{message}` | 后台异步失败(字体下载/应用失败、日志保存失败等) |
| `sumi-focus-owner` | `{pageId}` | 请求插件窗口把焦点交给已有 owner 的编辑面 |
| `sumi-window-state` | `{visible:boolean}` | 窗口显示确认,用于恢复被隐藏的编辑面 |

### 1.2 表 B:原生编辑面能力

来源:`tauri-plugin-native-editor/src/lib.rs`(跨平台接口与校验)、`platform.rs`(macOS/Linux 实现分发)。

**重要事实**:`tauri-plugin-native-editor` **不注册任何 JavaScript 命令**(文件头注释原文:`This crate registers no JavaScript commands`)。它是一组只供宿主 Rust 代码调用的 API;插件 WebView 只能通过表 A 的 `host.sumi.*` 间接使用它。设计文档 §5.3 写的“命令与事件”在这里对应 Rust 函数、`SurfaceCommand` 枚举与 `NativeEvent` 枚举。平台支持:`is_supported()` 仅 macOS 与 Linux 为真,其他平台所有操作返回 `native editor is not supported on this platform`。

**B1 外观**

| 能力 | 签名 / 字段 | 约束 |
|---|---|---|
| `Appearance` | `font_family`、`font_size`、`line_height`、`foreground`、`background`、`max_columns`、`bottom_inset`、`locale`(默认 `en`)、`caret_motion`(`breathing`/`steady`,默认 `breathing`)、`focus_typing`(默认 `true`) | `font_size` 8–96,`line_height` 1–3,`max_columns` 20–200,`bottom_inset` 0–2000;颜色须通过校验(`red` 这类名字被拒绝) |
| `SurfaceCommand::SetAppearance{appearance}` | 更新外观 | 同上校验 |
| `SurfaceCommand::SetLocale{locale}` | 只更新界面标签语言,不打断组字、选区、光标 | `normalize_locale`:`zh`、`ja`,其余一律 `en` |
| `register_font(window, path, expected_family)` | 注册受信任的单个字体文件(仅本进程) | `path` 必须是绝对路径;无 JS 入口 |
| `register_font_cascade(window, alias, families)` | 把已注册的若干字体按序拼成一个别名;首个为主字体(拉丁),后续补缺字 | `families` 个数 1–8,均非空 |
| `SurfaceConfig.appearance` | 挂载时的初始外观 | 同 `Appearance` |

**B2 光标**

| 能力 | 说明 |
|---|---|
| `CaretMotion` | `Breathing`(默认)/ `Steady`,经 `Appearance.caret_motion` 传入 |
| `TextRange{start,length}`、`Viewport{start,offset}` | 选区与视口,**单位为 UTF-16 码元**;`start`/`end` 必须落在字符边界(`utf16_boundary`),`offset` 为有限数且绝对值不超过 10000 |
| `SurfaceConfig.selection` / `.viewport` | 挂载时的初始选区与视口,同样校验 |
| `NativeEvent::Selection{surface_id, generation, revision, range}`、`NativeEvent::Viewport{…, viewport}` | 原生侧上报选区/视口变化;不修改文本 |

**B3 IME 交接**

| 能力 | 说明 |
|---|---|
| `NativeEvent::Composition{surface_id, generation, revision, active}` | 原生侧上报组字开始/结束 |
| `SurfaceState.composing` | `inspect()` 返回的组字状态 |
| 宿主规则 | 组字期间:`transaction()` 直接以 `composition active` 拒绝;`host.sumi.detach`、`host.sumi.command`、`host.sumi.page` 切换均拒绝(`请先完成输入法组合`/`请先完成当前输入并保存纸页,再切换`) |
| Linux 候选框 | 候选窗由 `linux_candidates*.rs`、`linux_caret.rs` 提供;Fcitx5 for Sumi 的打包不属于本契约(见 `01-inventory.md`) |

**B4 焦点与可见性**

| 能力 | 说明 |
|---|---|
| `SurfaceCommand::Focus` | 把键盘焦点交给编辑面 |
| `SurfaceCommand::SetVisible{visible}` | 显示/隐藏 |
| `SurfaceCommand::PreparePanel` | 隐藏前的面板准备(覆盖层出现前使用) |
| `SurfaceCommand::SetBounds{bounds}` | 位置与大小;`bounds` 四项必须有限、宽高非负 |
| `menu_command(command) -> bool` | 主线程原生菜单分发:只有真正处于 key window 的 Sumi 响应者才消费,返回 `true`;其他文本框保留系统默认行为 |

**B5 编辑事务**(宿主 ↔ 原生面)

| 能力 | 说明 |
|---|---|
| `mount(window, SurfaceConfig, EventHandler)` | 挂载。`SurfaceConfig{surface_id, generation, revision, bounds, appearance, document, selection, viewport}`;`surface_id` 非空且不超过 200 字节,`revision` 不超过 `i64::MAX` |
| `NativeEvent`(`kind` 标签,snake_case) | `Edit{surface_id,generation,base_revision,range,replacement}`;`Clipboard{…,revision,ranges,cut}`;`Paste{…,base_revision,range,text?,html?,rtf?,literal}`;`Selection`;`Viewport`;`Composition`;`Action{…,revision,action,range}` |
| `EventHandler` | `Fn(NativeEvent) -> Result<EventReply,String>`,在原生主线程**同步**执行。肯定的编辑确认(ACK)要求同步写入宿主日志;**绝不在其中重入 AppKit** |
| `EventReply{revision, projection?, clipboard_text?, draft_error?}` | `draft_error` 非空表示日志写入失败:保留草稿为只读、不推进原生已接受修订号 |
| `Projection{document, selection}`、`RenderDocument{text, runs}`、`StyleRun{range, bold, italic, strike, heading(0–6), quote, link?}` | 受控富文本投影,在下一次原生输入之前同步装入;样式范围必须落在字符边界 |
| `SurfaceCommand::ApplyDocument{base_revision, revision, document, selection}` | 把文档整体应用到编辑面;要求 `revision >= base_revision`,选区合法 |
| `command(window, surface_id, generation, cmd)` | 发送一条 `SurfaceCommand` |
| `command_and_then(…, complete)` | 在**同一个主线程回合**内先执行原生命令、成功后执行 `complete`,中间不会混入输入;命令校验或执行失败则 `complete` 不执行 |
| `inspect(window, surface_id, generation) -> SurfaceState` | `SurfaceState{surface_id, generation, revision, text, selection, composing, textkit2, visible, viewport}` |
| `transaction(window, surface_id, generation, prepare)` | 在同一主线程回合内检查、准入并渲染一个宿主事务;原生输入不会看到“核心已前进、投影未应用”的中间态;组字中拒绝 |
| 打字音效监听 | `configure_typing_monitor(app, enabled, handler?)`、`typing_monitor_status(app)`、`request_typing_permission(app)` 返回 `TypingMonitorStatus{enabled, permission_granted, listening}`;`TypingSoundEvent{surface_id, generation, role}` 的 `role` 为 `key`/`space`/`enter`/`delete`/`modifier`/`key_up`/`space_up`/`stop`——**只有角色,绝不含字符内容** |

**B6 owner 交接**

owner 是“当前持有某纸页编辑面的 `(窗口, 标签页, 编辑面)`”,记录在宿主的 `Owner`(`src-tauri/src/sumi/mod.rs`)里,**不属于 `tauri-plugin-native-editor`**。契约面是:

- `host.sumi.mount` 返回 `{kind:"existing_owner", page_id}` 表示别处已持有;
- `host.sumi.focus_existing{pageId}` 请求持有方前台化,宿主不传递任何窗口/编辑面能力;
- 持有方窗口收到推送 `sumi-focus-owner{pageId}`;主窗口持有时宿主向 `main` 窗口发 `sumi-focus-owner{page_id, tab_id}` 事件;
- 编辑面身份是 `{id, generation}`:`generation` 在每次重新挂载时递增,旧句柄的任何命令返回 `编辑面已过期`;
- `detach` 与 owner 释放在同一生命周期租约内完成,并发的 `mount` 不会丢失新装入的 owner。

**B7 宿主主窗口文件视图用的 Tauri 命令(补充)**

文件视图(`file_views`)的编辑面开在宿主**主窗口**里,由 `src/lib/sumi/` 与 `NativeFileView` 通过 Tauri 命令(不是 `host.sumi.*`)驱动。这些命令只接受标签为 `main` 的窗口(否则 `CAPABILITY_DENIED: main editor window required`),且都要求 `plugin_id == notemd.sumi` 并通过 `authorize()`。注册处 `src-tauri/src/lib.rs` 的 `generate_handler!`。这部分是宿主内部实现,**留在 note.md**(归属见 `01-inventory.md`),此处列出只为让“宿主改了命令名插件会不会坏”可检查——已核实 `plugins-src/write/src/main.ts` 不含 `invoke`、也不含任何 `sumi_*` 命令名(grep 0 命中);调用点在宿主前端 `src/lib/sumi/{focus,session,recovery}.ts`。插件包的其他入口(`contract.ts`、样式)不发命令。后台进程是否另有路径触达这些命令 `[未定]`(未逐文件审查)。

| Tauri 命令(参数,均以 snake_case 传入) | 说明 |
|---|---|
| `sumi_state(plugin_id)` | 同 `host.sumi.state` |
| `sumi_open_path(plugin_id, path, tab_id, expected_page_id?)` | 按文件路径打开,返回 `Opened` 或 `existing_owner` |
| `sumi_page_path(plugin_id, page_id)` | 由页面 ID 解析投影文件路径:`{page_id, epoch, path, vault_root}` |
| `sumi_mount(plugin_id, page_id, tab_id, bounds)` | 挂载 |
| `sumi_focus_existing(plugin_id, page_id)`、`sumi_focus_owner(plugin_id, page_id, tab_id)` | owner 前台化 |
| `sumi_restore_projection(plugin_id, page_id, tab_id?)` | 同 `host.sumi.restore_projection` |
| `sumi_recovery_probe(plugin_id, path)`、`sumi_recover_new(plugin_id, request_id, evidence, normalize_crlf)` | 从外部文件探测/恢复为新纸页 |
| `sumi_flush(plugin_id, page_id, tab_id, surface_id?, generation?)` | 落盘 |
| `sumi_detach(…, surface_id, generation)`、`sumi_close(plugin_id, page_id, tab_id)` | 摘下/关闭 |
| `sumi_source_save(plugin_id, page_id, tab_id, base_revision, raw)` | 源码模式保存 |
| `sumi_rebase_draft(plugin_id, page_id, tab_id, submitted, accepted, draft)` | 草稿变基 |
| `sumi_bounds(…, surface_id, generation, bounds)`、`sumi_visible(…, visible)`、`sumi_focus(…)` | 编辑面控制 |

宿主向 `main` 窗口发的事件:`sumi-focus-owner`、`sumi-path-changed{page_id, old_path}`。

### 1.3 表 C:插件前端契约(`contract.ts`)

来源:`plugins-src/write/src/contract.ts`。插件界面与宿主之间交换的数据形状,是表 A 的载荷类型。

| 导出 | 形状 |
|---|---|
| `Theme` | `'ink' \| 'dim' \| 'paper' \| 'sepia' \| 'crt' \| 'crt-blue'` |
| `Preferences` | `{theme, fontFamily:string, caretMotion:'breathing'\|'steady', focusTyping:boolean, startFullscreen:boolean, fontSize, lineHeight, maxColumns, bottomInset:number}` |
| `Page` | `{id:string, excerpt:string, deleted:boolean}`(`excerpt` 为正文前 80 个字符) |
| `SumiState` | `{available:boolean, reason?:string, pages:Page[], activePageId:string\|null, navigationVersion?:number, preferences:Preferences, sync:{connected:boolean, pending:number, message?:string}, saveState:'saved'\|'saving'\|'projection-pending'\|'error'}` |
| `SurfaceHandle` | `{id:string, generation:number}` |
| `Bounds` | `{x,y,width,height:number}` |
| `FontStatus` | `{family, status:'not_downloaded'\|'downloading'\|'ready'\|'error', downloadedBytes, totalBytes:number, error?:string\|null}` |
| `FontState` | `{fonts:FontStatus[], selectedFont:string, pendingFont:string\|null}` |
| `SoundState` | `{enabled:boolean, preset:'typewriter'\|'thock', permission:'granted'\|'required'\|'unsupported', status:'off'\|'ready'\|'permission_required'\|'unavailable', error?:string}` |
| `fontPresets` | 六组 `[别名, 说明]`:`Sumi Plex`、`Sumi WenKai`、`Sumi Zhaohua`、`Sumi Youcha`、`Sumi Fangsong`、`Sumi CRT` |
| `defaultPreferences` | 同 §1.1 的默认值 |
| `pageLabel(page, fallback)`、`preferencesFromForm(form, currentFont?, currentStartFullscreen=true)` | 纯函数;后者在前端复刻了表单侧的范围校验(与宿主 `Preferences::validate` 一致) |

`SumiState.saveState` 的取值逻辑(`state_value`):任一页有 `error`、待重试的本地编辑、或未落地的原生草稿 → `error`;任一页持久修订号落后于内存修订号 → `saving`;任一页投影出错 → `projection-pending`;否则 `saved`。`sync.pending` 为待发送的 outbox 条目数。

**契约外的耦合,第 2 期已解决**(见 §7):迁移前 `plugins-src/write/src/main.ts` 还 import 了 `../../shared/shortcuts` 与 `../../../src/lib/sumi/i18n`,二者在宿主仓库里,不在上表。现在 sumiwrite 自带 `apps/notemd-plugin/src/shortcuts.ts` 与 `i18n.ts`,不再 import 宿主文件。

### 1.4 表 D:后台服务握手与服务消息

来源:`sumi-protocol/src/service.rs`、`durability.rs`、`fonts.rs`、`sync.rs`、`lib.rs`;宿主侧传输 `src-tauri/src/sumi/service.rs`;插件后台侧 `plugins-src/write/backend/src/runtime.rs`。**这是宿主与插件原生后台进程之间的私有通道**,不对 WebView 开放:`host.sumi.service` 与 `service.request` 在 UI 桥一律回 `METHOD_NOT_FOUND`(`ui_rpc.rs` 的测试断言)。

**D1 传输**

| 方向 | 方法 | 说明 |
|---|---|---|
| 宿主 → 后台 | `service.request`,载荷 `{method, params}` | 经 `PluginProcess::request` |
| 后台 → 宿主 | `host.sumi.service`,载荷 `{session, instance, method, params}` | 仅 `notemd.sumi` 的原生进程可调(`process.rs`、`host_api.rs`);宿主在 `service::callback` 里校验 `session` 与 `instance`,过期/旧进程的事件被拒绝 |

**D2 握手(现值)**

| 项 | 现值 | 出处 |
|---|---|---|
| 服务协议版本 `VERSION` | `1`(宿主 `service.rs` 与后台 `runtime.rs` 各一份常量,必须相等) | `service.rs`、`runtime.rs` |
| 宿主发 `hello` | `{version: 1}` | `service.rs` `binding()` |
| 后台回 `Hello` | `{version: 1, instance: <UUID>, capabilities: ["durability.observe_page.v1"]}` | `runtime.rs` `"hello"` 分支;`Hello{version:u32, instance:String, capabilities:Vec<String>}`,`capabilities` 缺省为空(旧后台不报能力) |
| 宿主校验 | `hello.version == 1` 且 `instance` 为合法 UUID,否则 `Sumi 后台协议不兼容,请同时更新宿主和插件` | `service.rs` |
| 能力常量 | `OBSERVE_PAGE = "durability.observe_page.v1"` | `sumi-protocol/src/service.rs` |
| 能力门禁 `Hello::check_request` | 仅当请求为 `method=="durability"` 且 `payload.method=="observe_page"` 时,要求 `capabilities` 含 `durability.observe_page.v1`,否则报 `Sumi 插件版本过旧,缺少安全的本机文件读取能力。请更新 Sumi 插件后重新打开;本机稿件仍保留`。其余请求(`sound`、`fonts`、`durability` 的其他方法)对旧后台一律放行 | `sumi-protocol/src/service.rs` 与其单测 |
| `open` | 宿主 → 后台:`{version, instance, session, vault, database, fontCache}`(路径均须为绝对路径);`session` 由宿主为每个 `Backend` 生成 | `service.rs`、`runtime.rs` `Open` |

模块头注释写明:**“既有的 fonts/sound 保持版本 1;新增可选能力靠 `capabilities` 字符串声明。”** 这条是本契约“新增可选能力”规则的现成先例。

**D3 宿主 → 后台的服务消息**

| 方法 | 载荷 | 说明 |
|---|---|---|
| `hello` | `{version}` | 握手 |
| `open` | 见 D2 | 绑定会话 |
| `fonts` | `{version, cache, payload: FontRequest}` | 字体服务,见 D5 |
| `durability` | `{instance, session, payload: durability::Request}` | 持久化(SQLite/投影)请求,见 D4 |
| `network` | `{instance, session, payload:{operation, page?, server?, invitation?}}`;`operation` ∈ `start` / `stop` / `status` / `prepare`(需 `page`)/ `pair`(需 `server`、`invitation`)/ `invite` | 同步协调 |
| `sound` | `{instance, session, payload}`;`operation` ∈ `configure{enabled, preset, token, expires_at_ms?}` / `play{token, roles[], expires_at_ms}` / `stop{token}` / `status`(返回 `{ready}`);`roles` 取值 `key`/`space`/`enter`/`delete`/`modifier`/`key_up`/`space_up` | 打字音效引擎 |

后台对所有 `deny_unknown_fields` 的请求拒绝多余字段;后台在 `closing` 状态拒绝新请求。

**D4 `durability::Request`**(`sumi-protocol/src/durability.rs`,serde 标签 `method` + `params`,snake_case,拒绝未知字段)

`Create(Create)`、`Load{page_id}`、`ObservePage{page_id}`(需能力 `durability.observe_page.v1`)、`CommitLocal(LocalEdit)`、`CommitRemote{incoming, generation, revision}`、`Flush`、`List`、`Excerpts`、`SetDeleted{page_id, deleted}`、`Preferences{key}`、`SetPreferences{key, value}`、`SaveHeader{page_id, expected_revision, header}`、`ReadBaseline{page_id}`、`AcceptImportedBaseline{page_id, observed}`、`ImportLocal{edit, observed}`、`ImportProjectionExtensions{page_id, generation, expected_revision, observed}`、`RestoreProjection{page_id, generation}`、`Outbox`、`OutboxCount`、`DirectoryOutbox`、`Ack{op_id}`、`AcknowledgeDirectory{op_id}`、`ApplyDirectory{entry}`、`RecordInbox{incoming, generation}`、`HasDocument{page_id}`、`AppliedIncoming{receipts}`、`PendingInbox{page_id}`、`ReceiveRemote{incoming, generation}`。

载荷类型(同文件):`Loaded`、`Create`、`LocalEdit`、`Outgoing`、`PublishedBaseline`、`PageObservation`、`ObservedFiles`(`unwritten`/`published`/`pending`/`external`/`unavailable`)、`ProjectionIdentity{path, sha256}`、`DurableEvent`(`Committed`/`Saved`/`Failed`)、`RecordedIncoming`、`IncomingReceipt`、`CommitReceipt`、`CommittedImport`。`edit_receipt()` 的摘要带版本字节 `1`:**改变该摘要的线上身份需要协议迁移,不得静默重试**(源码注释)。

后台 → 宿主的 `durable` 回调把 `DurableEvent` 推给宿主(`runtime.rs`),宿主据此更新 `durable_revision` 并向插件窗口推送 `sumi-state`。

**D5 字体服务**(`sumi-protocol/src/fonts.rs`)

| 项 | 现值 |
|---|---|
| 别名 `ALIASES`(六个) | `Sumi Plex`(PostScript:`IBMPlexMono-Light`、`IBMPlexSansSC-Light`)、`Sumi WenKai`(`LXGWWenKaiMonoLite-Regular`)、`Sumi Zhaohua`(`ZhaohuaTypeWriter-Light`)、`Sumi Youcha`(`YouchaSanz-Light`)、`Sumi Fangsong`(`ZhuqueFangsong-Regular`)、`Sumi CRT`(`Unifont`) |
| `FontRequest`(标签 `operation`,camelCase,拒绝未知字段) | `statuses` / `files{family}` / `download{family}`;**请求里不接受路径或 URL**(单测断言) |
| `FontResponse`(标签 `kind`) | `statuses{statuses:FontStatus[]}` / `files{files:FontFile[]\|null}` / `downloaded` |
| `FontStatus` | `{family, status, downloadedBytes, totalBytes, error}`;`status` 取值 `not_downloaded` / `downloading` / `ready` / `error`(宿主还识别瞬时值 `idle`) |
| `FontFile` | `{path, postscript}`;宿主在使用前校验:`postscript` 与期望一致、是普通文件而非符号链接、规范化后位于授权的缓存目录内 |
| 缓存目录 | `<应用本地数据目录>/sumi/fonts/v1`(由宿主在 `open` 时传给后台) |
| 分工 | 下载地址与许可只存在于插件的字体目录里,**不进入共享协议**(`fonts.rs` 文件头) |

**D6 同步身份**(`sumi-protocol/src/sync.rs`):`Identity{serverUrl, spaceId, deviceId}`;`Invitation{spaceId, code, expiresAt}`(`Debug` 输出把 `code` 打码);`AccessToken{access_token, expires_at}`(接受 camelCase 别名)。长期设备密钥**不跨越**这条边界。

**D7 后台 → 宿主的回调方法**(`background_request`,`src-tauri/src/sumi/mod.rs`)

`durable`(事件通知)、`current`、`editor_state`(返回激活页、持有情况、各页 state vector)、`directory`(目录变更)、`remote`(合入远端更新)、`status`(同步状态)、`auth_load`、`auth_pair`、`auth_token`(系统钥匙串身份与令牌)。所有非 `durable` 回调须带与宿主工作区根一致的 `root`,否则 `Sumi后台工作区绑定不一致`;`remote`、`directory` 受“变更闸门”约束,同步停止后到达的旧事件被拒绝。

### 1.5 版本规则

1. **新增可选能力**(新的 `host.sumi.*` 命令、新的可选参数/返回字段、新的推送消息类型、新的 `capabilities` 字符串,且旧插件/旧宿主不用它也照常工作):升**次版本**,`host-contract v1.x`。**[提议规则,非现有行为]** 宿主对缺失的能力应当降级而不是拒绝(现有先例只有一个,参照 `observe_page` 的先例:旧后台只在需要该能力的那一个请求上被拒,且文案指向“更新插件”)。
2. **改变或删除既有行为**(改名/删除命令、改参数或返回的含义、收紧取值范围、改变服务协议 `VERSION`、改变 `edit_receipt` 摘要的线上身份、改变 owner/组字的拒绝规则):升**主版本**,`host-contract v2`。
3. **主版本变化必须两个仓库配套发版**(见 §4)。
4. 每次变更同时更新:本文件、`CHANGELOG`(两个仓库各自)、插件 manifest 的 `engines.notemd`(若需要更高的宿主下限)。
5. 契约版本与插件版本、宿主版本互相独立。当前对应关系:`host-contract v1` = 宿主 `v6.1117.1` 基线 + 插件 `0.1.16`。
6. **机械检查**:`bash docs/check.sh check_contract` 按固定 tag `v6.1117.1`(脚本里的 `TAG` 变量)用 `git show` 读源仓库的 `src-tauri/src/sumi/mod.rs`、`src-tauri/src/plugin_runtime/host_api.rs` 与 `src-tauri/src/plugin_runtime/process.rs`,不读工作区;抓取其中每个 `host.sumi.*` 名称(含只在 `host_api.rs`/`process.rs` 出现的 `host.sumi.service`),要求本文件都出现过;宿主新增命令而本文未登记,检查即失败。基线换 tag 时同步改 `TAG`。

### 1.6 停止、持久回执与插件进程环境(补漏,已按 v6.1117.1 代码核实)

追加于 §1.4/§1.5 之后,不改既有编号。产品层说法归 spec 01,此处只写契约层。

**E1 停止/停用/退出/升级的次序**(`src-tauri/src/sumi/mod.rs` `before_exit`、`freeze_workspace`、`cleanup_plugin`、`resume_plugin`;`service.rs` `MutationGate`、`stop_network`)

1. 置全局 `PLUGIN_QUIESCING`,此后拒绝创建新会话与重新显示窗口;各工作区相位 `ACTIVE -> QUIESCING`。覆盖**全部已打开工作区**,含隐藏页。
2. 停打字音,逐窗口 `before_close`(停止新输入、过组字屏障)。
3. `network.stop()`:先 `MutationGate::close()`(`accepting=false` 且代数加一),再向后台发 `network stop`,最后 `drain()` 等在途回调结束。此后到达的 `remote`/`directory` 回调被拒(“belongs to a stopped synchronization run”)。
4. `freeze_workspace`:flush 位置,`durable.flush()`(排空持久队列并尝试投影)。若 flush 因外部冲突失败:逐页 `load` 并核对已接受的 `revision` 等于内存文档 revision,全部一致则放行,冻结快照里 `projected=false`;任一页不一致或数据库错误,返回“正文尚未完成持久化,不能停用”,**仍阻止**停用/退出。
5. 全部成功后相位为 `QUIESCED`。失败则回滚:清快照、相位回 `ACTIVE`、`network.resume()`、窗口恢复。
6. 触发点:应用退出(`lib.rs` 的 exit 流程调用 `before_exit`);停用/卸载(`plugin_runtime/commands.rs`)与升级替换(`plugin_runtime/lifecycle.rs`)调用 `cleanup_plugin`(内部先 `before_exit`);升级成功后 `resume_plugin`。`resume_workspace` 恢复前逐页核对 epoch/generation/revision 与冻结快照一致,不一致则报错并保留草稿。
7. **启动票据**:`start_network()` 在调用时同步取 `MutationGate` 代数作票据;`stop_network()` 的 `close()` 令旧票据失效,即使旧启动 future 还没被轮询,`open_if_current` 也返回 false。恢复必须经 `network.resume()` 取新票据。
8. 关闭**单个窗口**只走第 2 步,不停后台下载、不停其他纸页的同步:`[未定]`——已核实的部分:`before_close_inner`(`mod.rs` L3106 起)只处理正在关闭的窗口里的 owner,不调用 `network.stop()`;`network.stop()` 只在 `before_exit`(L3290)里调用。但没有测试断言“关窗后后台下载与其他纸页同步继续”,故整体仍不算已证明。

**E2 持久回执**(`sumi-protocol/src/durability.rs` `edit_receipt`;`plugins-src/write/backend/src/durability.rs`;宿主 `src-tauri/src/sumi/durability.rs`)

- 回执表在后台 SQLite 内:`sumi_edit_receipts(op_id PK, digest, page_id, epoch, generation, revision)`;`sumi_local_update_identity(op_id, digest)`;`sumi_echo_receipts`(远端回声)。回执与数据在同一事务写入(`record_local_receipt` 在 `transaction` 内)。
- `digest` 覆盖 `(1u8, remote, edit, imported)`。同 `op_id`:摘要相同则**重放返回原回执**(`receipt()` 返回 `found`);摘要不同则拒绝,错误文案 `operation ID reused with different durable payload`。唯一例外:已确认的本地操作经云端回来,带新宿主 revision,按 `local_echo` 判为回声(返回 `None`,不算冲突)。
- 宿主侧 `validate_receipt` 用 `journal::receipt(request)` 重算并与后台回执比对,不一致报“后台保存回执与待确认修改不一致”,通过后才 `journal.acknowledge`。
- 事件语义:`DurableEvent::Committed{page_id,revision}` 在回执持久化后宿主确认时发出;`Saved{..,projected,projection_error}` 在投影结束后另发;`Failed` 表示失败。投影被外部冲突挡住时 `Saved.projected=false`,并不撤销已发出的 `Committed`(测试 `projection_conflict_allows_local_writing_reopen_and_never_reports_projected`)。
- **checkpoint 与云端 ACK 都不清除回执**(已按 v6.1117.1 代码核实):`sumi_edit_receipts` 唯一的写入是后台 `durability.rs` L52(`record_receipt` 的 INSERT),全仓库没有对它的 DELETE;`ack`(L391–403)只删 `outbox` 与 `sumi_outbox_generation`;`checkpoint_page`(L641–655)只删 `sumi_dirty_projection`;`write-core` 的删除只针对 outbox、document_deltas、sumi_directory_outbox。`sumi_local_update_identity` 的 DELETE 只出现在测试代码里。
- **后台崩溃后按原序原 ID 重放**(已按 v6.1117.1 代码核实):宿主输入日志 `src-tauri/src/sumi/journal.rs` 的 `pending()`(L80)按 `sequence` 自增列排序取出未确认请求,请求带原 `op_id`;`append_then`(L59 起)在同一把锁内写日志,同 `op_id` 内容不同则拒绝;`acknowledge`(L94 起)只在回执完全一致时删除。宿主 `durability.rs` 的 `from_backend`(L105 起,注释 L107“Recovery precedes every newly queued request, including Load/ObservePage”)先重放日志再接新请求;`run`(L239 起)失败时把同一请求放回队首重试(L275)。测试 `kill_after_accepted_before_ipc_recovers_both_edits`(`journal.rs` L234,经 `kill_and_reopen` L207)断言两次编辑按原序恢复。`service.rs` 注释“only the durable FIFO may replay operations with proven durable idempotency identities”与此一致。
- **读和 flush 不越过前面的写**(已按 v6.1117.1 代码核实):后台 `durability.rs` 的 `load`(L201)、`observe_page`(L209)、`flush`(L216)都先调用 `drain()`(L778 起)排空待写队列再读或投影。`list` 与 `excerpts` 不排空,只读目录与摘要,不在此保证之内。
- P10“同一 CRDT 更新回声幂等”:`sumi_echo_receipts` 与 `local_echo` 是其实现入口;完整性 `[未定]`。

**E3 插件进程环境(Linux)**:`src-tauri/src/platform.rs` 的环境白名单在 Linux 为 `HOME PATH LANG LC_ALL TERM USER TMPDIR XDG_RUNTIME_DIR`,注释说明默认 PulseAudio/PipeWire 客户端靠它找会话 socket,其余变量不继承;单测 `linux_plugin_spawn_preserves_runtime_without_secrets`(`plugin_runtime/process.rs`)断言保留 `XDG_RUNTIME_DIR` 且不泄露秘密变量。宿主若改白名单,须保留该变量。

---

## 2. 依赖方向

两个方向都按**固定 tag** 引用,不跟分支;两者在 crate 层面不成环。 **[我的判断]**(设计 §5.3 第 2 条;其中“共享快捷键 TypeScript 的处理方式”第 2 期已定为 sumiwrite 自带一份,同属 [我的判断],第 5 条签名与上架归属亦是。)

| 方向 | 引用什么 | 怎么引用 |
|---|---|---|
| note.md 宿主 → sumiwrite | 内核(`write-core`)与服务契约(`sumi-protocol`) | 固定 tag,命名 `core-vX.Y.Z`(sumiwrite 侧打 tag)。宿主的 `Cargo.toml` 里写 `git` + `tag` |
| sumiwrite 插件壳 → note.md | `notemd-plugin-sdk` | 固定 tag,取宿主已发布的 `v6.*` tag |

- **本地联调**:在任一侧的 `Cargo.toml` 用 `[patch]` 指向另一侧的本地目录;提交前去掉。
- **现状**(基线):宿主与插件后台都按 `path` 依赖 `write-core`、`sumi-protocol`(`src-tauri/Cargo.toml`、`plugins-src/write/backend/Cargo.toml`;`sumi-protocol/Cargo.toml` 的 `write-core = { path = "../write-core" }`);尚无 `core-v*` tag。第 1 期迁移完成时才打第一个。
- `core-vX.Y.Z` 的版本号与 `host-contract` 的版本号**是否联动**:`[未定]`,见 §7。
- 共享快捷键 TypeScript(`plugins-src/shared/shortcuts`)的归属与同步方式:第 2 期已定,sumiwrite 自带 `apps/notemd-plugin/src/shortcuts.ts`,note.md 的原件不动,两者不同步。

---

## 3. vault 投影约定

这是**桌面插件独有**的行为;iOS 没有 vault,只有纸页存储(见 `docs/spec/01-pages-and-storage.md`)。

| 项 | 约定 | 出处 |
|---|---|---|
| 目录 | `<vault>/inbox/writings/`,不存在则创建;沿途任一层是符号链接或非目录即拒绝(`writing directory must not be a symlink`) | `write-core/src/projection.rs` `paths()` |
| 正文文件 | `inbox/writings/YYYY-MM-DD-NN.writing.md`。`YYYY-MM-DD` 是本机本地日期,`NN` 是两位序号(`{:02}`);`(日期, 序号)` 在宿主目录表里唯一(唯一索引 sumi_filename) | `write-core/src/catalog.rs` `Entry::filename()` |
| sidecar | 同目录 `YYYY-MM-DD-NN.writing.meta.json`(正文文件名去掉 `.md` 后加 `.meta.json`)。内容为行级时间与行 ID 元数据,`schema` 为 `1` | `projection.rs`;`write-core/src/storage.rs` |
| 文件名约束 | 必须以 `.writing.md` 结尾,不含 `/`、`\`、NUL,不以 `.` 开头;空白页尚未生成文件名 | `projection.rs` `paths()`;`sumi_page_path` |
| frontmatter | 必含 `type: Writing Page`、`write_schema: 1`、`page_id`、`write_epoch`、`write_metadata: sidecar-v1`;其余键(如 `author`、`sumi_creation`)原样保留。校验读回时 `type`、`write_metadata`、`schema`、`page_id`、`write_epoch`、正文哈希、行数与行 ID 序列全部一致才接受 | `storage.rs` `serialize_pair` / 解析 |
| 原子性 | **一对文件不是双文件原子事务**,只是可恢复的投影:每个文件用临时文件 `.sumi-<uuid>.tmp` 写入、`fsync`、重命名;发布前比对基线哈希,遇到非“上一次发布”也非“本次待发布”的内容即报 `external projection change; preserve and import before writing` | `projection.rs` `publish()` |
| 外部修改 | 外部改动被保全并走三方合并/导入,而不是覆盖(`ObservedFiles::External`、`import.rs`);`host.sumi.restore_projection` 是修复入口 | `sumi-protocol/src/durability.rs`;`mod.rs` |
| 文件打开 | manifest 的 `file_views` 选择器以 `type: Writing Page` 匹配,在宿主主窗口里用原生编辑面打开 | `manifest.v2.json` |

**OKF 写入规矩**:`Writing Page` 是 note.md 的 OKF `type` 登记值,登记在 `src/lib/okf/concept.ts` 的 `CONCEPT_TYPE.writingPage`(注释:“Sumi 原生写作纸页,正文由人书写”)。本插件的写入遵守宿主的硬规矩——非保留 `.md` 必须带可解析的 YAML frontmatter 与非空 `type`;不得写名为 `index.md`/`log.md` 的概念文档;人机署名不混。规范性文档:

- 源仓库 `docs/okf-v0.2-format-constraints.md`(OKF v0.2 格式约束)
- 源仓库 `docs/plugin-v2-development.md` §9.1(插件写 `.md` 必读,含 `type` 登记表与自检 `pnpm okf:lint <目录>`)
- 源仓库 `docs/okf-v0.2-conformance-audit.md`(一致性审计与整改进度)

> **与 OKF 署名规则的关系**:`Writing Page` 的 frontmatter 现值里**没有** `generated` 字段(`storage.rs` `serialize_pair` 只写上表五键)。OKF 要求人工撰写内容“须带 `generated: { by: human:<id>, at }`”(`plugin-v2-development.md` §9.1)。纸页现状是否满足该要求:`[未定]`,记入 §7。

新增的 `type` 值须先在宿主 `concept.ts` 登记;sumiwrite 无权自行引入新的 `type`。

---

## 4. 发版配合

| 情形 | 做法 |
|---|---|
| 只改插件壳或内核,**契约版本不变**(`host-contract` 不变,`engines.notemd` 不需上调) | **只发插件包**:sumiwrite 产出待签名构建物 → note.md 签名并上架。宿主不必发版 |
| 契约**次版本**升级(新增可选能力) | 宿主先发布带新能力的版本;插件随后提高 `engines.notemd` 到该宿主版本并使用新能力。插件可在旧宿主上继续以旧能力运行时,不必提高下限 |
| 契约**主版本**升级,或服务协议 `VERSION` 变化 | **配套发版**:两边同一轮发布;宿主在握手失败时给出“请同时更新宿主和插件”(现有文案),就是为这一情形准备的 |
| 宿主改了契约内的命令或推送消息 | 属于上两行之一;宿主一侧的 `check_contract` 对应检查是防止“宿主静默改了一个未登记命令”的最后一道网 |

现行流程(基线):插件包由 `scripts/release-plugins.sh sumi` 的 `release_sumi()` 构建、打 `.notemdpkg`(每个架构一个 ZIP),用 minisign 分离签名为同名 `.minisig`,索引由 `scripts/gen-plugin-index.mjs` 生成;脚本**只打包与签名,不上传**。宿主发版见源仓库 `scripts/release.sh` 与 `CLAUDE.md` 的“发版:每次都写增量 CHANGELOG”。

两个仓库各自有 CHANGELOG;影响契约的变化,两边都要在“未发布”区写一条用户可感知的条目。

---

## 5. 签名与上架

**留在 note.md。** 密钥和门禁都在那一边。

| 事项 | 归属 | 现状出处 |
|---|---|---|
| 插件包签名(minisign) | note.md | `scripts/release-plugins.sh`:密钥环境变量 `NOTEMD_PLUGIN_SIGNING_KEY`(默认 `~/.tauri/notemd-plugins.key`);公钥写在宿主 `src-tauri/src/plugin_runtime/market.rs` 的 `PLUGIN_REGISTRY_PUBKEY` |
| 宿主发版、公证 | note.md | `scripts/release.sh`(含 Apple 公证等待与重试) |
| 插件市场上架 | note.md | `plugins-registry/`、`scripts/gen-plugin-index.mjs` |
| 待签名构建物与校验清单 | **sumiwrite 交付** | 见下 |

**sumiwrite 交付物**(本设计的 `[我的判断]`;状态 `[未定]`。sumiwrite 侧已交付,证据:[`build-artifact.sh`](https://github.com/wizlijun/sumiwrite/blob/notemd-plugin-v0.1.16/apps/notemd-plugin/scripts/build-artifact.sh)、[`verify-stage.py`](https://github.com/wizlijun/sumiwrite/blob/notemd-plugin-v0.1.16/apps/notemd-plugin/scripts/verify-stage.py)(tag `notemd-plugin-v0.1.16`)。note.md 侧在分支 `sumi/plugin-from-sumiwrite`(9288b33d),待用户合并;合并后补 note.md 的 blob 链接再改为已交付):

入口:`apps/notemd-plugin/scripts/build-artifact.sh --target <三元组> --out <目录> [--debug]`。`--debug` 用调试构建,供 note.md 的开发安装,发版不用。非 `--debug` 时工作树有已跟踪文件的改动即拒绝运行,保证 `source_commit` 属实。`<目录>` 必须不存在或为空;产出恰好是 `stage/` 与 `checklist.json`。脚本不读取、不需要任何签名或公证凭据。

1. `stage/`(**未签名**安装布局,与现行 `release_sumi()` 装配一致):`manifest.json`(即 `manifest.v2.json`)、`bin/notemd-sumi`、`ui/`(Vite 产物,不含 `sounds/`)、`resources/sounds/`。
2. `checklist.json`:

   ```json
   {"schema":1,"plugin":"notemd.sumi","version":"0.1.16","target":"aarch64-apple-darwin",
    "engines_notemd":">=6.1111.1","host_contract":1,"core_tag":"core-v0.1.0",
    "source_tag":"notemd-plugin-v0.1.16","source_commit":"<40 位>",
    "files":{"bin/notemd-sumi":"<sha256>","manifest.json":"<sha256>"}}
   ```

   `files` 覆盖 `stage/` 下每个普通文件,键为 POSIX 相对路径,值为 SHA-256;`stage/` 内不允许符号链接。`source_tag` 仅当 HEAD 恰在 `notemd-plugin-v<version>` 上时填写,否则为 `null`。`core_tag` 取自后端 `Cargo.toml` 中 `write-core` 与 `sumi-protocol` 的同一 tag。
3. 目标三元组只接受 `aarch64-apple-darwin`、`x86_64-apple-darwin`、`x86_64-unknown-linux-gnu`,且 manifest 的 `binary[三元组]` 必须是 `bin/notemd-sumi`。
4. 门禁在脚本内完成,note.md 不再重复:Linux 目标跑 `verify-linux-binary.py`;`resources/sounds` 跑 `verify-sounds.py`;字体目录与许可字节、无字体载荷由 `verify-stage.py` 检查。
5. 校验:`apps/notemd-plugin/scripts/verify-stage.py --verify-checklist <checklist.json> --stage <stage 目录>`,重算 SHA-256,缺文件、多文件、不符均非零退出。

note.md 收到后:比对 `source_commit` → `verify_checklist` → macOS 目标签名并公证二进制,替换 `bin/notemd-sumi`(签名身份、团队 ID、公证凭据只在 note.md 一侧,按引用取用)→ 打包 → minisign → 生成索引 → 上架。签名密钥与公证凭据**不进入** sumiwrite。

**`SUMIWRITE_DIR` 约定**:note.md 里需要本仓库文件的脚本统一读环境变量 `SUMIWRITE_DIR`(默认 `../sumiwrite`),缺目录时报清楚的错。note.md 的 `pnpm build` 与 `scripts/release.sh` 因此都会跑 `scripts/prepare-sumi-font.py`,必须有 sumiwrite 检出;它填充的缓存 `src-tauri/resources/sumi` 不被宿主打包。是否把它从宿主构建里去掉,由 note.md 决定(记入 [04-known-gaps.md](04-known-gaps.md) §4.8)。

---

## 6. 来源索引

读过的源文件(相对 `note.md` 根目录):`src-tauri/src/sumi/mod.rs`、`sound.rs`、`service.rs`、`fonts.rs`、`export.rs`;`src-tauri/src/plugin_runtime/host_api.rs`、`ui_rpc.rs`、`process.rs`;`src-tauri/src/lib.rs`(命令注册);`tauri-plugin-native-editor/src/lib.rs`、`platform.rs`;`sumi-protocol/src/{lib,service,durability,fonts,sync}.rs`、`Cargo.toml`;`plugins-src/write/src/contract.ts`、`main.ts`、`manifest.v2.json`;`plugins-src/write/backend/src/runtime.rs`、`sound.rs`;`write-core/src/{projection,catalog,storage}.rs`;`src/lib/okf/concept.ts`;`docs/plugin-v2-development.md`;`scripts/release-plugins.sh`;设计文档 `docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md` §5.3。

## 7. 出入与未定(同步记入 `04-known-gaps.md`)

1. **“约 20 个 `host.sumi.*` 命令”**:实际 UI 桥可调 20 个(表 A),另有一个仅供后台进程回调用的 `host.sumi.service`(表 D1,不在 `mod.rs` 的 `dispatch` 里,只在 `host_api.rs`/`process.rs`/`service.rs`)。设计文档的“约”可改为精确值。
2. **“原生编辑面的命令与事件”**:`tauri-plugin-native-editor` 实际**不注册任何 JS 命令**(`lib.rs` 文件头),设计文档措辞容易误导;本文按 Rust API + `SurfaceCommand`/`NativeEvent` 枚举记录。
3. **“owner 交接”**:owner 状态在宿主 `src-tauri/src/sumi/mod.rs` 的 `Owner`,不在原生编辑插件里;契约面见表 B6。
4. **契约外的跨仓耦合**:`plugins-src/write/src/main.ts` import `../../shared/shortcuts` 与 `../../../src/lib/sumi/i18n`;`contract.ts` 与宿主 `Preferences` 的默认值、范围两处各存一份。第 2 期已定:sumiwrite 自带 `shortcuts.ts` 与 `i18n.ts`,`main.ts` 不再 import 宿主文件;`contract.ts` 与宿主 `Preferences` 的两份默认值与范围第 2 期未处理,留待下次契约版本变化时由两边一起定 `[未定]`。
5. **`core-vX.Y.Z` 与 `host-contract` 版本是否联动** `[未定]`。当前宿主以 `path` 依赖内核,无 tag。
6. **服务协议 `VERSION=1` 与 `host-contract v1` 的关系**:二者数值同为 1 但含义不同(前者是私有通道线上版本,后者是整个耦合面的快照版本);主版本升级时是否必须同时改 `VERSION` `[未定]`。
7. **`Writing Page` frontmatter 缺 `generated` 署名**:见 §3 末尾提示。是否符合 OKF §7 的人工撰写署名要求 `[未定]`。
8. **`host.sumi.sound_*` 三条命令**不在 `mod.rs` 的 `dispatch()` 内实现,而在 `sound::dispatch`;仍由 `mod.rs` 路由,故被 `check_contract` 覆盖。
9. **构建物与校验清单的具体格式**:第 2 期已定,见 §5;sumiwrite 侧已交付,note.md 侧待用户合并(`[未定]`)。
10. **宿主发版 tag 与插件版本的对应记录**:宿主 `v6.1117.1` 与插件 `0.1.16` 的对应只能从 manifest 与 CHANGELOG 间接推断,无单一登记处;本文把这组对应写作 `host-contract v1` 的定义。
