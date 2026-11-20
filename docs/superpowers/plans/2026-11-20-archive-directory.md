# 归档目录与写作工作区 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 桌面上每台机器一个与 vault 无关的写作工作区(纸页库、输入日志、同步凭据),投影写到用户自选的归档目录;已有用户升级后原样接管现有纸页库。

**Architecture:** 内核 `projection` 改为以“归档目录”为根:不再拼 `inbox/writings`,运行时不建目录,并新增无基线首写 `publish_first`。插件后台 `open` 改收 `workspace` + `archive`(可空),服务协议 `VERSION` 2;后台在库里记下当前归档目录,目录一变就清空投影队列与基线、全部页重新发布。宿主用 `<app_data>/sumi/workspace.json` 定位工作区,首次升级时接管旧哈希目录,并新增三条命令:查询归档目录、改归档目录、从归档目录选文件恢复。

**Tech Stack:** Rust(write-core、sumi-protocol、notemd-sumi-backend、note.md `src-tauri`,工具链 `cargo +1.99.0`)、rusqlite、TypeScript/Vitest(插件 UI)、Svelte/Vitest(宿主恢复界面)、bash(`docs/check.sh`)。

**Spec:** `docs/superpowers/specs/2026-11-20-archive-directory-design.md`(下称“设计”)。现行规范在 `docs/spec/`,任务 1 先改规范与契约。

## Global Constraints

- `workspace.json` 路径 `<app_data>/sumi/workspace.json`,内容 `{"schema":1,"workspace":"<ID>","archive":"<绝对路径>"|null}`;纸页库 `<app_data>/sumi/<工作区 ID>/documents.sqlite3`,输入日志同目录;钥匙串 `profile` 就是工作区 ID。
- 工作区 ID 只允许 `[0-9a-f-]`,长度 1–64(旧哈希目录名 64 位十六进制,新装为小写 UUID v4)。宿主和后台都要校验。
- 投影文件直接放在归档目录里:`<归档目录>/YYYY-MM-DD-NN.writing.md` 与 `<归档目录>/YYYY-MM-DD-NN.writing.meta.json`。
- 归档目录本身可以是符号链接,先 canonicalize;**运行时绝不创建归档目录本身**。只有接管时、取 `<vault>/inbox/writings/` 而它又不存在的情况下,宿主经 `create_archive_under` 建一次。
- 改归档目录时,旧目录里的文件一律不删、不搬。
- 无基线首写分四种情况:没有同名文件 → 写入;逐字节相同 → 采用为基线;能确认是本页旧版本(`parse_pair` 通过,且 sidecar 的 `page_id`、`write_epoch` 与本页一致)→ 覆盖;其他 → 冲突,不覆盖。
- 版本:内核与协议 `0.2.0`,tag `core-v0.2.0`;服务协议 `VERSION = 2`;`host-contract v2`;插件 manifest `version` `0.2.0`,tag `notemd-plugin-v0.2.0`;`verify-stage.py` 的 `HOST_CONTRACT = 2`。
- 内核错误文案(英文,原样):`ARCHIVE_UNAVAILABLE = "archive directory is unavailable"`;`FIRST_WRITE_CONFLICT = "archive holds a different file under this name; recover it before writing"`。
- 宿主错误文案(中文,原样):未设置归档目录时为 `尚未设置归档目录`;选到不可用目录时为 `归档目录不可用`;`workspace.json` 损坏时为 `写作工作区配置损坏，请检查 <路径>`。
- 作者署名:`human_actor_for_vault(Some(归档目录))`;归档目录未设置或不可用时传 `None`。
- `home-content-edit` 只在归档目录位于当前打开的 vault 内时发出。
- 规范、契约、ADR 用简体中文;提交信息用英文祈使句,结尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 工具链 `export PATH="$HOME/.cargo/bin:$PATH"`,`cargo +1.99.0`。sumiwrite 的模块测试命令见各模块 README「Verification」段,`docs/check.sh` 必须输出 `OK`。
- note.md 的工作只在 worktree `~/git/note.md-archive`(分支 `sumi/archive-directory`,起点 note.md `main` `c7c1df89`)里做,不动 `~/git/note.md` 检出。note.md 两份 CHANGELOG 的「未发布」区都要有面向用户的条目。
- 不签名、不公证、不上传、不读凭据或钥匙串;推送、合并、推送 tag 都要先得到用户明确同意(见停点 A、B)。
- 红线:不得在 Swift 里重写 CRDT、行时间、合并或恢复逻辑(本计划不涉及 iOS 代码)。

## Review Focus

1. **会话中途归档目录消失又恢复**(移动硬盘拔掉再插上)。投影作业应该留在队列里,不能在原路径建影子目录;目录回来后,下一次检查点要补上投影。测试:任务 3 `archive_removed_mid_session_keeps_jobs_and_republishes_after_restore`。
2. **`workspace.json` 被手改坏或截断**。不能重新接管,否则可能接到另一套库;也不能覆盖这份文件,而是报 `写作工作区配置损坏，请检查 <路径>`。测试:任务 5 `corrupt_config_is_reported_and_left_untouched`。
3. **把归档目录改成当前同一个目录**,或者选到 `<app_data>/sumi` 里面。前者什么都不做,不清基线、不重新发布;后者拒绝。测试:任务 7 `choosing_same_archive_keeps_baselines`、`archive_choose_rejects_app_data_directory`。
4. **纸页开着时切换或关闭 vault**。会话不停;`home-content-edit` 只在新 vault 包含归档目录时发出。测试:任务 6 `vault_switch_keeps_session_and_retargets_home_content_edit`。
5. **归档目录路径里有中文和空格**(如 `~/文稿/玄霜 归档`)。读写 `workspace.json` 往返后,规范化路径比较仍然相等,不会误判为“目录变了”而清掉基线。测试:任务 5 `config_round_trips_non_ascii_archive`;任务 3 `reopen_with_same_non_ascii_archive_keeps_baselines`。

---

### Task 1: 规范、契约 v2 与 ADR 0013(只改文档)

