# 第 2 期详细计划:迁插件壳、资源与插件侧脚本

> **给执行的 agent:** 按任务顺序执行,每步用 `- [ ]` 勾选。必需的子技能:superpowers:subagent-driven-development(推荐)或 superpowers:executing-plans。

**目标**:把 note.md 的 `plugins-src/write/` 连同历史迁到本仓库 `apps/notemd-plugin/`,带上三个插件侧脚本,做到在本仓库内能测试、能构建出待签名的插件包;note.md 改为从本仓库固定 tag 取源码与构建物,并删掉自己那份。之后在本仓库按设计 `2026-11-20-archive-directory-design.md` 做归档目录(任务 10,另立计划)。

**做法**:与第 1 期相同:全新克隆上 `git filter-repo` 提取历史,并入本仓库 `phase2` 分支;先在本仓库把依赖接好、测试跑通、打 tag,再在 note.md 的单独分支上一次性切换依赖、改脚本、删目录。签名、公证、minisign、上架仍在 note.md。

**技术栈**:Rust 1.99.0、Node(TypeScript 5.9.3、Vite 6.4.2、Vitest 4.1.5、jsdom 25.0.1)、Python 3、git-filter-repo、Cargo git 依赖。

**依据**:[02-migration-plan.md](../handoff/02-migration-plan.md) 第 2 期、[01-inventory.md](../handoff/01-inventory.md) §3–§4、[03-notemd-contract.md](../handoff/03-notemd-contract.md) §4–§5、第 1 期计划 [2026-11-20-phase1-core-protocol-sync.md](2026-11-20-phase1-core-protocol-sync.md)(流程照抄处不再重复)。本计划与 02 冲突时,先改 02(任务 1)再动手。

**基线(2026-11-20 实测)**:note.md `main` 在 `952b6f26`;`9286d89d` 之后 `plugins-src/write/`、`plugins-src/shared/`、`src/lib/sumi/`、`scripts/sumi/`、`scripts/release-plugins.sh`、`notemd-plugin-sdk/`、`plugin-protocol/` 都没有改动。note.md 工作区有与本期无关的未提交改动(`HomeContent.svelte` 等),任何步骤都不得碰它们。note.md 仓库为公开仓库,Cargo 可匿名拉取。插件版本 `0.1.16`,后台 crate `notemd-sumi-backend 0.1.5`,`engines.notemd >=6.1111.1`。

---

## 第 2 期前置条件的四项结论

02 第 2 期要求本计划定下四件事。四项都是 **[我的判断]**,认可本计划即认可它们。

| 问题 | 结论 | 理由 |
|---|---|---|
| `plugins-src/shared/shortcuts.ts` 怎么共享 | **sumiwrite 自写一份**:`apps/notemd-plugin/src/shortcuts.ts`,只含插件用到的 `isApplePlatformSync`、`shortcutEventBlocked`、`primaryShortcut`,把它依赖的 note.md `src/lib/platform-sync.ts`、`src/lib/primary-modifier.ts` 两个函数内联进来。note.md 那份原样不动 | 原文件本身又引用 note.md 应用代码,跨仓库引用拉不进来;要的只有约 20 行,而且是平台约定,不是会漂移的业务逻辑 |
| `src/lib/sumi/i18n.ts` | **各留一份**:sumiwrite 带历史迁一份到 `apps/notemd-plugin/src/i18n.ts`;note.md 那份留给宿主界面(`SumiRecovery.svelte:3`、`NativeFileView.svelte:13`)继续用 | 宿主内 Sumi 界面归 note.md(AGENTS.md 第 2 条),宿主不能反向依赖插件包;它是宿主消息的翻译表,两份分开演进。记入 04 |
| `scripts/sumi/verify-release.py` 拆不拆 | **不拆,留在 note.md**。只改自测里唯一一处读工作区的地方(`:492`),改为经 `source('v'+VERSION, …)` 从 tag 读 | 它是钉在 `v6.1111.1` / 插件 `0.1.14` 的冻结发版核验,读源码全走 `git show <提交>:<路径>`,删目录不影响;插件侧的资源门禁改由本仓库的构建脚本承担(任务 5) |
| 交给 note.md 签名的构建物与校验清单格式 | 见任务 5 的“交付格式”;写进契约 03 §5,替换 `[未定]` | — |

另外两项也在本期定 **[我的判断]**:

