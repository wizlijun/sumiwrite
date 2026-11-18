# 0009 纸页存储与 vault 投影分层

类型:新
状态:已决定(第 0 期);规范按此分层书写,代码层面的切分到相应期次落实。
记录日期:2026-11-18;出处为抽离设计 §5.4。归属标注沿用设计原文。

## 背景

旧规范把存储路径直接写成 vault 内的文件:`inbox/writings/YYYY-MM-DD-NN.writing.md` 加同目录 sidecar(主规范 §0、§1、§7)。这对 note.md 插件成立,对 iOS 不成立——iOS 没有 vault。若沿用旧写法,iOS 要么假装有一个 vault,要么规范里的“存储”一词在两个平台上含义不同。同时,事实上的本机事实源本来就是 SQLite,不是文件(见 [0003](0003-portable-files-and-sqlite-history.md))。

## 决定

规范拆成两层(设计 §5.4):

- **纸页存储**:各端都有。内核的 SQLite 存完整 CRDT 历史,是本机事实源。iOS 放在应用沙盒里。
- **vault 投影**:只有桌面插件做。把已提交状态投影成 `.writing.md` 与 sidecar,并处理外部修改的三方合并。路径与 `type: Writing Page` 约定属于与 note.md 的契约,遵守 note.md 的 OKF 写入规矩(设计 §5.3 第 3 部分)。
- **iOS 没有 vault,只有纸页存储,外加“导出为 Markdown”的分享入口** **[我的判断]**。

两层的分界写进规范结构:纸页模型与存储在 [01-pages-and-storage.md](../spec/01-pages-and-storage.md),投影在 [platform/notemd-desktop.md](../spec/platform/notemd-desktop.md)。

设计对“拆成两层”本身未标注 [用户定] 或 [我的判断];只有 iOS 一句标为 [我的判断]。

## 放弃的方案

设计没有为这一条列比较表。被替换的是旧规范的写法:

- **存储即 vault 文件**:旧规范以 vault 路径描述存储,把投影和存储写在一起(主规范 §1、§7)。
- **移动端在应用私有 Documents 内保存 Markdown 快照**:旧规范对移动端的设想(主规范 §7“移动端对应为应用私有 Documents 内的 Markdown 快照与持久状态”)。设计 §5.4 改为 iOS 只有纸页存储加导出;设计没有写明放弃该设想的理由,此处只记录两者不同。

## 后果

得到的:

- 桌面与 iOS 共享同一个“纸页存储”定义,规范不必为 iOS 写例外。
- vault 投影的全部复杂度(文件对原子性、外部修改、别名与孤儿、vault 传输冲突)被限定在桌面插件里。

付出的:

- **iOS 上没有用户可见的文件。** 纸页只存在于应用沙盒的 SQLite 和同步服务里;删除应用而尚未同步的纸页就没了。用户能自己拿走的只有导出的 Markdown。
- **导出会丢行时间。** 旧规范规定普通 Markdown 导出只含正文,不含内部头部与行时间;保留行时间要导出 MD + sidecar 归档(主规范 §5.2.3)。iOS 的导出是否提供后者,`[未定]`。
- **代码层面还没分开。** 投影与三方导入现在就在 `write-core`(`projection.rs`、`import.rs`),而不是在桌面插件壳里;iOS 会链接到它不用的代码。是否把投影移出内核、在哪一期移,`[未定]`。
- 桌面上“纸页存储”和“vault 文件”仍是两份需要保持一致的东西,三方合并的规则继续由桌面单独维护和测试。

## 来源

- 抽离设计 §5.3、§5.4:note.md 源仓库 `docs/superpowers/specs/2026-11-18-sumiwrite-extraction-design.md`(尚未提交到任何 tag)
- 旧规范的存储路径、移动端设想与导出规则(§0、§1、§5.2.3、§7):https://github.com/wizlijun/note.md/blob/v6.1117.1/docs/superpowers/specs/2026-11-07-immersive-write-design.md
- 投影与导入现位于内核:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/projection.rs 、https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/src/import.rs
- SQLite 是事实源:https://github.com/wizlijun/note.md/blob/v6.1117.1/write-core/README.md
