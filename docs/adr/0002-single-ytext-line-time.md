# 0002 正文是单个 Y.Text,行时间随字符贡献保留

类型:补记
状态:已采纳;现行于基线 v6.1117.1 的 `write-core`。
记录日期:2026-11-18;决定出处为主规范 §5.2.2、§5.3 与 `write-core` 线格式文档。

## 背景

用户确认的需求是:每个由明确 LF 划分的逻辑行记录“首次书写”和“最后修改”时间;屏幕折行不产生新行记录;首版不做逐键回放(主规范 §0、§1)。难点在并发:A 在一台设备上把一行拆成两行,B 同时离线修改了右半段,合并后 B 的时间必须落到最终的右行上,而不是只更新旧行 ID 的摘要(主规范 §5.3)。行号会漂移,行对象会被并发拆合打散,所以“行”的身份和时间都不能依赖位置。

## 决定

- **正文是一个 Y.Text(共享根 `body`)**,只存规范 LF Markdown,不存呈现样式;另有 `page`(Y.Map,身份)与 `timing`(Y.Map,时间事件)两个根(`WIRE.md`)。
- **行身份挂在换行上**:首行 ID 存于 `page.root_line_id`;此后每个 LF 携带非显示属性 `next_line_id`,即**其后一行**的稳定 UUID;普通字符显式清除该属性,防止属性继承。这些属性不进入可见 Markdown,投影时导出到 sidecar 行表。
- **时间随字符贡献保留**:`timing` 中每个 UUID 键对应一条不可变 JSON 事件 `[1, at_ms, source, spans]`。span 用 Yrs StickyIndex V1 相对锚点和 `[client, start_clock, end_clock)` 字符来源区间定位,不用行号或当前偏移。归约器按当前逻辑行汇总存活贡献:first 取最小、last 取最大。
- 正文、LF 身份与时间事件在**同一 Yrs 事务**中提交,走同一条同步协议;sidecar 只是归约结果的物化快照,不是第二个合并真相。
- 新空行没有 first;清空已有行保留其历史;Undo 以新 ID 重新插入文字,并发出携带原行来源的新事件。`time_source` 取值 `device` / `import` / `mixed` / `unknown`。

## 放弃的方案

旧文档记录了两个被明确否决的方案:

- **每行内嵌时间**(在 Markdown 行末或独占行写 `<!-- … -->` 注释)。否决理由:对任意 Markdown 不透明——闭合代码围栏后只能有空白、两空格/反斜杠硬换行会失效、注释行替代空行会改变段落与列表、代码块内注释会显示;若坚持,就要定义专用行编码并在任何解析前剥离,外部工具仍不能保证等价渲染(主规范 §5.2.1)。更根本的是,把时间作为正文字符协同,每次更新时间都会额外产生删除/插入,污染选区和 source map,并发时还会生成失效注释(主规范 §5.2.2)。
- **后写覆盖的行对象**(每行一个 `{first,last}` 普通 LWW 对象)。否决理由:并发拆行、合行时,按行 ID 覆盖会把另一台设备的修改时间记到错误的行或直接丢掉;规范明确“跨设备时间不以每行 `{first,last}` 的普通 LWW 对象合并”(主规范 §5.3;内核 README“instead of trusting line numbers or last-writer-wins row objects”)。

同时否决的还有按屏幕行号匹配(主规范 §5.3)。

## 后果

得到的:

- 并发拆行、合行、跨行删除、空行、Undo/Redo 下,时间都跟着真实存活的文字走;对应回归在 `write-core/tests/` 覆盖。
- Markdown 正文保持干净,外部编辑器看到的就是用户写的字。

付出的:

- **时间是结构化事务数据,存储与同步开销不会因此消失**,尤其并发拆合行的来源记录;规范明确没有性能实测就不给延迟百分比(主规范 §5.2.2)。
- 事件不可变、`timing` 不允许删除或覆盖,历史只增不减,长期增长靠容量限额兜底,超限保留本机草稿并报错(主规范 §5.3)。
- 恢复状态仍可能包含被删正文和编辑历史:虽然界面不提供逐键回放,**不能宣称底层不存逐键记录**。
- 理解与实现门槛高:任何新客户端(iOS、ESP32 代理)都必须完整复用这套归约逻辑,不能自写简化版——这是 [0012](0012-shared-session-module.md) 坚持复用 Rust 的理由之一。
- 墙钟可能错误;`source` 标签不是校时证明。时间只表达“设备当时认为的时刻”,不证明创作时间真实性。

## 来源

- 主规范 §0、§1、§5.1、§5.2.1、§5.2.2、§5.3:https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md
- 线格式(共享根、事件形状、归约):https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/WIRE.md
- 行时间语义:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md
- `next_line_id` 写入与清除:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/document.rs
- 行时间回归:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/tests/document.rs