**Files:**
- Modify: `docs/spec/01-pages-and-storage.md` §4.2(约 L164)
- Modify: `docs/spec/platform/notemd-desktop.md` §2、§2.1(约 L46–58),新增 §2.0
- Modify: `docs/handoff/03-notemd-contract.md`:标题行、§1.1 表 A、§1.4 表 D、§1.5、§2 现状行、§3、§4、§7
- Create: `docs/adr/0013-workspace-and-archive-off-vault.md`
- Modify: `docs/handoff/04-known-gaps.md`、`docs/handoff/02-migration-plan.md`(第 2 期「步骤」)、`docs/spec/MAPPING.md`(文末退役表)
- Modify: `docs/check.sh`(`check_files` 加 0013;`check_adr` 期望数 `12` → `13`;`check_contract` 的 `'host-contract v1'` → `'host-contract v2'`;`check_retired` 的词表加 `'vault 投影'`)
- 扫描替换:`docs/spec/`(不含 `MAPPING.md`)与 `docs/handoff/0[0-3]-*.md` 中所有作为现行做法出现的“vault 投影”(当前 18 处)

**Interfaces:**
- Produces: 契约 v2 的条目(后续各任务照此实现):
  - 后台 `open` 字段 `version, instance, session, workspace, archive, database, fontCache`(`archive` 可为 `null`),`VERSION` 2;
  - 回调 `params.root` 的值为工作区 ID;
  - 新增后台请求 `Request::SetArchive { archive }`;
  - 新宿主命令 `host.sumi.archive_get` → `{"archive":string|null,"available":bool,"untaken":[string]}`;`host.sumi.archive_choose` → 与 `archive_get` 同形;`host.sumi.recovery_choose` → `{"path":string|null}`;
  - `sumi_page_path` 返回 `{"page_id","epoch","path","archive"}`。

- [ ] **Step 1: 先改 check.sh,运行确认失败**

改上面列的四处 `check.sh`。运行 `bash docs/check.sh`,预期失败:缺 0013,ADR 数为 12,缺 `host-contract v2`,并报出 `retired term: vault 投影`。

- [ ] **Step 2: 写 ADR 0013**

ADR 0013 的标题是“纸页库与归档目录脱离 vault”。`类型:新`,二级标题依次为 `## 背景`、`## 决定`、`## 放弃的方案`、`## 后果`、`## 来源`。各段内容:

- 决定:取设计 §5.1–5.3。
- 放弃的方案:设计 §4 的方案 B(独立桌面应用),以及“只改归档目录”。
- 后果:要写明“ADR 0009 的『vault 投影』自此称『归档投影』”,以及“多个旧纸页库不合并”。
- 来源:用相对链接指向设计文档。

- [ ] **Step 3: 改规范**

01 §4.2:

- 标题改为“纸页存储与归档投影的分层”,状态行保持 `[已交付:macOS+Linux]` 及原有证据,因为分层本身已交付;
- 正文“vault 投影”改为“归档投影”,写明投影写到本机设置的归档目录;
- 另起一句“归档目录取代 vault 内固定目录 `[未定]`:待配套发版,见 notemd-desktop §2.0”。

notemd-desktop:

- 新增 `### 2.0 写作工作区与归档目录`,状态 `[未定]`:待配套发版(`host-contract v2`),交付后补证据。内容依次写:工作区(取设计 §5.1)、首次升级接管(§5.2 的五步)、归档目录路径规则与改目录流程(§5.3)、无基线首写四种情况的表。
- §2 标题改为“归档投影与外部修改的三方合并”。
- §2.1 正文路径改为 `<归档目录>/YYYY-MM-DD-NN.writing.md`。删掉“目录不存在就创建”,改为“归档目录必须已存在;本身可以是符号链接;运行时不创建”。§2.1 状态改为 `[未定]`,注明 v6.1117.1 已交付的是 `<vault>/inbox/writings/`,保留原证据链接作出处。

- [ ] **Step 4: 改契约到 v2**

- 标题 `host-contract v1` → `host-contract v2`;§1.5 写明 v1 → v2 是主版本升级,且服务协议 `VERSION` 1 → 2。
- 表 A 加三条新命令,写明返回形状(见 Interfaces);`sumi_page_path` 行改为返回 `archive`。
- 表 D:`open` 字段、回调 `root` 语义、`SetArchive` 都按 Interfaces 改。
- §2 现状行补 `core-v0.2.0`、`notemd-plugin-v0.2.0`,状态为待打 tag。
- §3 标题改为“归档投影约定”;“目录”一行改为“归档目录,必须已存在,本身可为符号链接,运行时不创建”;“正文文件”一行去掉 `inbox/writings/` 前缀。
- §4 加一句:本轮属于“主版本升级”那一行,宿主与插件配套发版。
- §7 第 6 条补一句:v2 这一轮两者同时升了,是否必须联动仍为 `[未定]`。
- manifest 的 `vault.read`、`vault.write` 保留(归档目录在 vault 内时仍要写 vault),在 §1.1 注明。

- [ ] **Step 5: 退役名称、扫描替换、缺口与迁移计划**

- `MAPPING.md` 退役表加一行:“vault 投影”(出处 ADR 0009)→ 归档投影,见 ADR 0013。
- 在 `docs/spec/`(除 `MAPPING.md`)与 handoff 00–03 中,把“vault 投影”全部改为“归档投影”。ADR 0009 不动。
- `04-known-gaps.md` 加两条出入:“多个旧纸页库不合并,只在设置里列出未接管的旧库”;“v2 待配套发版”。
- `02-migration-plan.md` 第 2 期「步骤」加一行:“归档目录与写作工作区(ADR 0013,计划 `docs/superpowers/plans/2026-11-20-archive-directory.md`)”。

- [ ] **Step 6: 验证**