- **SDK 引用方式**:note.md 打 tag `plugin-sdk-v0.1.0`(门禁 G2),插件后台写 `notemd-plugin-sdk = { git = "https://github.com/wizlijun/note.md", tag = "plugin-sdk-v0.1.0" }`。Cargo 会检出整个 note.md 仓库,SDK 对 `../plugin-protocol` 的 path 依赖在检出里照常解析(任务 3 实测)。
- **本期不发新插件包**:迁移不改行为,`0.1.16` 已上架。从本仓库构建只用于本机安装验收;下一次有真实改动时再按任务 8 的新流程发版、升版本号。

## 开工前置(用户门禁)

| # | 事项 | 卡住哪个任务 |
|---|---|---|
| G1 | 认可本计划(含上面六项结论与评审重点) | 全部 |
| G2 | 允许在 note.md 打并推送 tag `plugin-sdk-v0.1.0`(指向当时 `main` 上 `notemd-plugin-sdk/`、`plugin-protocol/` 未改动的提交) | 任务 3 |
| G3 | 允许推送本仓库 `main` 与 tag `notemd-plugin-v0.1.16` | 任务 7 |
| G4 | 允许在 note.md 开分支 `sumi/plugin-from-sumiwrite` 做任务 8、9;合并与推送另由用户定 | 任务 8、9 |

## 全局约束

- Rust 一律 `cargo +1.99.0`。crate 名不变:仍叫 `notemd-sumi-backend`,二进制仍叫 `notemd-sumi`。
- 插件 `id` `notemd.sumi`、版本 `0.1.16`、`engines.notemd >=6.1111.1`、`binary` 两个目标三元组都不改。
- 前端依赖精确钉住:`typescript 5.9.3`、`vite 6.4.2`、`vitest 4.1.5`、`jsdom 25.0.1`(note.md 根 `node_modules` 现有版本),用 npm 与 `package-lock.json`。
- 许可文本与字体目录按字节不变;`.gitattributes` 里三条 `-text` 规则随文件迁入本仓库。
- 签名密钥、公证凭据、Developer ID、Team ID 不进入本仓库,只写引用位置(AGENTS.md 第 5 条)。
- 两个仓库不得各留一份可编辑的插件源码(02 总红线)。`shortcuts.ts`、`i18n.ts` 两项按上表的结论处理。
- note.md 每个提交都能照常构建和发版;note.md 侧遵守其 `CLAUDE.md`。本期没有用户可感知的变化,不加 CHANGELOG 条目。
- 文档用简体中文,提交信息用英文祈使句,结尾带 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。本仓库每次提交前 `bash docs/check.sh` 输出 `OK`;改 `core/`、`protocol/`、`sync/` 时跑该模块 README 的测试(本期预计只在任务 4 改 `apps/`,不改这三处)。

## 评审重点

测试覆盖不到、最可能出事的五处,按可能性从高到低:

1. **宿主测试图里出现两份 `plugin-protocol`**:宿主 `src-tauri` 按 path 依赖 `plugin-protocol`,又经 dev 依赖(本仓库插件后台)→ SDK git tag → git 上的 `plugin-protocol`。任务 8 在 `src-tauri/Cargo.toml` 提交一条指回自身的 `[patch."https://github.com/wizlijun/note.md"]`,并用 `cargo tree -d -e normal,dev` 断言没有重复的 `plugin-protocol`、`notemd-plugin-sdk`、`write-core`。
2. **许可文件换行被改写**:三份许可文件在 note.md 靠 `.gitattributes` 的 `-text` 保住原始字节;本仓库漏了这条,检出时可能被规范化,`verify-stage.py` 的字节比较就会失败,或者更糟,上游 SHA 对不上。任务 2 加规则并比对 SHA-256。
3. **note.md 脚本读不到本仓库的文件**:字体目录 `manifest.json` 是宿主测试、`prepare-sumi-font.py`、两个原生探针、`verify-extracted-assets.mjs`、验收构建共用的唯一来源。任务 8 统一用 `SUMIWRITE_DIR`(默认 `../sumiwrite`),缺目录时报清楚的错,不静默跳过;发版模式下还要求它正好停在 tag 上且工作区干净。
4. **构建物与源码 tag 对不上**:note.md 签的必须是本仓库 tag 对应源码构建的东西。任务 5 的清单记 `source_commit`,任务 8 在签名前比对 `git -C $SUMIWRITE_DIR rev-parse HEAD` 与清单、重算每个文件的 SHA-256,并拒绝清单外的文件。
5. **Vite 静默换版本**:插件原先借用 note.md 根的 `node_modules`,迁来后自带;版本一漂,`dist/` 的字节就变,验收结果不可比。任务 4 精确钉版本,并比对迁移前后 `dist/` 的文件列表与 SHA-256。

