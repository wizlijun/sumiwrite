# 第 1 期详细计划:迁内核、服务契约与同步服务

> **给执行的 agent:** 按任务顺序执行,每步用 `- [ ]` 勾选。必需的子技能:superpowers:executing-plans(或 superpowers:subagent-driven-development)。

**目标**:把 `write-core/`、`sumi-protocol/`、`write-sync-worker/` 连同历史迁进本仓库,分别放到 `core/`、`protocol/`、`sync/`,并且自给自足;打 `core-v0.1.0` tag;note.md 改为按 tag 引用,并删掉自己那份。

**做法**:在 note.md 的全新克隆上用 `git filter-repo` 提取历史,并入本仓库的 `phase1` 分支。先在本仓库修路径、解依赖、改许可,三个模块的测试全过后再打 tag。note.md 一侧的依赖切换与目录删除放在同一个提交里,做在单独分支上。

**技术栈**:Rust 1.99.0(yrs 0.24.0、rusqlite bundled)、Node + Wrangler 3.114.17 + vitest 2.1.9(workers 池)、Python 3 运维脚本、git-filter-repo。

**依据**:[02-migration-plan.md](../handoff/02-migration-plan.md) 第 1 期(顺序与验收口径)、[01-inventory.md](../handoff/01-inventory.md) §5–§6、设计 §5.3、§8、§12(note.md `docs/sumiwrite-extraction` 分支,提交 `0c11629f`)。本计划与 02 冲突时,先改 02(任务 1)再动手。

---

## 开工前置(用户门禁)

以下事项由用户决定或执行,任一未落实,对应任务不开工:

| # | 事项 | 卡住哪个任务 |
|---|---|---|
| G1 | 推送 note.md `docs/sumiwrite-extraction` 分支,公开设计与第 0 期计划 | 任务 6(把文档引用改成 blob 链接) |
| G2 | 建 sumiwrite 公开远端。本计划假设地址是 `https://github.com/wizlijun/sumiwrite`,地址不同则全文替换 | 任务 7 |
| G3 | 认可凭据方案(见任务 5):令牌与账号 ID 只从环境变量或 macOS 钥匙串读,仓库里不放任何凭据文件 | 任务 5 |
| G4 | 允许在 note.md 开分支 `sumi/core-from-sumiwrite` 做第 7、8 步;合并与推送另由用户定 | 任务 8、9 |

以下事项由执行者完成,不需要用户决定 **[我的判断]**:

- **修 Rust 1.99.0 工具链**:本机 `1.99.0-aarch64-apple-darwin` 是下载卡住留下的残缺安装,报 `missing manifest`。重装命令:`rustup toolchain uninstall 1.99.0 && rustup toolchain install 1.99.0 --profile minimal -c clippy`。重装失败就停下报告,不得改用 stable 代替,因为不同版本的 clippy 规则不同。
- **装 git-filter-repo**:`brew install git-filter-repo`。

**基线(2026-11-20 实测)**:
- note.md `main` 在 `3c710c9e`。`969f8e73` 之后,三个目录都没有改动。
- `write-core` 在 stable 1.99.1 上 85 个测试通过,`sumi-protocol` 4 个通过。
- `write-sync-worker` 在本机**跑不起来**:`../worker/node_modules/.bin` 不存在,本目录也没装 `yjs`。所以同步服务没有可比的本机基线,迁移后以“自带工具链下全部通过”作为验收。

## 全局约束

- 线格式红线:`yrs = "=0.24.0"`,Yjs `13.6.33`,对 Yjs 的互操作测试必须通过(设计 §3)。
- 同步服务钉死 Wrangler `3.114.17`,`compatibility_date = "2024-12-30"`,`compatibility_flags = ["nodejs_compat"]`,都不随迁移改动。
- Rust 一律用 `cargo +1.99.0`。
- **crate 名不变**:仍叫 `write-core`、`sumi-protocol`,只改目录名。这样 note.md 里的 `use write_core` / `use sumi_protocol` 一行都不用动 **[我的判断]**。
- 仓库公开:不得提交令牌、账号 ID 或私有路径;凭据只写引用位置(AGENTS.md 第 5 条)。
- note.md 每个提交都必须能照常构建和发版;两个仓库不得各留一份可编辑源码(02 总红线)。
- note.md 一侧遵守其 `CLAUDE.md`。本期 note.md 的改动没有用户能感知的变化,所以不加 CHANGELOG 条目 **[我的判断]**。
- 文档用简体中文,提交信息用英文祈使句,结尾带 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。本仓库每次提交前 `bash docs/check.sh` 必须输出 `OK`。