Run: `bash docs/check.sh`
Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git add docs
git commit -m "Specify the writing workspace and archive directory (host-contract v2)"
```

---

### Task 2: 内核归档目录路径、无基线首写与 `SetArchive` 请求(core-v0.2.0)

**Files:**
- Modify: `core/src/projection.rs`(`paths` L19–33、`publish` L51 起;新增 `create_archive_under`、`publish_first`、`FirstWrite`、两个常量)
- Modify: `core/tests/catalog_projection.rs`(现有 L59–84 的 `inbox/writings` 断言改为归档目录)
- Modify: `core/Cargo.toml`、`protocol/Cargo.toml`(`version = "0.2.0"`,两个 `Cargo.lock` 随之更新)
- Modify: `protocol/src/durability.rs`(`Request` 加 `SetArchive`)
- Modify: `CHANGELOG.md`、`CHANGELOG.zh-CN.md`(「未发布」区)

**Interfaces:**
- Consumes: `storage::parse_pair(markdown,metadata) -> Result<ParsedPair>`(`ParsedPair.sidecar.page_id`、`.epoch`),`storage::sha256`,`Error::Invalid`
- Produces:
  - `pub const ARCHIVE_UNAVAILABLE: &str` 与 `pub const FIRST_WRITE_CONFLICT: &str`(值见 Global Constraints)
  - `pub fn paths(archive:&Path, filename:&str) -> Result<(PathBuf,PathBuf)>`:文件名规则不变;`archive` 必须是绝对路径;canonicalize 失败或结果不是目录时返回 `Error::Invalid(ARCHIVE_UNAVAILABLE)`;不创建任何东西;返回 `(canon/filename, canon/<stem>.meta.json)`
  - `pub fn create_archive_under(root:&Path, components:&[&str]) -> Result<PathBuf>`:即现行 `paths` 里逐层“拒符号链接或非目录、不存在则 `create_dir`”的逻辑,返回 canonical 路径
  - `pub fn publish(archive:&Path, filename:&str, pair:&FilePair, baseline:&Baseline) -> Result<Baseline>`:签名不变,根改为归档目录
  - `pub enum FirstWrite { Written(Baseline), Adopted(Baseline), Replaced(Baseline), Conflict }`
  - `pub fn publish_first(archive:&Path, filename:&str, pair:&FilePair) -> Result<FirstWrite>`
  - `sumi_protocol::durability::Request::SetArchive { archive: Option<PathBuf> }`,响应为 `()`

- [ ] **Step 1: 写失败的测试**(`core/tests/catalog_projection.rs`,每条用独立 `tempfile` 目录)

- `paths_use_archive_directly`:`paths(dir, "2026-11-20-01.writing.md")` 等于 `(canon(dir)/2026-11-20-01.writing.md, canon(dir)/2026-11-20-01.writing.meta.json)`,且 `dir` 下没有出现 `inbox`。
- `paths_accept_symlinked_archive`:`link → real`,返回路径以 `canonicalize(real)` 开头。
- `paths_reject_missing_archive_without_creating_it`:`dir/missing` 报错,信息含 `archive directory is unavailable`,之后 `!dir.join("missing").exists()`。
- `paths_reject_relative_or_file_archive`:相对路径和普通文件都报 `ARCHIVE_UNAVAILABLE` 或无效。
- 保留现有的文件名校验断言。
- `create_archive_under_builds_layers_and_rejects_symlink_layer`:`create_archive_under(vault, &["inbox","writings"])` 建出两层;若 `inbox` 是符号链接则报 `writing directory must not be a symlink`。
- `publish_first_writes_when_absent`:结果为 `Written(b)`,磁盘字节等于 `pair`,`b` 的两个哈希等于 `sha256(pair.*)`。
- `publish_first_adopts_identical_files`:先手写相同字节,结果为 `Adopted`,文件 mtime 与 inode 不变。
- `publish_first_replaces_own_old_version`:用同一 `Document` 先投影 v1,再编辑得 v2,`publish_first(v2)` 得 `Replaced`,磁盘为 v2。
- `publish_first_conflicts_on_other_page`:磁盘是另一页(不同 `page_id`)的合法对,结果为 `Conflict`,磁盘字节不变。
- `publish_first_conflicts_on_other_epoch`:同一 `page_id`、不同 `write_epoch`,结果为 `Conflict`。
- `publish_first_conflicts_on_edited_body`:本页旧版本的正文多一行,导致 `parse_pair` 失败,结果为 `Conflict`。
- `publish_first_conflicts_on_half_pair`:只有正文没有 sidecar,或者反过来,都是 `Conflict`。
- `publish_first_rejects_missing_archive`:`Err`,含 `ARCHIVE_UNAVAILABLE`,且不建目录。

- [ ] **Step 2: 运行确认失败**

Run: `cargo +1.99.0 test --manifest-path core/Cargo.toml --all-features --test catalog_projection`
Expected: 编译失败(`publish_first`、`create_archive_under` 未定义)

- [ ] **Step 3: 实现**

`projection.rs` 按 Interfaces 实现。`publish_first` 的做法:

1. 先用 `parse_pair` 解析待写的 `pair`,取出本页的 `page_id` 与 `epoch`;解析失败就返回 `Err`(这是调用方的 bug)。
2. 用 `read_hash` 的同一规则读磁盘两份文件:拒绝符号链接,不存在记为 `None`。
3. 两份都不存在,用 `replace` 写入,返回 `Written`。
4. 两份都与待写字节逐字节相同,返回 `Adopted`。
5. 两份都存在,`parse_pair` 通过,且 `page_id` 与 `epoch` 都相同:先写正文再写 sidecar(与 `publish` 的写入顺序一致),返回 `Replaced`。
6. 其余情况返回 `Conflict`。

`protocol/src/durability.rs` 加 `SetArchive` 变体。两个 crate 的版本都升到 `0.2.0`。CHANGELOG 两份各加一条:“内核投影改为写入可设置的归档目录(破坏性变更,`core-v0.2.0`)”。

- [ ] **Step 4: 模块验证**

Run(依次):
```sh
cargo +1.99.0 test --manifest-path core/Cargo.toml --all-features
cargo +1.99.0 clippy --manifest-path core/Cargo.toml --all-targets --all-features -- -D warnings
cargo +1.99.0 test --manifest-path protocol/Cargo.toml
cargo +1.99.0 clippy --manifest-path protocol/Cargo.toml --all-targets -- -D warnings
bash docs/check.sh
```
Expected: 全部通过,`check.sh` 输出 `OK`。

- [ ] **Step 5: Commit 并打本地 tag**

```bash
git add core protocol CHANGELOG.md CHANGELOG.zh-CN.md
git commit -m "Project into a configurable archive directory and add first-write adoption"
git tag core-v0.2.0
```

- [ ] **Step 6: 停点 A**

后台与宿主都通过 GitHub URL 和 tag 依赖内核(`apps/notemd-plugin/backend/Cargo.toml`、note.md `src-tauri/Cargo.toml`),所以 `core-v0.2.0` 必须先推送到 `origin`,任务 3 才能用 `--locked` 解析。停下来请用户同意执行 `git push origin core-v0.2.0`。得到同意前不开始任务 3。

---

### Task 3: 插件后台:工作区 ID、可空归档目录、换目录重置(服务协议 VERSION 2)

**Files:**
- Modify: `apps/notemd-plugin/backend/Cargo.toml`(`write-core`、`sumi-protocol` 的 tag 改为 `core-v0.2.0`;`version = "0.2.0"`)及 `Cargo.lock`
- Modify: `apps/notemd-plugin/backend/src/runtime.rs`(`VERSION`、`Open`、`Session`、`open()`、`network_request` 里的 `"start"`)
- Modify: `apps/notemd-plugin/backend/src/network.rs`(`Workspace.root: PathBuf` → `workspace_id: String`,回调 JSON 键仍为 `"root"`;`BridgeTokens` 同改;L98–187 的测试)
- Modify: `apps/notemd-plugin/backend/src/coordinator.rs`(L974 测试里构造 `Workspace` 的地方)
- Modify: `apps/notemd-plugin/backend/src/durability.rs`(`Durability::open` L95;`Worker` L484;`Worker::open` L500 删掉 `is_dir` 检查;`self.vault` 在 L929、971、1018、1022、1154、1202;`publish_page`;新表与重置)
- Modify: `apps/notemd-plugin/backend/src/durability_rpc.rs`(分派 `SetArchive`)
- Test: 上述文件内的 `#[cfg(test)]` 模块