---

### Task 1(任务 1):把新发现补进交接文档

01-inventory §4 漏列了以下反向依赖,按 02 文首的规矩先改文档再动手。

**文件**:改 `docs/handoff/01-inventory.md` §3、§4、§6,`docs/handoff/02-migration-plan.md` 第 2 期,`docs/handoff/04-known-gaps.md`。

| 漏列项 | 位置(note.md `952b6f26`) | 本计划的处理 |
|---|---|---|
| 宿主 dev 依赖插件后台 crate,测试里在进程内跑 `Durability` | `src-tauri/Cargo.toml:140`;`src-tauri/src/sumi/durability.rs:29`、`:56`、`:124`、`:165` | 任务 8 改为 git tag 依赖 |
| 宿主测试 `include_str!` 读字体目录 | `src-tauri/src/sumi/mod.rs:4091` | 后台导出常量(任务 4),任务 8 改用 |
| 字体目录被 note.md 脚本与探针按路径读 | `scripts/prepare-sumi-font.py:13`;`tauri-plugin-native-editor/native/focus-probe.m:543`、`focus-return-probe.m:115`;`scripts/sumi/verify-extracted-assets.mjs:42-43`;`scripts/sumi/acceptance/build.sh:13`、`:22-26`、`:65`、`prepare.py:43` | 任务 8 改读 `$SUMIWRITE_DIR` |
| 开发安装脚本从树内构建插件 | `scripts/dev-install-plugin.sh:493-512` | 任务 8 |
| pnpm 工作区包含插件 | `pnpm-workspace.yaml`(`plugins-src/*`)、`pnpm-lock.yaml:812` | 任务 8 删目录后 `pnpm install` 重算 |
| 原生签名的源码证明写死插件路径 | `scripts/sumi/native-release.py:11`、`:30` | 任务 8 |
| `.gitattributes` 许可文件规则 | note.md `.gitattributes:55`、`:56`、`:59` | 任务 2 迁入,任务 8 删除 |
| 插件发版脚本借用 note.md 根的 `tsc`、`vite` | `scripts/release-plugins.sh:384`、`dev-install-plugin.sh:499` | 任务 4 自带工具链 |

- [ ] 把上表写进 01 §4(新增“立第 2 期计划时发现”子表),§3 末尾的判定说明补上 `verify-release.py` 不拆的结论;§6 里第 2 期的两项改为“已定,见第 2 期计划”。
- [ ] 02 第 2 期“前置条件”里“详细计划已立”一句加上指向本文的链接;步骤 5 补一句“`release_sumi()` 按 03 §5 的交付格式消费构建物”。
- [ ] 04 记两件事:`i18n.ts` 两仓库各一份,分开演进;第 2 期不发新插件包。
- [ ] `bash docs/check.sh` 输出 `OK`,提交:`Record plugin reverse dependencies found while planning phase 2`。

### Task 2(任务 2):提取历史并并入本仓库

**产出**:本仓库 `phase2` 分支(从 `main` 开出)上有 `apps/notemd-plugin/`,带原有历史。

- [ ] 在 scratchpad 做全新克隆并记下提交,然后提取:
  ```bash
  git clone --no-local ~/git/note.md notemd-extract2 && cd notemd-extract2 && git rev-parse HEAD
  git filter-repo --path plugins-src/write/ --path src/lib/sumi/i18n.ts \
    --path scripts/sumi/verify-sounds.py --path scripts/sumi/verify-linux-binary.py \
    --path scripts/sumi/test_verify_linux_binary.py \
    --path-rename plugins-src/write/:apps/notemd-plugin/ \
    --path-rename src/lib/sumi/i18n.ts:apps/notemd-plugin/src/i18n.ts \
    --path-rename scripts/sumi/:apps/notemd-plugin/scripts/
  ```