## 评审重点

测试本身覆盖不到、最可能出事的五处,按可能性从高到低:

1. **锁文件漂移**:path 依赖换成 git 依赖后,`cargo update` 可能顺带升级传递依赖,`yrs` 一变线格式就变。任务 8 要求三份 `Cargo.lock` 的 diff 只改 `write-core` 和 `sumi-protocol` 的 `source` 行,并断言 `yrs 0.24.0` 不变。
2. **图里出现两份 `write-core`**:`sumi-protocol` 在 git 检出里经 `path = "../core"` 依赖内核,note.md 又直接依赖 git 上的 `write-core`;两者要解析为同一个包,否则类型对不上。任务 8 用 `cargo tree -d` 断言没有重复。
3. **凭据随历史公开**:filter-repo 会带上这三个目录的全部历史。任务 2 在推送前扫描历史里的令牌、账号 ID 和私有路径。
4. **测试零条也算通过**:`scripts/test.mjs` 逐个文件跑 vitest,如果目录读错就一个都不跑,却照样退出 0。任务 4 要求实际跑到 6 个测试文件。
5. **离线构建拿不到 git 依赖**:`scripts/sumi/run-native.mjs` 用 `--offline --locked`。任务 8 先 `cargo fetch`,并把这一步写进 `scripts/sumi/README.md`。

---

### 任务 1:把新发现补进交接文档

迁移计划和清单漏列了几处跨模块依赖(下表),按 02 文首的规矩先改文档再动手。

**文件**:改 `docs/handoff/02-migration-plan.md`(第 1 期步骤 2、3、7 和前置条件)、`docs/handoff/01-inventory.md` §5、`docs/handoff/04-known-gaps.md`。

| 漏列项 | 位置(note.md `3c710c9e`) | 本计划的处理 |
|---|---|---|
| 同步服务测试经相对路径导入内核夹具 | `write-sync-worker/tests/{service,wire-validator,packed-validator}.test.ts` 第 7–9 行 `../../write-core/tests/fixtures/*.json` | 任务 3 改成 `../../core/...` |
| 验收脚本借用 note.md 的 `ws` | `scripts/cloud-acceptance.mjs:10` 引用 `../../worker/node_modules/.pnpm/ws@8.18.0/...` | 任务 4 改为自带 `ws@8.18.0` |
| 容量脚本假设 note.md 的目录布局 | `scripts/packed-capacity-local.mjs:6` 用 `root/tasks/sumi-sync` 和 `root/write-sync-worker/src` | 任务 4 改到 `sync/.local` |
| 文档里写着旧命令 | `PACKED-INDEX.md:28` | 任务 4 |
| 插件后台测试用 `include_str!` 读内核夹具 | `plugins-src/write/backend/src/sync.rs:1907-1908` | 任务 3 让内核用 feature 导出夹具,任务 8 改用 |
| 发布与基准脚本对内核源码算摘要 | `scripts/sumi/verify-release.py:44`、`build.mjs:19`、`run-native.mjs:12`、`:14-15`(把 `write-core/target` 当构建目录) | 任务 8 |
| `.gitignore` 里写着旧目录 | note.md `.gitignore:71`、`:73` | 任务 8 |

- [ ] 把上表写进 01 §5(新增一张“迁移时才发现”的子表)和 02 第 1 期对应步骤;前置条件里“第 1 期详细计划已立”一句加上指向本文的链接。
- [ ] 04-known-gaps 记三件事:本机 1.99.0 工具链残缺;同步服务在 note.md 里没有可运行的本机基线;`tasks/sumi-sync/` 在本机不存在,没有要迁移的部署状态。
- [ ] `bash docs/check.sh` 输出 `OK`,然后提交:`Record cross-module dependencies found while planning phase 1`。

### 任务 2:提取历史并并入本仓库

**产出**:本仓库 `phase1` 分支上有 `core/`、`protocol/`、`sync/`,带原有历史(最早的是 2026-11-07 的 `94fde1d8`)。

- [ ] 在 scratchpad 里做全新克隆,并记下提取所用的提交:
  ```bash
  git clone --no-local ~/git/note.md notemd-extract && cd notemd-extract && git rev-parse HEAD
  git filter-repo --path write-core/ --path sumi-protocol/ --path write-sync-worker/ \
    --path-rename write-core/:core/ --path-rename sumi-protocol/:protocol/ \
    --path-rename write-sync-worker/:sync/
  ```