**Interfaces:**
- Consumes: 任务 2 的 `paths`、`publish`、`publish_first`、`FirstWrite`、`FIRST_WRITE_CONFLICT`、`Request::SetArchive`
- Produces:
  - 服务 `open` 请求 `Open { version:u32, instance:String, session:String, workspace:String, archive:Option<PathBuf>, database:PathBuf, font_cache:PathBuf }`(camelCase,`deny_unknown_fields`)。`archive` 为 `Some` 时必须是绝对路径,但不检查是否存在。`workspace` 按 Global Constraints 校验。`version` 必须是 2。
  - 同一工作区或同一数据库只许绑一个会话。同一会话再次 `open` 时,`workspace`、`archive`、`database`、`font_cache` 任一不同都报 `workspace session paths changed`。
  - `Durability::open(archive: Option<PathBuf>, database: PathBuf, notify) -> Result<Durability>`;`Durability::set_archive(archive: Option<PathBuf>) -> Result<()>`。
  - 表 `sumi_projection_target(id INTEGER PRIMARY KEY CHECK(id=1), archive TEXT)`,`archive` 为 `NULL` 表示未设置。
  - 回调 envelope 的 `params.root` 等于工作区 ID 字符串。

- [ ] **Step 1: 写失败的测试**

`durability.rs` 的测试模块。归档目录是 `tempdir` 子目录,数据库放在另一个 `tempdir`:

- `open_without_archive_saves_text_and_reports_pending`:`archive=None` 时 `open` 成功;提交编辑后 `Saved` 事件里 `projected == false`,`projection_error == Some("尚未设置归档目录")`;重新载入后正文仍在。
- `open_with_missing_archive_does_not_create_it`:`archive=Some(dir/missing)` 时 `open` 成功;编辑并检查点之后 `!dir.join("missing").exists()`。
- `archive_removed_mid_session_keeps_jobs_and_republishes_after_restore`:先发布成功,再 `rename` 归档目录到别处;继续编辑并检查点,队列非空,原路径不存在;`rename` 回来后再检查点,磁盘正文等于最新快照,队列为空。
- `set_archive_republishes_into_new_directory_and_keeps_old_bytes`:在 A 发布两页,记下 A 里所有文件的字节;`set_archive(Some(B))` 后再检查点,B 中两页都在,A 的字节不变,`sumi_baselines` 的文件名对应 B 的文件。
- `set_archive_succeeds_when_old_archive_is_gone`:删除 A 之后 `set_archive(Some(B))` 成功,B 发布完成。
- `switch_back_overwrites_own_old_version_but_not_edited_file`:两页 P、Q 先在 A 发布,`set_archive(B)`;在 B 期间编辑 P;把 A 里 Q 的正文外部改掉;`set_archive(A)`。结果:A 中 P 为最新版本;Q 的外部改动字节不变,Q 的 `projection_error == FIRST_WRITE_CONFLICT`;P 不受 Q 影响。
- `reopen_with_same_non_ascii_archive_keeps_baselines`:归档目录名为 `玄霜 归档`;关闭再用同一路径 `open`,`sumi_baselines` 行数不变,也没有重新写盘(文件 mtime 不变)。
- `legacy_database_adopts_first_archive_and_keeps_baselines`:模拟没有 `sumi_projection_target` 表的旧库,里面已有基线;首次 `open(Some(A))` 写入目标行,基线保留。

`runtime.rs` 的测试:

- `open_rejects_version_1`;
- `open_rejects_invalid_workspace_id`(`"../x"`、空串、65 个字符);
- `open_rejects_relative_archive`;
- `open_accepts_null_archive`;
- `same_workspace_cannot_bind_two_sessions`。

`network.rs`:现有回调测试改为断言 `params["root"] == "<工作区 ID>"`。

- [ ] **Step 2: 运行确认失败**

Run: `cargo +1.99.0 test --manifest-path apps/notemd-plugin/backend/Cargo.toml`
Expected: 编译失败(`Open` 没有 `workspace` 字段、`set_archive` 未定义)

- [ ] **Step 3: 实现**

- `Worker.vault: PathBuf` 改为 `archive: Option<PathBuf>`,加 `fn archive_paths(&self, filename:&str) -> Result<(PathBuf,PathBuf)>`。`archive` 为 `None` 时返回 `Err("尚未设置归档目录")`,否则调 `projection::paths`。所有 `projection::paths(&self.vault, …)` 都改走它。
- `publish_page`:作业基线的两个哈希都为 `None` 时调 `publish_first`。`Conflict` 映射为 `Err(FIRST_WRITE_CONFLICT)`,作业留在队列;其余三种结果的处理与 `publish` 成功相同。
- 重置例程 `fn retarget(&mut self, archive: Option<PathBuf>) -> Result<()>`,在一个事务里完成:
  1. 读出 `sumi_projection_target`;
  2. 没有这一行:插入当前值,不清空任何东西,然后返回;
  3. 有这一行且值与 `archive` 相同(按字符串比较;宿主保证传 canonical 路径):直接返回;
  4. 否则:`DELETE FROM sumi_projection_queue`,`DELETE FROM sumi_baselines`,`DELETE FROM sumi_import_permissions`;对目录表中每个未删除、已有文件名的页,`INSERT OR REPLACE INTO sumi_dirty_projection(page_id, revision)` 写入 `(id, 0)`;`UPDATE projections SET complete=0`;更新目标行。
  事务提交后设 `self.archive = archive` 与 `self.dirty_since = Some(Instant::now())`,由现有检查点节奏重新发布。
- 调用时机:`Worker::open` 建表之后、`recover_projections` 之前调一次;`SetArchive` 请求先 `drain()` 再调。
- `runtime.rs`:`VERSION = 2`;按 Interfaces 校验并存进 `Session { workspace, archive, … }`;`network::Workspace { workspace_id: session.workspace.clone(), … }`。