- [ ] 公开前扫描,规则同第 1 期任务 2,另加:`APPLE_PASSWORD=` 后跟值、`NOTEMD_PLUGIN_SIGNING_KEY=` 后跟值、`-----BEGIN`、`untrusted comment:`(minisign 私钥头)。命中就停下报告。
- [ ] `git switch -c phase2 && git pull --allow-unrelated-histories <克隆路径> main`,合并信息:`Import the Sumi Write plugin shell from note.md <提交>`。
- [ ] 本仓库 `.gitattributes`(新建或追加)写入 note.md `:55`、`:56`、`:59` 三条规则,路径前缀换成 `apps/notemd-plugin/`;然后 `git rm --cached -r apps/notemd-plugin/resources && git checkout -- apps/notemd-plugin/resources`,确认 `git status` 干净。
- [ ] 核对:`git ls-files apps/notemd-plugin | wc -l` 等于 52 + 4(三个脚本与 `i18n.ts`);`apps/notemd-plugin/resources/` 下每个文件的 SHA-256 与 note.md 工作区对应文件一致。
- [ ] 提交 `.gitattributes`:`Keep license files byte-exact in the plugin resources`。

### Task 3(任务 3):插件后台按 tag 引用 SDK [需 G2]

**文件**:改 `apps/notemd-plugin/backend/Cargo.toml:11`、`apps/notemd-plugin/backend/Cargo.lock`;改 `apps/notemd-plugin/README.md`(新建)。

- [ ] note.md 上打附注 tag `plugin-sdk-v0.1.0`(信息:`notemd-plugin-sdk 0.1.0 and plugin-protocol for sumiwrite`),推送前向用户确认。
- [ ] `Cargo.toml:11` 改为 `notemd-plugin-sdk = { git = "https://github.com/wizlijun/note.md", tag = "plugin-sdk-v0.1.0" }`,执行 `cargo +1.99.0 update -p notemd-plugin-sdk -p plugin-protocol --manifest-path apps/notemd-plugin/backend/Cargo.toml`。
- [ ] 锁文件闸门:`git diff` 只许新增这两个包的 `source` 行;`cargo tree -i yrs` 为 `yrs v0.24.0`;`cargo tree -d` 里没有 `write-core`、`sumi-protocol`、`plugin-protocol`。不满足就停下,不许无参数 `cargo update`。
- [ ] 跑 `cargo +1.99.0 test --manifest-path apps/notemd-plugin/backend/Cargo.toml` 与 `cargo +1.99.0 clippy --manifest-path apps/notemd-plugin/backend/Cargo.toml --all-targets -- -D warnings`,应全过(那个 `#[ignore]` 的联机测试只需编译通过)。
- [ ] `README.md` 写:它是什么、目录结构、“Verification”段(本任务两条命令,加任务 4 的前端命令,加 `python3 -I -m unittest discover -s apps/notemd-plugin/scripts -p 'test_*.py'`),以及本地联调 SDK 的写法(只写进文档,不提交):
  ```toml
  [patch."https://github.com/wizlijun/note.md"]
  notemd-plugin-sdk = { path = "../../../note.md/notemd-plugin-sdk" }
  ```
- [ ] 提交:`Depend on note.md plugin-sdk-v0.1.0 by tag`。

### Task 4(任务 4):前端自带工具链,断开对 note.md 源码的导入

**文件**:改 `apps/notemd-plugin/package.json`、`src/main.ts:2-3`、`src/i18n.test.ts:2`;新建 `src/shortcuts.ts`、`src/shortcuts.test.ts`、`package-lock.json`;改 `apps/notemd-plugin/backend/src/fonts.rs:44`;根 `.gitignore` 加 `apps/notemd-plugin/node_modules/`、`apps/notemd-plugin/dist/`、`apps/notemd-plugin/backend/target/`。

**接口**(任务 8 用到):

```rust
// apps/notemd-plugin/backend/src/fonts.rs
pub const MANIFEST_JSON: &str = include_str!("../../resources/sumi/manifest.json");
// 原 :44 的解析改为 serde_json::from_str(MANIFEST_JSON)
```

```ts
// apps/notemd-plugin/src/shortcuts.ts
export function isApplePlatformSync(): boolean
export function shortcutEventBlocked(event: KeyboardEvent): boolean
export function primaryShortcut(event: KeyboardEvent, key: string, shift?: boolean): boolean
```