- [ ] **公开前扫描**:`git log -p --all` 里不得出现 `CLOUDFLARE_API_TOKEN=` 后跟值、`account_id = "`、32 位十六进制账号 ID、`/Users/`、`/private/tmp/sumi-cloud-`。命中任何一项就停下报告用户,不要擅自改写历史。
- [ ] 在本仓库执行 `git switch -c phase1 && git pull --allow-unrelated-histories <notemd-extract 路径> main`,合并提交信息写:`Import core, protocol and sync from note.md <提交>`。
- [ ] 核对:`git log --oneline -- core protocol sync | wc -l` 等于 note.md 上 `git log --oneline -- write-core sumi-protocol write-sync-worker | wc -l`;三个目录下的文件数与 note.md 源目录一致(用 `git ls-files | wc -l` 对比)。

### 任务 3:修模块间的相对路径,并导出内核夹具

**文件**:
- 改:`protocol/Cargo.toml:10` 改为 `write-core = { path = "../core" }`。
- 改:`sync/scripts/interop.mjs:5`,以及 `sync/tests/{service,wire-validator,packed-validator}.test.ts` 的夹具导入,`../../write-core/` 一律改成 `../../core/`。
- 新建:`core/src/fixtures.rs`;改 `core/src/lib.rs`、`core/Cargo.toml`。
- 测试:`core/tests/fixtures_export.rs`。

**接口**(任务 8 会用到):

```rust
// core/Cargo.toml: [features] fixtures = []
// core/src/lib.rs: #[cfg(feature = "fixtures")] pub mod fixtures;
pub const YRS_V1: &str;            // include_str!("../tests/fixtures/yrs-v1.json")
pub const PENDING_INVALID_V1: &str;
pub const FORK_V1: &str;
```

理由 **[我的判断]**:插件后台的测试原先按 note.md 目录布局读夹具。改成 git 依赖之后,依赖源码在 Cargo 的检出目录里,相对路径失效。复制一份夹具又会违反“不各留一份”,所以由内核把夹具导出为常量。这只是新增,而且放在 feature 后面,不改任何已有行为。

- [ ] 先写测试 `fixtures_export_parses`:带 `--features fixtures` 运行,三个常量都能被 `serde_json` 解析;`YRS_V1` 的 `pageId` 与 `expected.body` 等于直接读 `tests/fixtures/yrs-v1.json` 得到的值。
- [ ] 运行 `cargo +1.99.0 test --manifest-path core/Cargo.toml --features fixtures --test fixtures_export`,应因找不到 `fixtures` 模块而失败。
- [ ] 实现 `fixtures.rs`,再跑同一条命令,应通过。
- [ ] 跑 `cargo +1.99.0 test` 与 `clippy --all-targets -- -D warnings`,`core/` 和 `protocol/` 各跑一遍,`core/` 另加一遍 `--all-features`,都应通过。`core` 应当是 85 个测试加 1 个新测试。
- [ ] 提交:`Fix cross-module paths and export core fixtures behind a feature`。

### 任务 4:同步服务自带工具链

**文件**:改 `sync/package.json`、`sync/package-lock.json`、`sync/tsconfig.json`、`sync/scripts/test.mjs`、`sync/scripts/deploy.sh`、`sync/scripts/packed-capacity-local.mjs`、`sync/scripts/cloud-acceptance.mjs`、`sync/PACKED-INDEX.md`、`sync/README.md`;删 `sync/scripts/link-toolchain.mjs`;新建本仓库根目录 `.gitignore`。

