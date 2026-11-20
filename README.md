# 玄霜写作(Sumi Write)

玄霜写作是一个沉浸式写作产品:把写作做成一张“纸页”——只管写、自动存、跨设备续写,界面退到字的后面。它的内核、同步服务和呈现规则都归本仓库;note.md 是它目前的桌面宿主。

## 仓库地图

代码目录按期迁入(见下文“当前期次”),不放空壳。改了哪个模块,提交前跑该模块的测试命令。

- `core/`:编辑内核(Rust,Yrs),说明见 [`core/README.md`](core/README.md)。测试:`cargo +1.99.0 test --manifest-path core/Cargo.toml --all-features`,`cargo +1.99.0 clippy --manifest-path core/Cargo.toml --all-targets --all-features -- -D warnings`。
- `protocol/`:宿主与插件后台之间的服务契约类型,依赖 `core/`,说明见 [`protocol/README.md`](protocol/README.md)。测试:`cargo +1.99.0 test --manifest-path protocol/Cargo.toml`,`cargo +1.99.0 clippy --manifest-path protocol/Cargo.toml --all-targets -- -D warnings`。
- `sync/`:同步服务(Cloudflare Worker),自带固定版本的工具链,说明见 [`sync/README.md`](sync/README.md)。测试见 [`sync/README.md`](sync/README.md)「Verification」段。
- `apps/notemd-plugin/`:桌面插件壳(`notemd.sumi`),前端、Rust 后台、资源与插件侧校验脚本,说明见 [`apps/notemd-plugin/README.md`](apps/notemd-plugin/README.md)。测试见 [`apps/notemd-plugin/README.md`](apps/notemd-plugin/README.md)「Verification」段。
- `CHANGELOG.md` / `CHANGELOG.zh-CN.md`:面向用户的变更记录,倒序,顶部是“未发布”区。
- `LICENSE`:Apache-2.0,覆盖全部模块。
- `AGENTS.md`:给 agent 的规程入口。
- `docs/handoff/`:交接方案(总览、清单、迁移计划、与 note.md 的契约、已知缺口)。
- `docs/spec/`:现行规范,按主题组织;`MAPPING.md` 记录旧规范到新规范的去向。
- `docs/adr/`:技术选型记录。
- `docs/check.sh`:文档自检脚本,提交前运行 `bash docs/check.sh`。

## 当前期次

第 1 期已完成:`core/`、`protocol/`、`sync/` 已连同历史迁入,三个模块的测试在本仓库全部通过;本仓库已推送 tag `core-v0.1.0`,note.md 已改为按该 tag 引用并删除树内副本(note.md [`c2889dd4`](https://github.com/wizlijun/note.md/commit/c2889dd4f6c60fb43d8f58be78ebb09f561b14a0))。下一步是第 2 期,开工前要先立详细计划。第 0 期只交接文档。后续各期的步骤、前置条件、验证与回退见 [迁移计划](docs/handoff/02-migration-plan.md)。

## 阅读顺序

1. [`docs/handoff/00-overview.md`](docs/handoff/00-overview.md):交接总览。
2. [`docs/spec/00-product.md`](docs/spec/00-product.md):产品是什么、不是什么。
3. [`docs/handoff/01-inventory.md`](docs/handoff/01-inventory.md)、[`docs/handoff/03-notemd-contract.md`](docs/handoff/03-notemd-contract.md):东西在哪、与 note.md 怎么连。
4. [`docs/handoff/02-migration-plan.md`](docs/handoff/02-migration-plan.md)、[`docs/handoff/04-known-gaps.md`](docs/handoff/04-known-gaps.md):怎么搬、还缺什么。
5. [`docs/adr/`](docs/adr/):为什么这样选型;旧规范的去向见 [`docs/spec/MAPPING.md`](docs/spec/MAPPING.md)。
