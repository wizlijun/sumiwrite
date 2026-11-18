# 玄霜写作(Sumi Write)

玄霜写作是一个沉浸式写作产品:把写作做成一张“纸页”——只管写、自动存、跨设备续写,界面退到字的后面。它的内核、同步服务和呈现规则都归本仓库;note.md 是它目前的桌面宿主。

## 仓库地图

本仓库目前只有文档,代码目录按期迁入(见下文“当前期次”),不放空壳。

- `LICENSE`:Apache-2.0。
- `AGENTS.md`:给 agent 的规程入口。
- `docs/handoff/`:交接方案(总览、清单、迁移计划、与 note.md 的契约、已知缺口)。
- `docs/spec/`:现行规范,按主题组织;`MAPPING.md` 记录旧规范到新规范的去向。
- `docs/adr/`:技术选型记录。
- `docs/check.sh`:文档自检脚本,提交前运行 `bash docs/check.sh`。

## 当前期次

第 0 期:只交接文档,不搬代码,不改 note.md 的构建与发版。后续各期的步骤、前置条件、验证与回退见 [迁移计划](docs/handoff/02-migration-plan.md)。

## 阅读顺序

1. [`docs/handoff/00-overview.md`](docs/handoff/00-overview.md):交接总览。
2. [`docs/spec/00-product.md`](docs/spec/00-product.md):产品是什么、不是什么。
3. [`docs/adr/`](docs/adr/):为什么这样选型。