- [ ] 在 `package.json` 里**精确钉住**版本:`devDependencies` 写 `wrangler 3.114.17`、`vitest 2.1.9`、`@cloudflare/vitest-pool-workers 0.5.41`、`@cloudflare/workers-types 4.20260702.1`、`typescript 5.9.3`、`ws 8.18.0`。这些就是 note.md `worker/node_modules` 里现有的版本。`dependencies.yjs` 保持 `13.6.33`。另外加 `"license": "Apache-2.0"`。
- [ ] `scripts` 改用本目录的工具:`check` 写 `tsc --noEmit`,`dev` 写 `wrangler dev`,`deploy` 写 `wrangler deploy`;删掉 `pretest` 与 `precheck`,并删除 `link-toolchain.mjs`。`tsconfig.json` 的 `types` 改为 `["@cloudflare/workers-types"]`。
- [ ] `test.mjs` 改调 `node_modules/.bin/vitest`。另外**断言实际跑了 6 个测试文件**,少于 6 个就以非零退出(评审重点 4)。文件名的排序和“每个文件一个新运行时”的做法不变。
- [ ] 本地状态目录统一为 `sync/.local/`,写进 `.gitignore`。它取代原来的 `../tasks/sumi-sync`。要改的是 `deploy.sh:11-16`(`deploy.sh` 也改为读取 `node_modules/wrangler/package.json` 来校验 `3.114.17`)、`packed-capacity-local.mjs:6` 和 `cloud-acceptance.mjs:11-12`。根目录 `.gitignore` 另加 `core/target/`、`protocol/target/`、`sync/node_modules/`、`sync/.wrangler/`。
- [ ] `cloud-acceptance.mjs:10` 改为 `require('ws')`。
- [ ] `PACKED-INDEX.md:28` 和 `README.md` 里的命令改成在 `sync/` 下执行的写法。
- [ ] `cd sync && npm install`(联网,生成新的锁文件),然后依次跑 `npm ci && npm test && npm run check && node scripts/interop.mjs`。应当:6 个测试文件全部通过,`tsc` 没有报错,interop 输出 `fixture keys:` 且没有断言失败。
- [ ] `git grep -n -e '\.\./worker' -e 'tasks/sumi-sync' -e 'write-sync-worker' -e 'write-core' -- sync` 只允许命中 `CLOUD-ACCEPTANCE.md` 这类历史验收记录,不允许命中可执行文件。
- [ ] 提交:`Give the sync service its own pinned toolchain`。

### 任务 5:云管理脚本的凭据与路径 [需 G3]

**文件**:改 `sync/scripts/cloud-admin.py`;新建测试 `sync/scripts/test_cloud_admin.py`(unittest)。

**凭据方案** **[我的判断]**,需用户认可,即门禁 G3:

- 令牌依次从两处取:环境变量 `CLOUDFLARE_API_TOKEN`;取不到就读 macOS 钥匙串的通用密码,服务名 `sumiwrite.cloudflare.api-token`(`security find-generic-password -s <服务名> -w`,输出只进内存)。
- 账号 ID 依次从两处取:`CLOUDFLARE_ACCOUNT_ID`;取不到就读钥匙串服务名 `sumiwrite.cloudflare.account-id`。
- 不再读任何 `.env` 或 `wrangler.toml`。两处都取不到时报错,报错只说缺哪一项,不打印任何值。

**接口**:

```python
def resolve_credentials(environ: dict[str, str], keychain: Callable[[str], str | None]) -> dict[str, str]
# 返回 {'CLOUDFLARE_API_TOKEN': ..., 'CLOUDFLARE_ACCOUNT_ID': ...};缺任一项抛 RuntimeError
```

- [ ] 先写测试,四种情况:
  - `test_env_wins_over_keychain`:环境变量和钥匙串都有值时,用环境变量的;
  - `test_falls_back_to_keychain`;
  - `test_missing_token_message_has_no_values`:缺令牌时抛出的错误信息里不含账号 ID 的值;
  - `test_never_reads_dotenv`:在临时目录放一个 `.env`,其中有令牌,结果仍应报缺失。
- [ ] 运行 `python3 -I -m unittest sync/scripts/test_cloud_admin.py`,应失败。
- [ ] 实现 `resolve_credentials`,并把模块顶层的 `PRIVATE`、`ENV`、`ACCOUNT` 挪到 `main()` 里初始化,这样导入模块不会产生副作用,测试才能导入它。路径改为:
  - `ROOT=parents[2]`,现在指向本仓库根;
  - `WORKER=ROOT/'sync'`;
  - `TASK=ROOT/'sync/.local'`;
  - `WRANGLER=WORKER/'node_modules/.bin/wrangler'`;
  - `wrangler()` 的版本校验读 `WORKER/'node_modules/wrangler/package.json'`;
  - `source_proof()` 里的 `git status -- write-sync-worker` 改为 `-- sync`。
- [ ] 再跑测试,应通过。另跑 `env -u CLOUDFLARE_API_TOKEN -u CLOUDFLARE_ACCOUNT_ID python3 -I sync/scripts/cloud-admin.py private-path`:要么用钥匙串里的值,要么报缺失,但不得联网,也不得打印凭据。
- [ ] `sync/README.md` 写明两个钥匙串服务名,以及如何用 `security add-generic-password` 存入。只写引用,不写值。
- [ ] 提交:`Read cloud credentials from environment or Keychain only`。

