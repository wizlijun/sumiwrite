# 02 迁移计划

本文只定**顺序与验收口径**。第 1、2、3 期开工前各自另立详细计划(设计 §8、§11),逐条细化本文的步骤;详细计划与本文冲突时,先改本文再动手。

来源:设计 [`docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md`](https://github.com/wizlijun/note.md/blob/0c11629f976226c688d186b13d4812da31073dc2/docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md)(note.md 提交 `0c11629f`)§8、§9、§10.3;逐目录清单 [01-inventory.md](01-inventory.md);契约 [03-notemd-contract.md](03-notemd-contract.md)。基线 note.md `main` 969f8e73 / `v6.1117.1`。

标注:**[用户定]**、**[我的判断]** 沿用设计原标注;本文自己补充的做法标 **[我的判断]**(本文补充)。

总红线(设计 §2 反目标):任何一期都不得让 note.md 不能照常构建和发版;不得在两个仓库各留一份可编辑源码。

---

## 第 0 期:建仓库与文档(本期)

做什么:建 `~/git/sumiwrite`,写设计 §7 的全部文档,不搬代码,不改 note.md(设计 §2 **[用户定]**)。

完成的标志:用户通读并认可规范与交接方案(设计 §8)。自检:`bash docs/check.sh` 输出 `OK`。

---

## 第 1 期:迁内核、服务契约与同步服务

### 前置条件

- **第一步:公开设计与第 0 期计划**。(已完成,2026-11-20)两者在提交 `0c11629f`,已并入 note.md `main` 并公开;本仓库对它们的引用已改为固定到该提交的 blob 链接(`https://github.com/wizlijun/note.md/blob/<提交>/<路径>`)**[我的判断]**(本文补充)。
- 第 0 期完成的标志已达成。
- 第 1 期详细计划已立并获用户认可:[第 1 期详细计划](../plans/2026-11-20-phase1-core-protocol-sync.md)(2026-11-20 认可)。
- sumiwrite 有 Cargo 可拉取的公开远端。仓库公开是设计 §12 **[用户定]**;第 0 期不建远端,所以建远端是第 1 期的第一件事 **[我的判断]**(本文补充)。
- 工具链与 note.md 基线一致:`write-core` 用 `cargo +1.99.0`(`write-core/README.md`);同步服务复用 Wrangler 3.114.17(`write-sync-worker/README.md`、`write-sync-worker/scripts/cloud-admin.py:82`;迁移后为 `sync/scripts/cloud-admin.py`)。
- 同步服务的 `.env` 迁出方式、账号 ID 的新存放位置已在详细计划里定下([01-inventory.md](01-inventory.md) §6)。

### 步骤

1. **提取并保留历史**:在 note.md 的一份**全新克隆**上用 `git filter-repo` 按路径提取 `write-core/`、`sumi-protocol/`、`write-sync-worker/`,并改名为 `core/`、`protocol/`、`sync/`,再并入 sumiwrite(设计 §8 **[我的判断]**)。示意(本文补充,以详细计划为准):

   ```bash
   git clone --no-local <note.md 仓库> notemd-extract && cd notemd-extract
   git filter-repo --path write-core/ --path sumi-protocol/ --path write-sync-worker/ \
     --path-rename write-core/:core/ --path-rename sumi-protocol/:protocol/ \
     --path-rename write-sync-worker/:sync/
   # 在 sumiwrite 中:git pull --allow-unrelated-histories <notemd-extract> main
   ```

2. **修模块间的相对路径**:改名后,`sync/scripts/interop.mjs` 读取的 `../../write-core/tests/fixtures/yrs-v1.json` 要改为 `../../core/...`(基线 `write-sync-worker/scripts/interop.mjs:5`);`protocol/Cargo.toml` 里的 `write-core = { path = "../write-core" }`(基线 `sumi-protocol/Cargo.toml:10`)改名后失效,要改为指向 `../core`。其余跨模块路径以详细计划的 `grep` 结果为准:同步服务三个测试文件的夹具导入、插件后台 `sync.rs:1907` 的 `include_str!`(改由内核以 `fixtures` feature 导出常量),见 [01-inventory.md](01-inventory.md) §5.1。
3. **同步服务解开对 note.md 的依赖**,按 [01-inventory.md](01-inventory.md) §5 归为四处:
   - 工具链:不再借用根下 `worker/node_modules` 的 Wrangler 与 `tsc`,连同 `link-toolchain.mjs` 的软链(`package.json:8-12`、`scripts/deploy.sh`、`scripts/cloud-admin.py:14`、`:67`);
   - 根目录 `.env`(`cloud-admin.py:42`):改为 sumiwrite 自己的配置入口,只放凭据引用,不放秘密(设计 §12);
   - `worker/wrangler.toml` 里的账号 ID(`cloud-admin.py:46`);
   - 以 note.md 仓库根为基准的路径假设(`cloud-admin.py:11` 的 `ROOT`、`deploy.sh:12` 的 `../tasks/sumi-sync`)。
   钉死的 Wrangler 3.114.17 与兼容日期 `2024-12-30` 不随迁移改动。
4. **许可**:`core/Cargo.toml` 的 MIT 声明改为 Apache-2.0,`protocol/` 补上 Apache-2.0 声明(设计 §12 **[我的判断]**)。
5. **启用变更记录**:本仓库根目录建 `CHANGELOG.md` 与 `CHANGELOG.zh-CN.md`(设计 §6),格式沿用 note.md 的倒序加“未发布”区 **[我的判断]**(本文补充)。
6. **打 tag**:在 sumiwrite 打 `core-v0.1.0`。`core-vX.Y.Z` 与 `host-contract` 版本是否联动尚未定,见 [03-notemd-contract.md](03-notemd-contract.md) §7 与 [04-known-gaps.md](04-known-gaps.md) §2。
7. **note.md 改依赖并删目录,放在同一个提交里**:
   - 三处 path 依赖改为指向 sumiwrite `core-v0.1.0` 的 git tag 依赖:`src-tauri/Cargo.toml`(L39–40:`write-core`、`sumi-protocol`)、`plugins-src/write/backend/Cargo.toml`(L12–13)、`scripts/sumi/native/Cargo.toml`(L6);
   - 删除 `write-core/`、`sumi-protocol/`、`write-sync-worker/`;
   - 同步更新写死这些路径的脚本与测试:`scripts/sumi/native-release.py:11` 的 `SOURCE_DIRS`、`scripts/sumi/test_native_release.py:42`,以及基线上 `grep` 命中的 `scripts/sumi/{verify-release.py,build.mjs,run-native.mjs,native/src/main.rs,README.md,verify-release.md}`(逐个在详细计划里判定);
   - 另有详细计划规划时发现的:`verify-release.py:44`、`build.mjs:19`、`run-native.mjs:12`/`:14-15`(构建目录在 `write-core/target`;`--offline` 遇 git 依赖须先 `cargo fetch`)、note.md `.gitignore:71`/`:73`,见 [01-inventory.md](01-inventory.md) §5.1;
   - 本地联调用 `[patch]` 指向本地目录(设计 §5.3)。
8. **旧文档指引**:旧文档集每份文首加一行“现行规范已迁至 sumiwrite”的指引。这是设计中对 note.md 文档的唯一改动(设计 §7.2 **[我的判断]**)。单独成一个提交。
9. note.md 一侧的改动继续受其 `CLAUDE.md` 约束(CHANGELOG 门禁、OKF 写入规矩,设计 §3)。

### 验证

sumiwrite 侧(命令抄自各模块 README,路径按改名后写):

```bash
cargo +1.99.0 test   --manifest-path core/Cargo.toml
cargo +1.99.0 clippy --manifest-path core/Cargo.toml --all-targets -- -D warnings
cd sync && npm ci && npm test && npm run check
```

- `protocol/` 没有 README,没有成文的测试命令。暂按 `core/` 的写法跑 `cargo +1.99.0 test` 与 `clippy --all-targets -- -D warnings` **[我的判断]**(本文补充),并在第 1 期补 README。
- 同步服务的测试不再依赖 note.md 的 `worker/` 目录;互操作夹具检查 `sync/scripts/interop.mjs` 能读到 `core/tests/fixtures/yrs-v1.json`。
- 线格式红线不变:Yrs 仍固定 0.24.0,对 Yjs 13.6.33 的互操作测试通过(设计 §3)。

note.md 侧:

- 宿主与插件照常构建(按 note.md 现有构建与 `scripts/release-plugins.sh` 的 `release_sumi()` 流程,不发布)。
- 现有 Sumi 测试全过:宿主 `src-tauri/src/sumi/` 的测试(含 `lifecycle_tests.rs`、`recovery_tests.rs`)、插件后台 `plugins-src/write/backend` 的测试、插件前端 `plugins-src/write` 的 `npm test` 与 `npm run check`(`package.json`)、`scripts/sumi/test_native_release.py`。具体命令与过滤条件在详细计划里写明 **[我的判断]**(本文补充)。
- 仓库内不再有 `write-core/`、`sumi-protocol/`、`write-sync-worker/` 的副本。

### 回退

- note.md:revert 第 7 步那一个提交即可恢复。目录删除与依赖切换在同一提交,所以 revert 后目录和 path 依赖一起回来。第 8 步的文档指引是另一个提交,按需单独 revert。
- sumiwrite:已迁入的历史和 `core-v0.1.0` tag 保留不动。note.md 回退后不再引用它,两边不会各自演进——在重新切换前,sumiwrite 侧的 `core/`、`protocol/`、`sync/` 不接受改动 **[我的判断]**(本文补充)。

---

## 第 2 期:迁插件壳、资源与插件侧脚本

状态:sumiwrite 侧已完成(tag `notemd-plugin-v0.1.16`,[`build-artifact.sh`](https://github.com/wizlijun/sumiwrite/blob/notemd-plugin-v0.1.16/apps/notemd-plugin/scripts/build-artifact.sh));note.md 侧 `[未定]`:已快进合并到本地 note.md `main`(9288b33d),待推送。

### 前置条件

- 第 1 期完成,note.md 已按 tag 引用 `core/` 与 `protocol/`。
- 第 2 期详细计划已立并获认可([本文](../plans/2026-11-20-phase2-plugin-shell.md)),其中定下:
  - `plugins-src/shared/shortcuts.ts`:sumiwrite 保留自己的一份,note.md 的原件不动;
  - `src/lib/sumi/i18n.ts`:两仓库各留一份,分开演进;
  - `scripts/sumi/verify-release.py`:不拆,留在 note.md;
  - sumiwrite 交给 note.md 签名的构建物与校验清单格式:见 [03-notemd-contract.md](03-notemd-contract.md) §5,由[计划](../plans/2026-11-20-phase2-plugin-shell.md)任务 5 定。
- 确认 `notemd-plugin-sdk` 经 git tag 引用时,它对 `plugin-protocol/` 的 path 依赖能一并拉取(`notemd-plugin-sdk/Cargo.toml:8`)。

### 步骤

1. 迁 `plugins-src/write/`(插件壳、`backend/`、`resources/` 中的字体目录、音效、许可与来源文件)到 `apps/notemd-plugin/`(设计 §6),做法同第 1 期,保留历史。
2. 迁 [01-inventory.md](01-inventory.md) §3 判定归 sumiwrite 的 `scripts/sumi/` 条目,以及 `src/lib/sumi/i18n.ts`。
3. 插件壳按 tag 引用 note.md 的 `notemd-plugin-sdk`(设计 §5.3)。
4. 按前置条件里的结论处理 `shortcuts.ts`。
5. note.md 的 `scripts/release-plugins.sh` 中 `release_sumi()` 改为从 sumiwrite 的固定 tag 取构建物,签名、公证、上架仍在 note.md(设计 §5.3 **[我的判断]**)。`release_sumi()` 按 [03-notemd-contract.md](03-notemd-contract.md) §5 的交付格式消费构建物。
6. note.md 删除已迁目录,与第 5 步放在同一个提交。
7. 迁移不改行为,本期不发新插件包;之后第一次真实改动走新流程发版,契约版本变化时两边配套发版([03-notemd-contract.md](03-notemd-contract.md) §4)。

### 验证

- 从 sumiwrite 构建的插件包,在正式宿主上安装并跑通现有验收清单(设计 §8)。验收脚本以 [01-inventory.md](01-inventory.md) §3 的判定为准。
- 插件前端 `npm test`、`npm run check`,插件后台测试,在 sumiwrite 内通过。
- 包内容与 manifest 的 `engines.notemd` 下限与迁移前一致。

### 回退

- note.md:revert 第 5–6 步那一个提交,`release_sumi()` 回到从树内构建。
- 插件市场:已上架的版本不撤回。若某个从 sumiwrite 出的包有问题,用 note.md 回退后的流程再发一个更高版本号的包覆盖 **[我的判断]**(本文补充)。

---

## 第 3 期:会话与同步协调下沉到 `session/`

### 前置条件

- 第 2 期完成。
- 第 3 期详细计划已立并获认可,定下切分方式(设计 §10.2 **[我的判断]**)。依据 [01-inventory.md](01-inventory.md) §2 的逐文件判定,并解决其中留给本期的问题:
  - `journal.rs` 依赖 `mod.rs` 里的类型(`CommitReceipt`、`LocalEdit`、`Request`);`durability.rs` 依赖 `service::Backend`,都要先抽接口;
  - `external.rs`(vault 投影相关)是否进 `session/`;
  - owner 交接时要不要真正转移上下文(见 [../spec/platform/notemd-desktop.md](../spec/platform/notemd-desktop.md) §3.2)。
- 下沉后的部署形态:同一个 `session/` 要同时适配桌面跨进程和 iOS 单进程([ADR 0012](../adr/0012-shared-session-module.md))。

### 步骤

1. 在 sumiwrite 新建 `session/`。
2. 把宿主 `src-tauri/src/sumi/` 中与 Tauri 无关的部分(单一编辑 owner、组字防护、输入日志、恢复、凭据逻辑),以及插件后台的 `sync.rs`、`coordinator.rs`、`durability.rs` 中与宿主无关的部分,下沉到 `session/`。
3. 宿主只留薄适配(命令注册、窗口、系统钥匙串与原生桥对接,设计 §5.2);宿主和插件后台改为调用 `session/`。
4. 约束:`session/` 不依赖 Tauri,也不依赖 `notemd-plugin-sdk`(设计 §8)。证书校验方式做成可替换的,为 iOS 换掉 `rustls-tls-native-roots` 留位置([ADR 0010](../adr/0010-ios-uikit-textkit2-uniffi.md))**[我的判断]**(本文补充)。
5. 更新读取这些源文件路径的脚本:`scripts/sumi/test-linux-credentials.sh`、`test_fullscreen_appearance.py`([01-inventory.md](01-inventory.md))。

### 验证

- 桌面行为不变。
- `src-tauri/src/sumi/lifecycle_tests.rs`、`recovery_tests.rs` 及插件后台测试全过(设计 §8)。
- `cargo tree` 检查 `session/` 的依赖里没有 `tauri*` 与 `notemd-plugin-sdk` **[我的判断]**(本文补充)。

### 回退

- 宿主与插件后台改为调用 `session/` 的提交各自可 revert,回到原实现;`session/` 留在 sumiwrite 但无人引用。
- 回退期间不在 `session/` 与原位置同时改同一逻辑,避免两份源码分叉(设计 §2 反目标)。

---

## 第 4 期:iOS/iPadOS 应用

前置条件见 [../spec/platform/ios.md](../spec/platform/ios.md) §6(第 3 期完成、发行事务)。里程碑 M0–M5 及各自验证见 [ios.md §4.1](../spec/platform/ios.md):M0 内核过 FFI 排在最前,不成立就回到技术栈重选(设计 §10.3)。

完成的标志:TestFlight 版可与桌面跨设备续写(设计 §8)。iOS 第一阶段自用,不公开发行(设计 §2 **[用户定]**)。

---

## 第 5 期:评估桌面独立应用

桌面独立应用只写进路线图,iOS 上线后评估(设计 §2 **[用户定]**)。满足下面**任意两条**就启动(设计 §9):

1. 过去一个季度里,因为原生编辑桥改动而被迫配套发宿主的次数,明显多于宿主自身需要的发版。
2. iOS 版证明内核加原生界面的组合可以脱离宿主运行,且维护成本可接受。
3. 出现不使用 note.md 但想用玄霜写作的桌面用户需求。

独立时,原生编辑桥随之迁入 sumiwrite,note.md 改为只识别和阅读 `.writing.md`。第 1 条“明显多于”没有量化门槛,见 [../spec/platform/later.md](../spec/platform/later.md) §4.1。