- [ ] **Step 4: 模块验证**

Run(依次):
```sh
cargo +1.99.0 test --locked --manifest-path apps/notemd-plugin/backend/Cargo.toml
cargo +1.99.0 clippy --manifest-path apps/notemd-plugin/backend/Cargo.toml --all-targets -- -D warnings
```
Expected: 全部通过,只有原有的联机 `#[ignore]` 测试被忽略。

- [ ] **Step 5: Commit**

```bash
git add apps/notemd-plugin/backend
git commit -m "Bind the plugin backend to a workspace and an optional archive directory"
```

---

### Task 4: 插件界面:归档目录设置、首次提示与配套元数据

**Files:**
- Modify: `apps/notemd-plugin/src/contract.ts`(新增 `ArchiveInfo` 类型)
- Modify: `apps/notemd-plugin/src/main.ts`(`showAppearance()` 约 L434 里加“归档目录”一节;启动时调 `archive_get`,`archive === null` 时显示提示条)
- Modify: `apps/notemd-plugin/src/i18n.ts`(新增宿主文案的中英日三语)
- Modify: `apps/notemd-plugin/src/main.test.ts`、`apps/notemd-plugin/src/i18n.test.ts`
- Modify: `apps/notemd-plugin/manifest.v2.json`(`version` → `0.2.0`;`engines` 本任务不动,见任务 8)
- Modify: `apps/notemd-plugin/scripts/verify-stage.py`(L17 `HOST_CONTRACT = 2`)、`apps/notemd-plugin/scripts/test_verify_stage.py`(L19–20 的 `host_contract` 改为 2,`core_tag` 改为 `core-v0.2.0`)
- Modify: `CHANGELOG.md`、`CHANGELOG.zh-CN.md`

**Interfaces:**
- Consumes: 宿主命令(任务 7 实现;本任务的测试用现有 `host.sumi` mock):`archive_get` → `ArchiveInfo`,`archive_choose` → `ArchiveInfo`,`recovery_choose` → `{ path: string | null }`
- Produces: `export interface ArchiveInfo { archive: string | null; available: boolean; untaken: string[] }`

- [ ] **Step 1: 写失败的测试**(`main.test.ts`,沿用现有的 host mock 方式)

- `appearance shows archive path and availability`:`archive_get` 返回 `{archive:'/a/b',available:true,untaken:[]}` 时,`#archive-path` 文本为 `/a/b`;`available:false` 时 `#archive-status` 显示“归档目录不可用”(本地化后的文案)。
- `choose archive calls host and re-renders`:点 `#archive-choose` 调用 `archive_choose` 恰一次;根据返回值刷新 `#archive-path`。
- `recover from archive calls recovery_choose`:点 `#archive-recover` 调用 `recovery_choose` 恰一次。
- `untaken libraries are listed as a hint`:`untaken` 有两项时,`#archive-untaken` 中有两个 `li`。
- `null archive shows startup prompt`:启动时 `archive_get` 返回 `archive:null`,出现 `#archive-prompt`;点其中的按钮调用 `archive_choose`;返回非空后提示条消失。

`i18n.test.ts`:`尚未设置归档目录`、`归档目录不可用` 的英日译文都存在。

`test_verify_stage.py`:清单里的 `host_contract == 2`。

- [ ] **Step 2: 运行确认失败**

Run: `npm --prefix apps/notemd-plugin test` 和 `python3 -I -m unittest discover -s apps/notemd-plugin/scripts -p 'test_*.py'`
Expected: 新测试失败

- [ ] **Step 3: 实现**

- 一节标题为 `t('归档目录','Archive folder','保存先フォルダ')`,放在 `showSounds(form)` 之前。
- 元素 id 依次为:`#archive-path`、`#archive-status`、`#archive-choose`(“选择…”)、`#archive-recover`(“从归档目录选文件恢复…”)、`#archive-untaken`。
- `#archive-untaken` 前的说明文字:“这些是升级前的旧纸页库，未接管，也不会被删除。”(三语)
- 提示条 `#archive-prompt` 的文案:“请选择稿子归档到哪个文件夹。选好之前照常写字，文件稍后写出。”(三语)
- 请求一律走现有的 `request()`,出错走现有的 `run()`。
- CHANGELOG 两份各加一条:“玄霜写作有了自己的归档目录与纸页库，不再随 note.md 的 vault 切换。”

- [ ] **Step 4: 模块验证**

Run(依次):
```sh
npm --prefix apps/notemd-plugin test
npm --prefix apps/notemd-plugin run check
npm --prefix apps/notemd-plugin run build
python3 -I -m unittest discover -s apps/notemd-plugin/scripts -p 'test_*.py'
cargo +1.99.0 test --locked --manifest-path apps/notemd-plugin/backend/Cargo.toml
bash docs/check.sh
```
Expected: 全部通过,`check.sh` 输出 `OK`。

- [ ] **Step 5: Commit**

```bash
git add apps/notemd-plugin CHANGELOG.md CHANGELOG.zh-CN.md
git commit -m "Add the archive folder setting to the plugin UI and bump to host-contract v2"
```

- [ ] **Step 6: 停点 B**

宿主的开发依赖 `notemd-sumi-backend` 从 GitHub 取,按 `rev` = 合并后的 main 提交固定。停下来,先对 sumiwrite 分支做一次整分支审查。审查通过后请用户同意以下两件事:

1. 把分支合并到 sumiwrite `main`;
2. `git push origin main`。

此处不打插件 tag:note.md `scripts/release-plugins.sh` 要求 sumiwrite 检出恰好位于 `notemd-plugin-v<manifest 版本>` 上,所以 tag 必须打在已带发版日 `engines.notemd` 的那个提交上(见任务 8 Step 2)。

得到同意前不开始任务 6。任务 5 不依赖已合并的 main,可以先做。

---

### Task 5: 宿主:`workspace.json` 与首次升级接管(note.md worktree)

**Files:**
- Create: `~/git/note.md-archive/src-tauri/src/sumi/workspace_config.rs`(在 `mod.rs` 里声明 `mod workspace_config;`)
- Test: 同文件 `#[cfg(test)] mod tests`