- [ ] 迁移前取基线:在 note.md 里 `cd plugins-src/write && node ../../node_modules/vite/bin/vite.js build`,把 `dist/` 每个文件的相对路径与 SHA-256 存到 scratchpad 的 `dist-before.txt`。
- [ ] `package.json` 的 `devDependencies` 改为四个精确版本(见全局约束),加 `"license": "Apache-2.0"`;`cd apps/notemd-plugin && npm install` 生成锁文件。
- [ ] 先写 `shortcuts.test.ts`,行为照搬 note.md 原实现:
  - `primaryShortcut_mac_requires_meta_without_ctrl`:把 `navigator.platform` 桩成 `MacIntel`,`{metaKey:true,key:'s'}` 为真,`{metaKey:true,ctrlKey:true,key:'s'}` 为假;
  - `primaryShortcut_other_requires_ctrl_without_meta`:桩成 `Linux x86_64`,`{ctrlKey:true,key:'S'}` 为真(大小写不敏感),`{ctrlKey:true,metaKey:true}` 为假;
  - `blocked_events_never_match`:`isComposing`、`keyCode 229`、`repeat`、`defaultPrevented` 任一为真时都返回假;
  - `shift_and_alt_must_match_exactly`:`shift` 参数为假而事件带 Shift 时为假,带 Alt 时为假。
- [ ] `npx vitest run src/shortcuts.test.ts` 应因找不到模块失败;实现 `shortcuts.ts`(内联 `platform-sync.ts`、`primary-modifier.ts` 的逻辑,文件头注释注明来源 note.md 路径),再跑应通过。
- [ ] `main.ts:2` 改为 `from './shortcuts'`,`main.ts:3` 与 `i18n.test.ts:2` 改为 `from './i18n'`。`git grep -n "\.\./\.\./" -- apps/notemd-plugin/src` 应无结果。
- [ ] 改 `fonts.rs`,`cargo +1.99.0 test --manifest-path apps/notemd-plugin/backend/Cargo.toml fonts` 应通过。
- [ ] `npm ci && npm test && npm run check && npm run build`,全过;把新 `dist/` 的列表与 SHA-256 和 `dist-before.txt` 比较,应完全相同(评审重点 5)。不同就停下报告,不许改源码去凑。
- [ ] 提交:`Give the plugin shell its own pinned toolchain and drop note.md imports`。

### Task 5(任务 5):待签名构建物与校验清单

**文件**:新建 `apps/notemd-plugin/scripts/build-artifact.sh`、`scripts/verify-stage.py`、`scripts/test_verify_stage.py`;改 `docs/handoff/03-notemd-contract.md` §5。

**交付格式** **[我的判断]**(写进 03 §5,替换 `[未定]`):

`build-artifact.sh --target <三元组> --out <目录> [--debug]` 在 `<目录>` 下产出(`--debug` 用调试构建,供 note.md 的开发安装;发版不用):

- `stage/`:与现行 `release_sumi()` 装配的安装布局一致(`release-plugins.sh:384-394`):`manifest.json`(即 `manifest.v2.json`)、`bin/notemd-sumi`(**未签名**)、`ui/`(Vite 产物,不含 `sounds/`)、`resources/sounds/`;
- `checklist.json`:
  ```json
  {"schema":1,"plugin":"notemd.sumi","version":"0.1.16","target":"aarch64-apple-darwin",
   "engines_notemd":">=6.1111.1","host_contract":1,"core_tag":"core-v0.1.0",
   "source_tag":"notemd-plugin-v0.1.16","source_commit":"<40 位>",
   "files":{"bin/notemd-sumi":"<sha256>","manifest.json":"<sha256>", "...":"..."}}
  ```
  `files` 覆盖 `stage/` 下每个普通文件,键为相对路径;`source_tag` 在不处于 tag 上的开发构建里为 `null`。
- 三元组只接受 `aarch64-apple-darwin`、`x86_64-apple-darwin`、`x86_64-unknown-linux-gnu`,且 manifest 的 `binary[三元组]` 必须是 `bin/notemd-sumi`(同 `release-plugins.sh:362-363`)。

脚本内的门禁(从 `release_sumi()` 原样搬来,note.md 不再重复):Linux 目标跑 `verify-linux-binary.py`;装配后对 `resources/sounds` 跑 `verify-sounds.py --reference resources/sounds`;字体目录与许可的字节门禁(原 `release-plugins.sh:398-414` 的内联 Python)搬进 `verify-stage.py`。

**接口**:

```python
# apps/notemd-plugin/scripts/verify-stage.py
def verify_fonts(stage: Path, source: Path) -> None     # 原内联门禁;失败抛 AssertionError
def build_checklist(stage: Path, meta: dict) -> dict      # meta 含 checklist 除 files 外的字段
def verify_checklist(stage: Path, checklist: dict) -> None  # 重算 SHA-256;缺文件、多文件、不符都抛错
# 命令行:verify-stage.py --verify-checklist <checklist.json> --stage <stage 目录>,不符时非零退出
```