### 任务 6:许可、说明文件和变更记录

**文件**:改 `core/Cargo.toml`(`license = "Apache-2.0"`);`protocol/Cargo.toml` 加 `license = "Apache-2.0"`;新建 `protocol/README.md`;新建 `CHANGELOG.md` 与 `CHANGELOG.zh-CN.md`;改 `README.md`、`AGENTS.md`、`docs/handoff/00-overview.md`、`docs/handoff/04-known-gaps.md`。

- [ ] `protocol/README.md` 写三件事:它是什么(宿主与插件后台之间的服务契约类型);测试命令(`cargo +1.99.0 test` 与 `clippy --all-targets -- -D warnings`,沿用 `core/` 的写法);它依赖 `../core`。
- [ ] 两份 CHANGELOG 沿用 note.md 的格式:倒序,顶部一个“未发布”区。首条写“`core/`、`protocol/`、`sync/` 从 note.md 迁入,线格式不变”,以及“同步服务改为自带工具链,凭据只从环境变量或钥匙串读”。
- [ ] `README.md` 的仓库结构加上这三个目录及各自的测试命令。`00-overview` 的“已完成”一段更新为本期结果。
- [ ] `AGENTS.md` **提议**新增一条:改 `core/`、`protocol/`、`sync/` 后,提交前跑该模块 README 里的测试命令。这是规程改动,用户认可本计划即视为认可这一条;否则删掉这一步。
- [ ] 若 G1 已落实,把所有指向设计和第 0 期计划的路径引用改为固定提交的 blob 链接(02 第 1 期前置条件第一步);未落实就留着,这一步记进 04。
- [ ] `bash docs/check.sh` 输出 `OK`,然后提交:`Relicense modules to Apache-2.0 and document the new layout`。

### 任务 7:全量验证、合并与打 tag [需 G2]

- [ ] 在 `phase1` 上跑 02 第 1 期“验证”一节的全部命令,外加 `cargo +1.99.0 test --manifest-path core/Cargo.toml --all-features` 和任务 5 的单测。所有命令都应通过;`cargo tree --manifest-path core/Cargo.toml -i yrs` 显示 `yrs v0.24.0`。
- [ ] 把 `phase1` 合并回本地 `main`(`--no-ff`),然后打附注 tag:`git tag -a core-v0.1.0 -m "core, protocol and sync imported from note.md <提交>"`。
- [ ] 推送 `main` 和 `core-v0.1.0` 到 G2 的远端,推送前再向用户确认一次。推完后在一个空目录里用一个临时 crate 验证能拉到包:`write-core = { git = "https://github.com/wizlijun/sumiwrite", tag = "core-v0.1.0" }`,执行 `cargo +1.99.0 fetch`。

### 任务 8:note.md 改依赖并删目录(一个提交)[需 G4]

**分支**:note.md 上的 `sumi/core-from-sumiwrite`,从当时的 `main` 开出。

**文件**(note.md):
- 依赖:`src-tauri/Cargo.toml:39-40`、`plugins-src/write/backend/Cargo.toml:12-13`、`scripts/sumi/native/Cargo.toml:6` 改为 `{ git = "https://github.com/wizlijun/sumiwrite", tag = "core-v0.1.0" }`。`plugins-src/write/backend/Cargo.toml` 的 `[dev-dependencies]` 加同一来源的 `write-core`,带 `features = ["fixtures"]`。
- 锁文件:`src-tauri/Cargo.lock`、`plugins-src/write/backend/Cargo.lock`、`scripts/sumi/native/Cargo.lock`。
- `plugins-src/write/backend/src/sync.rs:1907-1908`:改用 `write_core::fixtures::YRS_V1`。
- `scripts/sumi/native-release.py:11`:`SOURCE_DIRS` 去掉 `sumi-protocol` 和 `write-core`。内核的来源证明改由已在列表中的 `plugins-src/write/backend` 下受控的 `Cargo.lock` 承担,它钉住了 tag 和提交。
- `scripts/sumi/test_native_release.py:42`:断言集合去掉这两项,改为断言 `plugins-src/write/backend` 在列表中。
- `scripts/sumi/verify-release.py:44`:`sumi-protocol/src/fonts.rs` 换成 `plugins-src/write/backend/Cargo.lock`(若已在列表中就只删不加)。
- `scripts/sumi/build.mjs:19`、`run-native.mjs:12`:输入清单去掉 `write-core/src/*`;`run-native.mjs` 的清单里已经有 `scripts/sumi/native/Cargo.lock`。
- `run-native.mjs:14-15`:`CARGO_TARGET_DIR` 和产物路径改为 `scripts/sumi/native/target`,并加进 `.gitignore`。
- `scripts/sumi/README.md:13`、`:62`、`verify-release.md:19`:文字改为“内核来自 sumiwrite `core-v0.1.0`”;第 62 行补上“离线构建前先 `cargo +1.99.0 fetch --manifest-path scripts/sumi/native/Cargo.toml`”。
- `.gitignore:71`、`:73`:删掉。
- 删除 `write-core/`、`sumi-protocol/`、`write-sync-worker/`。
- 本地联调写法(设计 §5.3)只写进 `scripts/sumi/README.md`,不提交实际的 `[patch]`:

  ```toml
  [patch."https://github.com/wizlijun/sumiwrite"]
  write-core = { path = "../sumiwrite/core" }
  sumi-protocol = { path = "../sumiwrite/protocol" }
  ```

