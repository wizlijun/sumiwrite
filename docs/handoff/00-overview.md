# 00 交接总览

基线:note.md `main` 969f8e73,宿主 tag `v6.1117.1`,插件 `notemd.sumi` 0.1.16。权威设计:note.md 仓库 [`docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md`](https://github.com/wizlijun/note.md/blob/0c11629f976226c688d186b13d4812da31073dc2/docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md)(下称“设计”)。设计与第 0 期计划 [`docs/superpowers/plans/2026-11-18-sumiwrite-phase0-docs.md`](https://github.com/wizlijun/note.md/blob/0c11629f976226c688d186b13d4812da31073dc2/docs/superpowers/plans/2026-11-18-sumiwrite-phase0-docs.md) 都已在 note.md `main` 公开,上面是固定到提交 `0c11629f` 的链接。

## 为什么拆

玄霜写作(Sumi Write)现在是 note.md 仓库里的一个插件,但它已经有自己的内核、协议、同步服务和品牌,下一步还要做 iOS/iPadOS 原生版。继续放在 note.md 里,两个产品的边界、发版节奏和文档会混在一起(设计 §1)。

## 拆成什么样

一句话:**sumiwrite 拥有“纸页”这个产品:写、存、同步、呈现规则。note.md 是它的一个宿主:提供原生编辑面、vault 和插件运行时。**(设计 §5.1)

```
            sumiwrite(本仓库)                         note.md(宿主)
  ┌─────────────────────────────────────┐     ┌──────────────────────────────┐
  │ core/      编辑内核(Rust, Yrs)      │◄────┤ src-tauri 宿主               │
  │ protocol/  宿主↔插件后台服务契约     │ tag │  ├ 实时编辑会话的 Tauri 适配 │
  │ session/   会话与同步协调(第 3 期) │     │  └ 原生编辑桥(不迁)         │
  │ sync/      同步服务(CF Worker)     │     │ notemd-plugin-sdk            │
  │ apps/notemd-plugin/ 桌面插件壳      ├────►│ 插件市场、签名与发版         │
  │ apps/ios/  iOS/iPadOS 应用(第 4 期)│ tag │ 历史发布证据                 │
  └─────────────────────────────────────┘     └──────────────────────────────┘
          两个方向都按固定 tag 引用,crate 层面不成环(设计 §5.3)
```

逐项归属见 [01-inventory.md](01-inventory.md);两仓之间的耦合面见 [03-notemd-contract.md](03-notemd-contract.md)(`host-contract v1`)。

## 当前状态(第 2 期 sumiwrite 侧已完成,note.md 侧已本地合并、待推送)

- **第 0 期已完成**:交接方案(`docs/handoff/`)、按主题重写的现行规范(`docs/spec/`,含旧文档去向表 [MAPPING.md](../spec/MAPPING.md))、12 条技术选型记录(`docs/adr/`)、`README.md`、`AGENTS.md`、`LICENSE`(Apache-2.0)和自检脚本 `docs/check.sh`。
- **第 1 期已完成(本仓库内)**:`core/`、`protocol/`、`sync/` 用 git-filter-repo 从 note.md `3c710c9e` 提取并保留历史并入;模块间相对路径已修,内核夹具在 `fixtures` feature 后导出;同步服务自带固定工具链,部署脚本凭据只从环境变量或钥匙串读;两个 crate 改为 Apache-2.0;有了 `CHANGELOG.md` / `CHANGELOG.zh-CN.md`。三个模块的测试在本仓库全部通过,线格式不变。
- **第 1 期已完成(note.md 侧)**:本仓库远端为 `https://github.com/wizlijun/sumiwrite`,已推送 `main` 与 tag `core-v0.1.0`(指向 `8f28b98a`)。note.md 的三处依赖改为按该 tag 引用,并删除 `write-core/`、`sumi-protocol/`、`write-sync-worker/`(note.md [`c2889dd4`](https://github.com/wizlijun/note.md/commit/c2889dd4f6c60fb43d8f58be78ebb09f561b14a0));旧文档文首已加指引(note.md [`9286d89d`](https://github.com/wizlijun/note.md/commit/9286d89dd52945dea5f71da745dcca225c73cabf))。两个提交都已在 note.md `origin/main` 上。
- **第 2 期(sumiwrite 侧已完成)**:插件壳、资源与插件侧脚本连同历史迁入 `apps/notemd-plugin/`,打了 tag `notemd-plugin-v0.1.16`;`scripts/build-artifact.sh` 产出未签名构建物与校验清单([`build-artifact.sh`](https://github.com/wizlijun/sumiwrite/blob/notemd-plugin-v0.1.16/apps/notemd-plugin/scripts/build-artifact.sh))。note.md 侧(改为从 sumiwrite 取构建物、删除树内插件、两个旧文件加指引)已快进合并到本地 note.md `main`(9288b33d、a7027f68、c7c1df89),`[未定]`:待推送。
- **下一步**:用户决定 note.md 分支的合并与推送;之后第 3 期(会话与同步协调下沉到 `session/`)先立详细计划。

## 五期路线

| 期 | 做什么 | 完成的标志 |
|---|---|---|
| 1 | 迁 `core/`、`protocol/`、`sync/`,保留历史;note.md 改为按 tag 引用 | 三个模块测试全过;note.md 照常构建,Sumi 测试全过 |
| 2 | 迁插件壳、资源、插件侧脚本;sumiwrite 出包、note.md 上架 | 从 sumiwrite 构建的包在正式宿主上通过现有验收 |
| 3 | 会话与同步协调下沉到 `session/` | 桌面行为不变,会话、恢复、同步测试全过;`session/` 不依赖 Tauri 和插件 SDK |
| 4 | iOS/iPadOS 应用 | TestFlight 版可与桌面跨设备续写 |
| 5 | 评估桌面独立应用 | 按设计 §9 给出结论 |

各期的前置条件、步骤、验证与回退见 [02-migration-plan.md](02-migration-plan.md)。已知缺口与未决项见 [04-known-gaps.md](04-known-gaps.md)。

## 阅读顺序

1. 本文。
2. [../spec/00-product.md](../spec/00-product.md):产品是什么、不是什么、各平台状态。
3. [01-inventory.md](01-inventory.md) → [03-notemd-contract.md](03-notemd-contract.md):东西在哪、两仓怎么连。
4. [02-migration-plan.md](02-migration-plan.md):怎么搬。
5. [04-known-gaps.md](04-known-gaps.md):哪些没做、哪些与旧规范不符。
6. 其余规范按需读(`../spec/01`–`05`、`platform/`),技术选型的理由读 [../adr/](../adr/)。