- [ ] 先写 `test_verify_stage.py`:
  - `test_extra_file_rejected`:stage 里多一个清单外的文件 → 抛错;
  - `test_digest_mismatch_rejected`;
  - `test_font_payload_rejected`:stage 任意位置出现 `.woff2` → 抛错;
  - `test_catalog_bytes_must_match_source`:`ui/sumi/manifest.json` 与源差一个字节 → 抛错;
  - `test_checklist_roundtrip`:`build_checklist` 后 `verify_checklist` 通过。
- [ ] `python3 -I -m unittest discover -s apps/notemd-plugin/scripts -p 'test_*.py'` 应失败;实现后应全过(含迁入的 `test_verify_linux_binary.py`)。
- [ ] 写 `build-artifact.sh`:`set -euo pipefail`;`cargo +1.99.0 build --release --locked --target <三元组>`;`npm ci && npm run check && npm run build`;装配;跑门禁;写 `checklist.json`。脚本不读取、不需要任何签名或公证凭据。
- [ ] 在本机跑 `bash apps/notemd-plugin/scripts/build-artifact.sh --target aarch64-apple-darwin --out <scratchpad>/artifact`,应成功,且 `verify_checklist` 对产物通过。
- [ ] 改 03 §5:写上交付格式;“note.md 收到后”一段改为:比对 `source_commit` → `verify_checklist` → macOS 目标签名公证二进制并替换 `bin/notemd-sumi` → 打包 → minisign → 索引 → 上架。状态行保持 `[未定]` 直到任务 8 交付后补证据。
- [ ] `bash docs/check.sh` 输出 `OK`,提交:`Build unsigned plugin artifacts with a verifiable checklist`。

### Task 6(任务 6):说明文件、许可与变更记录

**文件**:改 `apps/notemd-plugin/package.json`(已在任务 4)、`apps/notemd-plugin/backend/Cargo.toml`(`license = "Apache-2.0"`);改 `README.md`、`CHANGELOG.md`、`CHANGELOG.zh-CN.md`、`docs/handoff/00-overview.md`、`AGENTS.md`。

- [ ] 根 `README.md` 的仓库结构加 `apps/notemd-plugin/` 及其测试命令(指向它自己的 README)。
- [ ] 两份 CHANGELOG 的“未发布”区加:“插件壳、资源与三个插件侧脚本从 note.md 迁入 `apps/notemd-plugin/`,行为不变;新增待签名构建物与校验清单”。
- [ ] `AGENTS.md` 第 7 条**提议**把 `apps/notemd-plugin/` 加进“改模块先跑模块测试”的范围。规程改动,用户认可本计划即视为认可;否则删掉这一步。
- [ ] `bash docs/check.sh` 输出 `OK`,提交:`Document the plugin shell layout and checks`。

### Task 7(任务 7):全量验证、合并与打 tag [需 G3]

- [ ] 在 `phase2` 上跑 `apps/notemd-plugin/README.md` Verification 段全部命令,加任务 5 的本机构建;另把产物装进本机正式宿主:按 `dev-install-plugin.sh:503-512` 的布局手工拷到插件目录,打开玄霜写作,跑现有验收清单(设计 §8)里不需要第二台设备的条目。全部应通过;不通过就停下,记下差异报告用户。
- [ ] `--no-ff` 合并回本地 `main`,打附注 tag `notemd-plugin-v0.1.16`(信息:`Sumi Write plugin 0.1.16 imported from note.md <提交>`)。
- [ ] 推送 `main` 与 tag,推送前再向用户确认一次。推完后在空目录用临时 crate 验证能拉到:`notemd-sumi-backend = { git = "https://github.com/wizlijun/sumiwrite", tag = "notemd-plugin-v0.1.16" }`,`cargo +1.99.0 fetch`。

### Task 8(任务 8):note.md 改依赖、改脚本、删目录(一个提交)[需 G4]

**分支**:note.md 上的 `sumi/plugin-from-sumiwrite`,从当时的 `main` 开出。

**本仓库位置的约定** **[我的判断]**:note.md 里所有需要本仓库文件的脚本统一读环境变量 `SUMIWRITE_DIR`,默认 `$REPO_ROOT/../sumiwrite`。目录不存在时报“需要 sumiwrite 检出,设置 SUMIWRITE_DIR”并非零退出。发版(`release_sumi()`)另外要求:`git -C $SUMIWRITE_DIR describe --exact-match --tags` 输出 `notemd-plugin-v<manifest 版本>`,且 `git status --porcelain` 为空。