**Interfaces:**
- Consumes: `write_core::projection::create_archive_under`(任务 2;本任务在 worktree 里用临时、不入库的 `[patch."https://github.com/wizlijun/sumiwrite"]` 指向本机 sumiwrite 的 `core`、`protocol`。停点 A 已推送 tag 的话可直接改依赖,见任务 6 Step 1)
- Produces:
  - `#[serde(deny_unknown_fields)] pub struct Config { pub schema: u32, pub workspace: String, pub archive: Option<PathBuf> }`
  - `pub struct Resolved { pub config: Config, pub created: bool }`
  - `pub fn load_or_take_over(sumi_dir:&Path, open_vault:Option<&Path>) -> Result<Resolved, String>`:`open_vault` 是已 canonicalize 的 vault 根
  - `pub fn save(sumi_dir:&Path, config:&Config) -> Result<(), String>`:先写临时文件,`fsync`,`rename`,再 `fsync` 目录
  - `pub fn untaken(sumi_dir:&Path, workspace:&str) -> Result<Vec<PathBuf>, String>`
  - `pub fn valid_workspace_id(id:&str) -> bool`

- [ ] **Step 1: 写失败的测试**(每条测试都用独立 `tempdir` 作 `sumi_dir`)

“旧库”是指名为 64 位十六进制、内含 `documents.sqlite3` 的子目录;另放一个 `fonts/` 和一个 `.DS_Store` 文件作干扰。

- `takes_over_single_library_without_vault`:一个旧库,不传 vault。结果 `workspace` 为该目录名,`archive == None`,文件已写出,目录原样留着。
- `takes_over_single_library_matching_vault_and_creates_inbox_writings`:旧库名等于 `sha256(canon(vault))`。结果 `archive == Some(canon(vault)/inbox/writings)`,并且这个目录已被建出。
- `multiple_libraries_prefer_open_vault_hash`:三个旧库,其中一个命中当前 vault,接管命中的那个。
- `multiple_libraries_without_match_take_newest`:三个旧库,都不命中;按各目录下 `documents.sqlite3*` 文件的最新 mtime 选最新的,`archive == None`;`untaken()` 返回另外两个,不含 `fonts`。
- `fresh_install_with_vault_uses_uuid_and_inbox_writings`:没有旧库。`workspace` 是合法的 UUID v4 小写形式,`archive == Some(canon(vault)/inbox/writings)`。
- `fresh_install_without_vault_has_null_archive`。
- `second_call_reuses_config_without_takeover`:第二次调用时 `created == false`;即使中间新加一个旧库,结果也不变。
- `corrupt_config_is_reported_and_left_untouched`:`workspace.json` 写成 `{"schema":1,"workspace":`。返回 `Err`,内容以 `写作工作区配置损坏，请检查` 开头;文件字节不变;不新建库目录。
- `config_with_invalid_workspace_id_is_corrupt`:`"workspace":"../x"` 按损坏处理。
- `config_round_trips_non_ascii_archive`:`archive` 为 `<tmp>/文稿/玄霜 归档`。`save` 后再读,得到相同的 `PathBuf`。

- [ ] **Step 2: 运行确认失败**

Run: `cd ~/git/note.md-archive && cargo +1.99.0 test --manifest-path src-tauri/Cargo.toml --lib sumi::workspace_config`
Expected: 编译失败(模块不存在)

- [ ] **Step 3: 实现**

按设计 §5.2 的五步实现,只用 `std::fs`,不依赖 Tauri。`schema` 不是 1 也按损坏处理。接管时建 `inbox/writings` 若失败(例如某一层是符号链接),`archive` 记为 `None`,不报错。

- [ ] **Step 4: 验证**

Run: `cargo +1.99.0 test --manifest-path src-tauri/Cargo.toml --lib sumi::workspace_config`
Expected: 全部通过

- [ ] **Step 5: Commit**(不要提交临时 `[patch]`)

```bash
git add src-tauri/src/sumi/workspace_config.rs src-tauri/src/sumi/mod.rs
git commit -m "Add the Sumi writing workspace config and legacy library takeover"
```

---

### Task 6: 宿主:工作区与 vault 脱钩(服务协议 VERSION 2)

**Files:**
- Modify: `~/git/note.md-archive/src-tauri/Cargo.toml`(L39–40 改为 `core-v0.2.0`,L140 的 `notemd-sumi-backend` 改为 `{ git = "https://github.com/wizlijun/sumiwrite", rev = "<停点 B 合并后的 main 提交>" }`)及 `Cargo.lock`
- Modify: `src-tauri/src/sumi/service.rs`(L11 `VERSION = 2`;`Backend::open` L92;open 载荷 L122;L262–285 的测试)
- Modify: `src-tauri/src/sumi/durability.rs`(加 `set_archive`)
- Modify: `src-tauri/src/sumi/mod.rs`:
  - `Workspace` L416;
  - `fn root` L466、`current` L472、`current_native` L482、`workspace()` L534–603;
  - `background_request` L600–610;
  - 署名 L904;`home-content-edit` L1372;
  - `projection::paths` 在 L1825、2211、2556、2764、2874;
  - `open_path` L2537;`sumi_page_path` L2865–2875
- Modify: `src-tauri/src/sumi/lifecycle_tests.rs`、`backend_proxy_tests.rs`(凡是以 vault 根构造工作区的地方)

**Interfaces:**
- Consumes: 任务 5 的 `workspace_config::*`;任务 3 的 open 载荷与回调 `root` 语义;任务 2 的 `Request::SetArchive`
- Produces:
  - `Workspace` 删掉 `root`、`selected_root`,新增 `id: String`、`archive: std::sync::RwLock<Option<PathBuf>>`;
  - `impl Workspace { fn archive(&self) -> Option<PathBuf>; fn projection_paths(&self, filename:&str) -> Result<(PathBuf,PathBuf)> }`,未设置时报 `尚未设置归档目录`;
  - `WORKSPACES` 以工作区 ID 为键;
  - `service::Backend::open(app, workspace:String, archive:Option<PathBuf>, database:PathBuf)`;
  - `Durability::set_archive(&self, archive: Option<PathBuf>) -> Result<()>`;
  - `sumi_page_path` 返回 `{"page_id","epoch","path","archive"}`。

- [ ] **Step 1: 切换依赖**

去掉任务 5 的临时 `[patch]`,把 `write-core`、`sumi-protocol` 的 tag 改成 `core-v0.2.0`,`notemd-sumi-backend` 改为 `{ git = "https://github.com/wizlijun/sumiwrite", rev = "<停点 B 合并后的 main 提交>" }`(Cargo.lock 固定它)。运行 `cargo +1.99.0 update -p write-core -p sumi-protocol -p notemd-sumi-backend --manifest-path src-tauri/Cargo.toml`。Expected:成功解析;如果失败,说明停点 A 或 B 的推送还没做,回去等用户。