步骤:

- [ ] 改依赖,然后对每个清单执行 `cargo +1.99.0 update -p write-core -p sumi-protocol --manifest-path <清单>`。
- [ ] **锁文件闸门**(评审重点 1、2):
  - 三份锁文件的 `git diff` 只许改 `write-core` 与 `sumi-protocol` 两个条目的 `source` 行;
  - `cargo tree -i yrs` 显示 `yrs v0.24.0`;
  - `cargo tree -d` 里没有 `write-core` 或 `sumi-protocol`。

  任一不满足就停下。不许用 `cargo update` 无参数的写法去修。
- [ ] 改脚本、改 `sync.rs`、删目录、改 `.gitignore`,然后用 `git grep -n -e 'write-core/' -e 'sumi-protocol/' -e 'write-sync-worker'` 排查,不在 `docs/`、`CHANGELOG*` 里的命中都要清掉。
- [ ] 跑 note.md 侧的验证:
  - `cargo +1.99.0 test --manifest-path src-tauri/Cargo.toml sumi`,其中包括 `lifecycle_tests` 和 `recovery_tests`;
  - `cargo +1.99.0 test --manifest-path plugins-src/write/backend/Cargo.toml`,同时编译那个 `#[ignore]` 的联机测试;
  - `cd plugins-src/write && npm test && npm run check`;
  - `python3 scripts/sumi/test_native_release.py`;
  - `cargo +1.99.0 fetch --manifest-path scripts/sumi/native/Cargo.toml && node scripts/sumi/run-native.mjs --smoke`;
  - `scripts/release-plugins.sh` 里 `release_sumi()` 用到的构建命令 `cargo build --release --locked --manifest-path plugins-src/write/backend/Cargo.toml --bin notemd-sumi`,只构建,不签名、不发布。

  全部应通过。失败时先查是不是迁移引起的。如果不迁移也一样失败(比如 Node 26 的已知问题),就记下来报告用户,不顺手去修。
- [ ] 一个提交:`Depend on sumiwrite core-v0.1.0 and drop the in-tree copies`。

### 任务 9:旧文档加指引(note.md,另一个提交)[需 G4]

- [ ] 本仓库 `docs/spec/MAPPING.md` 的“旧文档”一列里列出的每一份 note.md 文档,文首第一行都加上:`> 现行规范已迁至 sumiwrite:https://github.com/wizlijun/sumiwrite/tree/main/docs/spec。本文仅作历史记录。` 这是设计 §7.2 对 note.md 文档唯一的改动。
- [ ] 提交:`Point superseded Sumi docs to sumiwrite`。然后停下,把两个分支提交交给用户决定合并与推送。

---

## 回退

照 02 第 1 期“回退”一节执行:note.md revert 任务 8 那个提交,目录和 path 依赖就一起回来;任务 9 的提交可以单独 revert。本仓库保留已迁入的历史和 tag,但在 note.md 重新切换过来之前,`core/`、`protocol/`、`sync/` 不接受改动。

## 本期不做

- 不改线格式,不升 Yrs、Yjs、Wrangler,不改兼容日期。
- 不部署同步服务,也不碰现有云资源。任务 5 只改脚本,不运行 `deploy`。
- 不建 CI。远端建好后是否接 GitHub Actions,另行决定。
- 不迁插件壳、资源和插件侧脚本,那是第 2 期。