**文件**(note.md):

- `src-tauri/Cargo.toml:140`:`notemd-sumi-backend = { git = "https://github.com/wizlijun/sumiwrite", tag = "notemd-plugin-v0.1.16" }`;文件末尾加
  ```toml
  [patch."https://github.com/wizlijun/note.md"]
  notemd-plugin-sdk = { path = "../notemd-plugin-sdk" }
  plugin-protocol = { path = "../plugin-protocol" }
  ```
  并更新 `src-tauri/Cargo.lock`。
- 新建 `src-tauri/src/sumi/backend_proxy_tests.rs`(`#[cfg(test)]`,在 `src-tauri/src/sumi/mod.rs` 声明):接收任务 3 从插件后台移出的 `host_proxy_harness` 测试模块(原文见本仓库 `2f5a320:apps/notemd-plugin/backend/src/lib.rs:172-519`)。它测的是宿主的持久化代理,归 note.md。移植时 `crate::durability` 改为 `notemd_sumi_backend::durability`,`include!` 的宿主 `durability.rs` 改为直接用宿主自己的 `super::durability`,崩溃子进程测试的过滤名随模块路径更新;顺手修 clippy `cloned_ref_to_slice_refs`(原 `:469`,改用 `std::slice::from_ref`)。这 11 个测试全部要在 note.md 跑通。
- `src-tauri/src/sumi/mod.rs:4091`:改用 `notemd_sumi_backend::fonts::MANIFEST_JSON`。
- `scripts/release-plugins.sh` `release_sumi()`:改为在 `$SUMIWRITE_DIR` 跑 `apps/notemd-plugin/scripts/build-artifact.sh --target "$triple" --out <临时目录>`;比对清单 `source_commit` 与 `git -C $SUMIWRITE_DIR rev-parse HEAD`;用 `python3 -I $SUMIWRITE_DIR/apps/notemd-plugin/scripts/verify-stage.py --verify-checklist <清单> --stage <stage>` 核对;macOS 目标对 `stage/bin/notemd-sumi` 跑 `native-release.py`,把签好的二进制换回 `stage/bin/`;然后沿用现有的 `zip_pkg`、`sign_pkg`、拷 manifest。删掉原函数里的构建、`verify-linux-binary.py`、`verify-sounds.py` 与内联字体门禁。凭据检查(`:364-370`)保留。
- `scripts/sumi/native-release.py:11`:`SOURCE_DIRS` 只留 note.md 自己的 `notemd-plugin-sdk`、`plugin-protocol`、`scripts/sumi/native-release.py`、`scripts/release-plugins.sh`;`:30` 的断言改为要求 `scripts/sumi/native-release.py` 在列表里。插件源码的来源证明改为:`native-release.py` 新增参数 `--checklist <路径>`,把清单的 `source_tag`、`source_commit` 与 `files` 摘要写进它的输出记录。
- `scripts/sumi/test_native_release.py:42`:断言改为 `{'notemd-plugin-sdk','plugin-protocol'} <= set(n.SOURCE_DIRS)` 且不含 `plugins-src/write/backend`;新增一条测 `--checklist` 写入输出记录。
- `scripts/sumi/verify-release.py:492`:改为 `json.loads(source('v'+VERSION, 'plugins-src/write/resources/sumi/manifest.json'))`。
- `scripts/dev-install-plugin.sh:493-512`:改为在 `$SUMIWRITE_DIR` 跑 `build-artifact.sh`(`PROFILE` 为 debug 时加 `--debug`),然后把 `stage/` 拷到安装目录。
- 读字体目录的五处(任务 1 表格第 3 行):路径改为 `$SUMIWRITE_DIR/apps/notemd-plugin/resources/sumi/manifest.json`。两个 `.m` 探针不读环境变量,改为由调用它们的脚本经命令行参数传入路径。
- `scripts/sumi/acceptance/build.sh`、`prepare.py`、`test_prepare.py`:插件构建与 manifest 读取改到 `$SUMIWRITE_DIR`;测试里的临时布局随之改。
- `.gitattributes:55`、`:56`、`:59`,`.gitignore:74`:删掉。
- 删除 `plugins-src/write/`、`scripts/sumi/verify-sounds.py`、`verify-linux-binary.py`、`test_verify_linux_binary.py`;`pnpm install` 重算 `pnpm-lock.yaml`。
- `scripts/sumi/README.md`、`verify-release.md`:写明 `SUMIWRITE_DIR` 约定与发版对 tag 的要求。