- [ ] **Step 2: 写失败的测试**(`lifecycle_tests.rs`,沿用现有测试夹具)

- `workspace_opens_without_vault`:不设置 vault 时打开工作区成功,能创建页面并写字。
- `vault_switch_keeps_session_and_retargets_home_content_edit`:先以 vault V1 打开,归档目录在 `V2/inbox/writings`。切到 V2 后,`current()` 仍为 `Ok`,编辑会发出 `home-content-edit`,其 `path` 以 V2 为前缀;切到 V3(不包含归档目录)后,编辑不再发出这个事件。
- `author_comes_from_archive_git_config`:归档目录是一个 git 仓库,`user.name` 为 `Archive Writer`;新页 frontmatter 的 `author` 为 `human:Archive Writer`。仓库的 git config 写法与 `okf/mod.rs` 现有测试一致。
- `null_archive_reports_projection_pending`:`archive` 为 `null` 时编辑,`saveState == "projection-pending"`。
- `background_callback_root_must_equal_workspace_id`:`params.root` 为旧的 vault 路径时被拒(`Sumi后台工作区绑定不一致`)。
- `profile_is_workspace_id`:`auth_load` 收到的 `profile` 等于工作区 ID;接管的情形下,它就是旧哈希。
- `page_path_returns_archive`:`sumi_page_path` 的 `archive` 字段等于 canonical 归档目录。
- `open_path_rejects_file_outside_archive`。

`service.rs`:open 载荷里有 `"workspace"` 和 `"archive"`、没有 `"vault"`,`version == 2`。

- [ ] **Step 3: 运行确认失败**

Run: `cargo +1.99.0 test --manifest-path src-tauri/Cargo.toml --lib sumi::`
Expected: 新测试失败或编译失败

- [ ] **Step 4: 实现**

- `workspace(app)` 不再要求打开 vault。
  - 用 `workspace_config::load_or_take_over(app_data/sumi, 当前已 canonicalize 的 vault 根)` 拿到配置,vault 只作接管线索;
  - `database = app_data/sumi/<id>/documents.sqlite3`;
  - 进程内缓存工作区 ID(`static ACTIVE_WORKSPACE`)。
- `current` 与 `current_native`:`writable()` 与 `authorize` 之后,比较 `ws.id` 与缓存的工作区 ID。`current_native` 不读 `VaultSyncManager`。
- `background_request(app, workspace_id:&str, …)`:按 ID 查找工作区,`profile = workspace_id`。
- 署名:`human_actor_for_vault(ws.archive().filter(|p| p.is_dir()).as_deref())`。
- `home-content-edit`:取 `resolve_vault_root(app)`,先 canonicalize。投影路径以它为前缀时,按相对路径拼回未 canonicalize 的选中根再发出,与现行语义一致;否则不发。
- 五处 `projection::paths(&ws.root, …)` 改为 `ws.projection_paths(…)`;`open_path` 改为检查 canonical 归档目录前缀。
- 删掉“请先打开 Vault”“Vault 已切换，旧编辑会话已停止”这两条报错路径。

**宿主清单(本任务与任务 7 共同遵守)**

- 归档目录为 `None` 且有遗留投影任务时,每次后台 open 都会发出 `Failed{page_id:""}`「尚未设置归档目录」。宿主不得对每个事件弹 toast:忽略空 `page_id`,或并入「选择归档目录」提示。
- `retarget` 按字符串比较归档目录。宿主必须每次存储并传入同一个规范路径字符串(只 canonicalize 一次,持久化那个字符串;注意 APFS 上 NFC/NFD 差异),否则后台会当成新目录而全部重新发布。
- v2 宿主遇到旧后台(hello 被拒,报 "unsupported Sumi Write service version")时,显示「请同时更新宿主和插件」。

- [ ] **Step 5: 验证**

Run(依次):
```sh
cargo +1.99.0 test --manifest-path src-tauri/Cargo.toml --lib sumi::
cargo +1.99.0 clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
```
Expected: 全部通过,包括原有的 `lifecycle_tests`、`recovery_tests`、`backend_proxy_tests`。

- [ ] **Step 6: Commit**

```bash
git add src-tauri
git commit -m "Decouple the Sumi workspace from the open vault"
```

---

### Task 7: 宿主:归档目录命令、改目录流程与恢复入口

**Files:**
- Modify: `~/git/note.md-archive/src-tauri/src/sumi/mod.rs`(dispatch 约 L3676 加三条命令;新增 `switch_archive`、`quiesce_for_archive`)
- Modify: `src-tauri/src/plugin_runtime/host_api.rs`(L87–91 的命令白名单加三条)
- Modify: `src-tauri/src/sumi/recovery.rs`(`Evidence.vault` L21 → `root`;`verify_vault` L31 → `verify_root`;`read_regular`、`inspect`、`probe`、`prepare` 改收允许根列表;L225 的 `inbox/writings` 改为传入的归档目录)
- Modify: `mod.rs` 中调用恢复的 L2685、L2715、L2728
- Modify: `src/components/SumiRecovery.svelte`(L34 `e.vault` → `e.root`)及 `src/components/SumiRecovery.test.ts`
- Modify: `src-tauri/src/sumi/recovery_tests.rs`、`lifecycle_tests.rs`
- Modify: `CHANGELOG.md`、`CHANGELOG.zh-CN.md`(note.md 根目录,「未发布」区)

**Interfaces:**
- Consumes: 任务 6 的 `Workspace::archive`、`Durability::set_archive`;任务 5 的 `save`、`untaken`;现有的停止屏障(`before_close`、`network.stop()`、`freeze_workspace`、`resume_workspace`、`resume_window`)
- Produces:
  - `async fn archive_info(app, ws) -> Result<Value>`,返回 `{"archive","available","untaken"}`;
  - `async fn switch_archive<R: Runtime>(app:&AppHandle<R>, ws:&Arc<Workspace>, chosen:PathBuf) -> Result<Value>`,返回值与 `archive_info` 同形;
  - 命令 `host.sumi.archive_get`、`host.sumi.archive_choose`、`host.sumi.recovery_choose`;
  - `recovery::Evidence.root: String`;`recovery::probe(roots:&[PathBuf], archive:Option<&Path>, path:&Path)`;`prepare` 同样改收 `roots`。

- [ ] **Step 1: 写失败的测试**

`lifecycle_tests.rs`(直接调 `switch_archive`,不弹对话框):

