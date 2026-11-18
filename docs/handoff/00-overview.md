# 00 交接总览

基线:note.md `main` 969f8e73,宿主 tag `v6.1117.1`,插件 `notemd.sumi` 0.1.16。权威设计:源仓库 `docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md`(下称“设计”)。

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

## 当前状态(第 0 期)

- **已完成**:本仓库只有文档——交接方案(`docs/handoff/`)、按主题重写的现行规范(`docs/spec/`,含旧文档去向表 [MAPPING.md](../spec/MAPPING.md))、12 条技术选型记录(`docs/adr/`)、`README.md`、`AGENTS.md`、`LICENSE`(Apache-2.0)和自检脚本 `docs/check.sh`。
- **未动**:代码全部仍在 note.md,本期对 note.md 零改动,构建与发版照旧(设计 §2 **[用户定]**)。代码目录到对应期次再建,不放空壳(设计 §6 **[我的判断]**)。
- **未建**:本仓库还没有远端,也没有 tag。

## 五期路线

| 期 | 做什么 | 完成的标志 |
|---|---|---|
| 1 | 迁 `core/`、`protocol/`、`sync/`,保留历史;note.md 改为按 tag 引用 | 三个模块测试全过;note.md 照常构建,Sumi 测试全过 |
| 2 | 迁插件壳、资源、插件侧脚本;sumiwrite 出包、note.md 上架 | 从 sumiwrite 构建的包在正式宿主上通过现有验收 |
| 3 | 会话与同步协调下沉到 `session/` | 桌面行为不变,会话、恢复、同步测试全过 |
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
