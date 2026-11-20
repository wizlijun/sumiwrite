//! sumi-ios-ffi:把共享内核 `write-core` 经 UniFFI 暴露给 Swift。
//! 这里只做类型转换和加锁,不含任何 CRDT、行时间、合并或恢复逻辑(红线:不得在 Swift 里重写)。

use std::sync::{Arc, Mutex, MutexGuard};
use write_core::render::{SourceMap, TextRange};
use write_core::catalog;
use write_core::storage::{self, Store};
use write_core::{Document, Error};

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
    #[error("invalid: {message}")]
    Invalid { message: String },
    #[error("stale revision")]
    StaleRevision,
    #[error("invalid offset")]
    InvalidOffset,
    #[error("capacity")]
    Capacity,
    #[error("storage: {message}")]
    Storage { message: String },
}

type R<T> = Result<T, CoreError>;

/// 内核错误转成页面方法的错误:`Invalid` 保持 `Invalid`。
fn page_err(e: Error) -> CoreError {
    match e {
        Error::StaleRevision => CoreError::StaleRevision,
        Error::InvalidOffset => CoreError::InvalidOffset,
        Error::Capacity => CoreError::Capacity,
        other => CoreError::Invalid { message: other.to_string() },
    }
}

/// 内核错误转成存储方法的错误:`Invalid` 归为 `Storage`。
fn store_err(e: Error) -> CoreError {
    match e {
        Error::StaleRevision => CoreError::StaleRevision,
        Error::InvalidOffset => CoreError::InvalidOffset,
        Error::Capacity => CoreError::Capacity,
        other => CoreError::Storage { message: other.to_string() },
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct LineInfo {
    pub id: String,
    pub text: String,
    pub first_ms: Option<i64>,
    pub last_ms: Option<i64>,
    pub time_source: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PageSnapshot {
    pub page_id: String,
    pub epoch: u32,
    pub revision: u64,
    pub body: String,
    pub root_line_id: String,
    pub lines: Vec<LineInfo>,
}

impl From<write_core::Snapshot> for PageSnapshot {
    fn from(s: write_core::Snapshot) -> Self {
        PageSnapshot {
            page_id: s.page_id,
            epoch: s.epoch,
            revision: s.revision,
            body: s.body,
            root_line_id: s.root_line_id,
            lines: s
                .lines
                .into_iter()
                .map(|l| LineInfo {
                    id: l.id,
                    text: l.text,
                    first_ms: l.first_ms,
                    last_ms: l.last_ms,
                    time_source: l.time_source,
                })
                .collect(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct StyleSpan {
    pub start: u32,
    pub length: u32,
    pub bold: bool,
    pub italic: bool,
    pub strike: bool,
    pub heading: u8,
    pub quote: bool,
    pub link: Option<String>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RenderedText {
    pub revision: u64,
    pub text: String,
    pub spans: Vec<StyleSpan>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct EditCommit {
    pub revision: u64,
    pub update: Vec<u8>,
    pub rendered: RenderedText,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct VisibleRange {
    pub start: u32,
    pub length: u32,
}

fn rendered_of(map: &SourceMap) -> RenderedText {
    RenderedText {
        revision: map.revision,
        text: map.document.text.clone(),
        spans: map
            .document
            .runs
            .iter()
            .map(|r| StyleSpan {
                start: r.range.start,
                length: r.range.length,
                bold: r.bold,
                italic: r.italic,
                strike: r.strike,
                heading: r.heading,
                quote: r.quote,
                link: r.link.clone(),
            })
            .collect(),
    }
}

#[uniffi::export]
pub fn core_version() -> String {
    format!("sumi-ios-ffi {}", env!("CARGO_PKG_VERSION"))
}

#[uniffi::export]
pub fn new_page_id() -> String {
    uuid::Uuid::new_v4().to_string()
}

/// 随机非零的 32 位 Yjs client ID。
fn random_client_id() -> u64 {
    loop {
        let id = uuid::Uuid::new_v4().as_u128() as u32;
        if id != 0 {
            return id as u64;
        }
    }
}

struct PageState {
    doc: Document,
    map: SourceMap,
}

impl PageState {
    fn new(doc: Document) -> Self {
        let map = SourceMap::new(&doc.body(), doc.revision());
        Self { doc, map }
    }
    fn rebuild(&mut self) {
        self.map = SourceMap::new(&self.doc.body(), self.doc.revision());
    }
    fn commit(&mut self, update: Vec<u8>) -> EditCommit {
        self.rebuild();
        EditCommit {
            revision: self.doc.revision(),
            update,
            rendered: rendered_of(&self.map),
        }
    }
}

#[derive(uniffi::Object)]
pub struct CorePage {
    inner: Mutex<PageState>,
}

impl CorePage {
    fn wrap(doc: Document) -> Arc<Self> {
        Arc::new(Self { inner: Mutex::new(PageState::new(doc)) })
    }
    fn lock(&self) -> MutexGuard<'_, PageState> {
        self.inner.lock().unwrap()
    }
    /// 仅供 Rust 测试用,不进 Swift 接口。
    pub fn client_id(&self) -> u64 {
        self.lock().doc.client_id()
    }
}

#[uniffi::export]
impl CorePage {
    /// 只给纸页的创建者用;副本一律走 `load_state` 或 `CoreStore::load_fresh`。
    #[uniffi::constructor]
    pub fn create(page_id: String) -> R<Arc<Self>> {
        Ok(Self::wrap(Document::new(&page_id, 1, random_client_id()).map_err(page_err)?))
    }

    #[uniffi::constructor]
    pub fn load_state(page_id: String, epoch: u32, client_id: u64, state: Vec<u8>) -> R<Arc<Self>> {
        Ok(Self::wrap(Document::load(&page_id, epoch, client_id, &state).map_err(page_err)?))
    }

    pub fn page_id(&self) -> String {
        self.lock().doc.snapshot().map(|s| s.page_id).unwrap_or_default()
    }

    pub fn epoch(&self) -> u32 {
        self.lock().doc.snapshot().map(|s| s.epoch).unwrap_or_default()
    }

    pub fn revision(&self) -> u64 {
        self.lock().doc.revision()
    }

    pub fn body(&self) -> String {
        self.lock().doc.body()
    }

    pub fn rendered(&self) -> RenderedText {
        rendered_of(&self.lock().map)
    }

    pub fn snapshot(&self) -> R<PageSnapshot> {
        Ok(self.lock().doc.snapshot().map_err(page_err)?.into())
    }

    pub fn encode_full(&self) -> Vec<u8> {
        self.lock().doc.encode_full()
    }

    pub fn apply_remote(&self, update: Vec<u8>) -> R<()> {
        let mut s = self.lock();
        let result = s.doc.apply_remote(&update).map_err(page_err);
        s.rebuild();
        result
    }

    /// 相对 `revision` 的可见 UTF-16 区间替换;键入的 Markdown 会被转义。
    pub fn apply_edit(&self, revision: u64, start: u32, length: u32, replacement: String, at_ms: i64) -> R<EditCommit> {
        let mut s = self.lock();
        if revision != s.map.revision {
            return Err(CoreError::StaleRevision);
        }
        let range = TextRange { start, length };
        let PageState { doc, map } = &mut *s;
        let update = map.apply_edit(doc, &range, &replacement, at_ms).map_err(page_err)?;
        Ok(s.commit(update))
    }

    /// 把 Markdown 原样插入,不转义。
    pub fn paste_markdown(&self, revision: u64, start: u32, length: u32, markdown: String, at_ms: i64) -> R<EditCommit> {
        let mut s = self.lock();
        if revision != s.map.revision {
            return Err(CoreError::StaleRevision);
        }
        let range = TextRange { start, length };
        let PageState { doc, map } = &mut *s;
        let update = map.apply_markdown_paste(doc, &range, &markdown, at_ms).map_err(page_err)?;
        Ok(s.commit(update))
    }

    pub fn undo(&self, at_ms: i64) -> R<Option<EditCommit>> {
        let mut s = self.lock();
        let update = s.doc.undo(at_ms).map_err(page_err)?;
        Ok(history_commit(&mut s, update))
    }

    pub fn redo(&self, at_ms: i64) -> R<Option<EditCommit>> {
        let mut s = self.lock();
        let update = s.doc.redo(at_ms).map_err(page_err)?;
        Ok(history_commit(&mut s, update))
    }

    pub fn can_undo(&self) -> bool {
        self.lock().doc.can_undo()
    }

    pub fn can_redo(&self) -> bool {
        self.lock().doc.can_redo()
    }

    pub fn anchor_selection(&self, revision: u64, start: u32, length: u32) -> R<Vec<u8>> {
        let s = self.lock();
        if revision != s.map.revision {
            return Err(CoreError::StaleRevision);
        }
        let anchor = s
            .map
            .anchor_selection(&s.doc, &TextRange { start, length })
            .map_err(page_err)?;
        s.doc.serialize_selection(&anchor).map_err(page_err)
    }

    pub fn resolve_selection(&self, encoded: Vec<u8>) -> R<VisibleRange> {
        let s = self.lock();
        let anchor = s.doc.deserialize_selection(&encoded).map_err(page_err)?;
        let r = s.map.resolve_selection(&s.doc, &anchor).map_err(page_err)?;
        Ok(VisibleRange { start: r.start, length: r.length })
    }
}

/// 内核在没有可撤销/重做的内容时返回 `[0, 0]`。
fn history_commit(s: &mut PageState, update: Vec<u8>) -> Option<EditCommit> {
    if update == [0, 0] {
        None
    } else {
        Some(s.commit(update))
    }
}

/// 纸页目录里的一项,供概览和翻页用。
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PageInfo {
    pub id: String,
    pub deleted: bool,
    /// 首个非空白可见行,去首尾空白,最多 40 个字符。
    pub summary: String,
    /// 各行 `last_ms` 的最大值;空页为 `None`。
    pub modified_ms: Option<i64>,
}

fn sql_err(e: impl std::fmt::Display) -> Error {
    Error::Invalid(e.to_string())
}

#[derive(uniffi::Object)]
pub struct CoreStore {
    inner: Mutex<Store>,
}

#[uniffi::export]
impl CoreStore {
    #[uniffi::constructor]
    pub fn open(path: String) -> R<Arc<Self>> {
        let mut s = Store::open(&path).map_err(store_err)?;
        // 初始化目录,并把目录里没有的旧页(M1 路径落盘的)按 page_id 顺序接到末尾。
        s.transaction(|t| {
            catalog::initialize(t)?;
            let mut st = t.prepare("SELECT page_id FROM documents ORDER BY page_id").map_err(sql_err)?;
            let all = st
                .query_map([], |r| r.get::<_, String>(0))
                .map_err(sql_err)?
                .collect::<Result<Vec<_>, _>>()
                .map_err(sql_err)?;
            let mut last = catalog::list(t)?.last().map(|e| e.id.clone());
            for id in all {
                if catalog::get(t, &id)?.is_none() {
                    catalog::create(t, &id, last.as_deref())?;
                    last = Some(id);
                }
            }
            Ok(())
        })
        .map_err(store_err)?;
        Ok(Arc::new(Self { inner: Mutex::new(s) }))
    }

    /// 按 `page_id` 排序。
    pub fn page_ids(&self) -> R<Vec<String>> {
        let mut s = self.inner.lock().unwrap();
        s.transaction(|t| {
            let mut st = t.prepare("SELECT page_id FROM documents ORDER BY page_id").map_err(|e| Error::Invalid(e.to_string()))?;
            let rows = st
                .query_map([], |r| r.get::<_, String>(0))
                .map_err(|e| Error::Invalid(e.to_string()))?
                .collect::<Result<Vec<_>, _>>()
                .map_err(|e| Error::Invalid(e.to_string()))?;
            Ok(rows)
        })
        .map_err(store_err)
    }

    /// 目录顺序的全部纸页(含已删除)。
    pub fn pages(&self) -> R<Vec<PageInfo>> {
        let mut s = self.inner.lock().unwrap();
        let (entries, present) = s
            .transaction(|t| {
                let entries = catalog::list(t)?;
                let mut st = t.prepare("SELECT page_id FROM documents").map_err(sql_err)?;
                let present = st
                    .query_map([], |r| r.get::<_, String>(0))
                    .map_err(sql_err)?
                    .collect::<Result<std::collections::HashSet<_>, _>>()
                    .map_err(sql_err)?;
                Ok((entries, present))
            })
            .map_err(store_err)?;
        entries
            .into_iter()
            .map(|e| {
                if !present.contains(&e.id) {
                    return Ok(PageInfo { id: e.id, deleted: e.deleted, summary: String::new(), modified_ms: None });
                }
                let doc = s.load(&e.id, random_client_id()).map_err(store_err)?;
                let map = SourceMap::new(&doc.body(), doc.revision());
                let summary = map
                    .document
                    .text
                    .split('\n')
                    .map(str::trim)
                    .find(|l| !l.is_empty())
                    .map(|l| l.chars().take(40).collect::<String>())
                    .unwrap_or_default();
                let modified_ms = doc.snapshot().map_err(store_err)?.lines.iter().filter_map(|l| l.last_ms).max();
                Ok(PageInfo { id: e.id, deleted: e.deleted, summary, modified_ms })
            })
            .collect()
    }

    /// 新建一页并登记目录,同一事务落盘;`after` 为空则挂在目录根下(01 §2.1);要追加到末尾须显式传最后一页的 id。
    pub fn create_page(&self, after: Option<String>, op_id: String) -> R<Arc<CorePage>> {
        let id = new_page_id();
        let doc = Document::new(&id, 1, random_client_id()).map_err(store_err)?;
        let pair = storage::serialize_pair(&doc.snapshot().map_err(store_err)?, None, None).map_err(store_err)?;
        self.inner
            .lock()
            .unwrap()
            .commit_local_with(&doc, &op_id, &doc.encode_full(), &pair, |tx| {
                catalog::create(tx, &id, after.as_deref()).map(|_| ())
            })
            .map_err(store_err)?;
        Ok(CorePage::wrap(doc))
    }

    pub fn set_deleted(&self, page_id: String, deleted: bool) -> R<()> {
        self.inner
            .lock()
            .unwrap()
            .transaction(|t| catalog::set_deleted(t, &page_id, deleted).map(|_| ()))
            .map_err(store_err)
    }

    /// 先随机 client ID 载入,再取 `fresh_client_id()` 重载一次(内核 README「Host integration」第 2 条)。
    pub fn load_fresh(&self, page_id: String) -> R<Arc<CorePage>> {
        let s = self.inner.lock().unwrap();
        let probe = s.load(&page_id, random_client_id()).map_err(store_err)?;
        let fresh = probe.fresh_client_id();
        Ok(CorePage::wrap(s.load(&page_id, fresh).map_err(store_err)?))
    }

    /// 首次落盘:完整状态加可移植文件对。
    pub fn commit_initial(&self, page: Arc<CorePage>, op_id: String) -> R<()> {
        let p = page.lock();
        let pair = storage::serialize_pair(&p.doc.snapshot().map_err(store_err)?, None, None).map_err(store_err)?;
        let update = p.doc.encode_full();
        self.inner
            .lock()
            .unwrap()
            .commit_local_with(&p.doc, &op_id, &update, &pair, |_| Ok(()))
            .map_err(store_err)
    }

    /// 普通输入事务:只追加增量;`revision` 是这次编辑之后的修订。
    pub fn commit_delta(&self, page_id: String, epoch: u32, revision: u64, op_id: String, update: Vec<u8>) -> R<()> {
        self.inner
            .lock()
            .unwrap()
            .commit_local_delta_with(&page_id, epoch, revision, &op_id, &update, |_| Ok(()))
            .map_err(store_err)
    }

    pub fn checkpoint(&self, page: Arc<CorePage>) -> R<()> {
        let p = page.lock();
        let pair = storage::serialize_pair(&p.doc.snapshot().map_err(store_err)?, None, None).map_err(store_err)?;
        self.inner
            .lock()
            .unwrap()
            .checkpoint_with(&p.doc, &pair, |_| Ok(()))
            .map_err(store_err)
    }
}