- `switch_archive_republishes_and_keeps_old_files`:A 中有两页。`switch_archive(B)` 之后,B 中两页齐全,A 的字节不变,`workspace.json` 的 `archive == canon(B)`,而且会话仍可写。
- `archive_choose_succeeds_when_old_archive_is_gone`:先删掉 A,再 `switch_archive(B)`,返回 `Ok`。
- `choosing_same_archive_keeps_baselines`:`switch_archive(A)` 而 A 就是当前归档目录。`workspace.json` 的 mtime 不变,磁盘文件 mtime 不变,不调用 `set_archive`(用后台调用计数断言)。
- `archive_choose_rejects_app_data_directory`:选 `<app_data>/sumi/x` 返回 `Err("归档目录不可用")`,配置不变。
- `archive_choose_rejects_missing_or_file_path`:不存在的路径或普通文件,同样报 `归档目录不可用`。
- `crash_after_config_write_resets_on_next_open`:只写 `workspace.json`、不调 `set_archive`,然后重开工作区;各页出现在新目录。这一条验证后台 `open` 时的对比。
- `archive_info_lists_untaken_libraries`。

`recovery_tests.rs`:

- `probe_accepts_file_in_archive_outside_vault`;
- `probe_accepts_file_in_open_vault`;
- `probe_rejects_file_outside_both`(报错文案改为“恢复证据不属于当前归档目录或 Vault，请重新检查源文件”);
- `prepare_rejects_evidence_for_previous_archive`:证据的 `root` 是旧归档目录时被拒;
- 现有测试中的 `vault` 字段一律改为 `root`。

`SumiRecovery.test.ts`:去重键用 `e.root`。

- [ ] **Step 2: 运行确认失败**

Run: `cargo +1.99.0 test --manifest-path src-tauri/Cargo.toml --lib sumi::` 和 `pnpm vitest run src/components/SumiRecovery.test.ts`
Expected: 新测试失败

- [ ] **Step 3: 实现**

`switch_archive` 依次做:

1. canonicalize `chosen`。不存在、不是目录、或位于 `app_data/sumi` 之下,都报 `归档目录不可用`。
2. 与当前归档目录相同就直接返回 `archive_info`。
3. 对这一个工作区执行停止屏障,做法同 `before_exit`,但只针对这一个 `ws`。`freeze_workspace` 里最终投影失败不中止(设计 §5.3 第 2 步),只记日志。
4. `workspace_config::save`。
5. `ws.durable.set_archive(Some(canon))`。
6. 更新 `ws.archive`。
7. `resume_workspace` 加 `resume_window`。

第 3–5 步任一步失败,都要恢复会话再返回错误,与 `before_exit` 的回滚写法一致。第 4 步之后才失败的情况,由下次 `open` 时后台的对比兜底。

`archive_choose` 用 `tauri-plugin-dialog`(已是依赖)弹文件夹选择框,取消时返回当前的 `archive_info`。`recovery_choose` 弹文件选择框,起点为归档目录,过滤 `*.writing.md`。选中文件后,用宿主现有的“外部路径打开”通道(即 argv/Finder 打开走的那条,最终到前端 `openPath`)把它作为标签页打开,这样就复用 `NativeFileView` 里现有的 `SumiRecovery` 流程;返回 `{"path": …}`。

恢复的允许根 = [canonical 归档目录(可用时), canonical 当前 vault(打开时)]。

`archive_get` 不得因 `workspace.json` 损坏而失败:返回 `archive: null`、`available: false`,并通过它自己的路径提示「写作工作区配置损坏，请检查 <路径>」,以免拖垮插件界面启动。(设计稿对损坏处理只建议原子写入,未另作规定,故按此执行。)

CHANGELOG 两份各加一条(写在版本节最前面):“玄霜写作的纸页库和归档目录不再跟随 vault:升级后原有纸页与同步配对原样保留;可以在设置里选择任意文件夹作归档目录。需同时更新宿主和玄霜写作插件。”

- [ ] **Step 4: 验证**

Run(依次):
```sh
cargo +1.99.0 test --manifest-path src-tauri/Cargo.toml --lib sumi::
cargo +1.99.0 clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
pnpm vitest run src/components/SumiRecovery.test.ts src/components/NativeFileView.actions.test.ts
node scripts/changelog.mjs check
```
Expected: 全部通过;`changelog.mjs check` 退出码 0。

- [ ] **Step 5: Commit**

```bash
git add src-tauri src/components CHANGELOG.md CHANGELOG.zh-CN.md
git commit -m "Add Sumi archive folder commands and archive-rooted recovery"
```

---

### Task 8: 配套发版准备与证据(只改文档)

**Files:**
- Modify: sumiwrite `docs/spec/platform/notemd-desktop.md` §2.0、§2.1,`docs/spec/01-pages-and-storage.md` §4.2,`docs/handoff/03-notemd-contract.md` §2 与 §5,`docs/handoff/04-known-gaps.md`

**Interfaces:**
- Consumes: 任务 1–7 的提交号与 tag

- [ ] **Step 1: 写明交付现状**

上列各处的状态行仍保持 `[未定]`。按已发生的事实写:“sumiwrite 已合并并推送 main(提交 …),插件 tag 待发版日打;note.md 侧在本地分支 `sumi/archive-directory`(提交 …),待合并、推送与配套发版”。不写 note.md 的 blob 链接,因为它们还没推送。

- [ ] **Step 2: 写明发版日要做的事**

在 `04-known-gaps.md` 的 v2 条目里写清:

- 发版当天,`manifest.v2.json` 的 `engines.notemd` 改为 `>=<该日 scripts/release.sh 推出的宿主版本>`,并在 sumiwrite 提交这次 engines 改动;
- 在该提交上打 `notemd-plugin-v0.2.0` 并推送;
- 宿主把 `notemd-sumi-backend` 从 `rev` 改为 `tag = "notemd-plugin-v0.2.0"`,刷新 `Cargo.lock`;
- 然后宿主与插件同一轮发布;
- 发布后,把上列状态行改为已交付,并补上 note.md 的 blob 链接。

这些由用户在发版时执行。

- [ ] **Step 3: 验证并提交**

Run: `bash docs/check.sh`
Expected: `OK`

```bash
git add docs
git commit -m "Record the archive directory delivery state ahead of the paired release"
```

- [ ] **Step 4: 手工验收清单交给用户**(取设计 §5.7「手工」)

逐条列出:

- 本机升级后,纸页与配对都在;
- 把归档目录改到 vault 外以后,写字、关闭、重开、强杀,正文与投影都正确;
- 拔掉放归档目录的移动硬盘后继续写字,不丢字,不建影子目录。

note.md 分支的合并与推送由用户决定。