步骤:

- [ ] 改 `src-tauri` 依赖并更新锁文件。**锁文件闸门**(评审重点 1):`cargo +1.99.0 tree -d -e normal,dev --manifest-path src-tauri/Cargo.toml` 里不出现 `plugin-protocol`、`notemd-plugin-sdk`、`write-core`、`sumi-protocol`;`cargo tree -i yrs` 为 `yrs v0.24.0`;`Cargo.lock` 的 diff 只涉及 `notemd-sumi-backend` 及其新增的 git 来源。不满足就停下。
- [ ] 改脚本、删目录,然后 `git grep -n "plugins-src/write"`,不在 `docs/`、`CHANGELOG*`、`tasks/`(历史发版记录)和 `verify-release.py` 的冻结源码清单里的命中都要清掉。
- [ ] 跑 note.md 侧验证,全部应通过:
  - `cargo +1.99.0 test --manifest-path src-tauri/Cargo.toml sumi`(含 `lifecycle_tests`、`recovery_tests`、`font_catalog_contains_only_selected_presets`);
  - `python3 scripts/sumi/test_native_release.py`;`python3 scripts/sumi/verify-release.py --self-test`;`python3 -I -m unittest scripts/sumi/acceptance/test_prepare.py`;
  - `SUMIWRITE_DIR=~/git/sumiwrite bash scripts/dev-install-plugin.sh sumi`,装好后打开玄霜写作能写字;
  - `SUMIWRITE_DIR` 指向不存在的目录时,上面这条与 `release_sumi` 都以清楚的报错退出;
  - 发版路径只演练到签名之前:在 tag 上的干净检出跑 `release_sumi()` 的构建与核对部分(可用环境变量让它在 `native-release.py` 之前停下;若脚本没有这个开关,手工逐条执行这些命令),不签名、不发布。

  失败时先查是不是迁移引起的;不迁移也一样失败的,记下来报告用户,不顺手修。
- [ ] 一个提交:`Build Sumi Write from sumiwrite notemd-plugin-v0.1.16 and drop the in-tree plugin`。

### Task 9(任务 9):旧位置加指引、补证据(note.md 与本仓库各一个提交)[需 G4]

- [ ] note.md:`plugins-src/shared/shortcuts.ts` 文首加注释,说明玄霜写作已在 sumiwrite 自带一份,两者不再同步;`src/lib/sumi/i18n.ts` 同样加一行说明。提交:`Note that Sumi Write keeps its own shortcuts and i18n copies`。
- [ ] 本仓库:03 §5 与 02 第 2 期的状态补上任务 8 提交的 blob 证据链接(按 `docs/check.sh` 的规则);00-overview 的当前状态改为“第 2 期已完成”。`bash docs/check.sh` 输出 `OK`,提交:`Record phase 2 completion`。然后停下,把 note.md 分支交给用户决定合并与推送。

### Task 10(任务 10):归档目录与写作工作区(另立计划)

依据 `docs/superpowers/specs/2026-11-20-archive-directory-design.md`(已认可)。任务 7 合并、插件后台已在本仓库之后,另写 `docs/superpowers/plans/2026-11-20-archive-directory.md`:那时插件后台的文件路径已定,改动直接落在 `apps/notemd-plugin/backend/`。它涉及内核破坏性变更(`core-v0.2.0`)、契约升到 v2、宿主与插件配套发版,规模与本期迁移相当,单独评审。

---

## 回退

- note.md:revert 任务 8 那个提交,插件目录、树内构建和 path 依赖一起回来;tag `plugin-sdk-v0.1.0` 留着无害。
- 本仓库:保留已迁入的历史和 tag;note.md 回退期间 `apps/notemd-plugin/` 不接受改动,避免两份源码分叉。
- 插件市场:本期不发包,无需回退。

## 本期不做

- 不改插件行为、版本号、manifest、契约版本(仍是 `host-contract v1`)。
- 不发新插件包,不签名、不公证、不上架。
- 不迁 `scripts/sumi/` 里判定归 note.md 的条目,不拆 `verify-release.py`。
- 不做 `session/` 下沉(第 3 期),不做归档目录(任务 10,另立计划)。
- 不建 CI。
