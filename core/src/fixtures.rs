//! 互操作夹具,原样嵌入 `tests/fixtures/` 下的 JSON。
//!
//! 下游以 git 依赖引用内核时,内核源码位于 Cargo 的检出目录,按相对路径读取夹具会失效;
//! 为避免在两个仓库各存一份,由内核在 `fixtures` feature 后导出。

/// Yrs 线格式 v1 夹具:基础状态、增量、完整状态与期望快照。
pub const YRS_V1: &str = include_str!("../tests/fixtures/yrs-v1.json");
/// 依赖缺失的无效增量:含基础状态、依赖、无效增量与期望的最后有效状态。
pub const PENDING_INVALID_V1: &str = include_str!("../tests/fixtures/pending-invalid-v1.json");
/// 只有完整状态与期望快照的夹具;同步服务用它验证 `recover` 路径。
pub const FORK_V1: &str = include_str!("../tests/fixtures/fork-v1.json");
