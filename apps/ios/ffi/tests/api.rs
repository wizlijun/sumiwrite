use std::sync::Arc;
use sumi_ios_ffi::*;

fn temp_db() -> (tempfile::TempDir, String) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("sumi.sqlite3").to_string_lossy().into_owned();
    (dir, path)
}

#[test]
fn edit_goes_through_source_map() {
    let page = CorePage::create(new_page_id()).unwrap();
    let c = page.apply_edit(0, 0, 0, "a*b".into(), 1).unwrap();
    assert_eq!(page.body(), "a\\*b");
    assert_eq!(page.rendered().text, "a*b");
    assert_eq!(c.revision, 1);
    assert_eq!(c.rendered.text, "a*b");
}

#[test]
fn paste_markdown_renders_heading_and_bold() {
    let page = CorePage::create(new_page_id()).unwrap();
    page.paste_markdown(0, 0, 0, "# 标题\n\n**粗**".into(), 1).unwrap();
    let r = page.rendered();
    assert_eq!(r.text, "标题\n\n粗");
    let h = r.spans.iter().find(|s| s.heading == 1).unwrap();
    assert!(h.start == 0 && h.length >= 2, "heading span must cover 标题: {h:?}");
    let b = r.spans.iter().find(|s| s.bold).unwrap();
    assert!(b.start <= 4 && b.start + b.length >= 5, "bold span must cover 粗: {b:?}");
}

#[test]
fn stale_and_split_offsets_are_typed_errors() {
    let page = CorePage::create(new_page_id()).unwrap();
    page.apply_edit(0, 0, 0, "😀".into(), 1).unwrap();
    assert!(matches!(
        page.apply_edit(0, 0, 0, "x".into(), 2),
        Err(CoreError::StaleRevision)
    ));
    assert!(matches!(
        page.apply_edit(1, 1, 0, "x".into(), 2),
        Err(CoreError::InvalidOffset)
    ));
}

#[test]
fn protected_block_edit_is_rejected_and_map_unchanged() {
    let page = CorePage::create(new_page_id()).unwrap();
    page.paste_markdown(0, 0, 0, "```\ncode\n```".into(), 1).unwrap();
    let (rendered, body, rev) = (page.rendered(), page.body(), page.revision());
    assert!(page.apply_edit(rev, 5, 0, "x".into(), 2).is_err());
    assert_eq!(page.rendered(), rendered);
    assert_eq!(page.body(), body);
    assert_eq!(page.revision(), rev);
}

#[test]
fn undo_redo_return_commits_and_none_when_empty() {
    let page = CorePage::create(new_page_id()).unwrap();
    assert!(page.undo(1).unwrap().is_none());
    assert!(!page.can_undo() && !page.can_redo());
    page.apply_edit(0, 0, 0, "hi".into(), 1).unwrap();
    assert!(page.can_undo() && !page.can_redo());
    let u = page.undo(2).unwrap().unwrap();
    assert_eq!(u.revision, 2);
    assert_eq!(page.body(), "");
    assert!(!page.can_undo() && page.can_redo());
    let r = page.redo(3).unwrap().unwrap();
    assert_eq!(r.revision, 3);
    assert_eq!(page.body(), "hi");
    assert!(page.redo(4).unwrap().is_none());
}

#[test]
fn selection_anchor_round_trips() {
    let page = CorePage::create(new_page_id()).unwrap();
    page.apply_edit(0, 0, 0, "abc😀def".into(), 1).unwrap();
    let rev = page.revision();
    let anchor = page.anchor_selection(rev, 5, 0).unwrap();
    assert_eq!(page.resolve_selection(anchor.clone()).unwrap(), VisibleRange { start: 5, length: 0 });
    page.apply_edit(rev, 0, 0, "x".into(), 2).unwrap();
    assert_eq!(page.resolve_selection(anchor).unwrap(), VisibleRange { start: 6, length: 0 });
}

#[test]
fn store_initial_delta_checkpoint_reopen() {
    let (_dir, path) = temp_db();
    let page = CorePage::create(new_page_id()).unwrap();
    let id = page.page_id();
    let epoch = page.epoch();
    let before;
    {
        let store = CoreStore::open(path.clone()).unwrap();
        store.commit_initial(page.clone(), "op-0".into()).unwrap();
        for (i, t) in ["a", "b"].iter().enumerate() {
            let c = page.apply_edit(page.revision(), i as u32, 0, t.to_string(), 10 + i as i64).unwrap();
            store.commit_delta(id.clone(), epoch, c.revision, format!("op-{}", i + 1), c.update).unwrap();
        }
        store.checkpoint(page.clone()).unwrap();
        let c = page.apply_edit(page.revision(), 2, 0, "c".into(), 20).unwrap();
        store.commit_delta(id.clone(), epoch, c.revision, "op-3".into(), c.update).unwrap();
        before = page.snapshot().unwrap();
    }
    let store = CoreStore::open(path).unwrap();
    let again = store.load_fresh(id.clone()).unwrap();
    assert_eq!(again.snapshot().unwrap(), before);
    assert_eq!(before.body, "abc");
    assert_eq!(store.page_ids().unwrap(), vec![id]);
    assert_ne!(again.client_id(), page.client_id());
}

#[test]
fn checkpoint_with_undelivered_revision_is_stale() {
    let (_dir, path) = temp_db();
    let store = CoreStore::open(path).unwrap();
    let page = CorePage::create(new_page_id()).unwrap();
    store.commit_initial(page.clone(), "op-0".into()).unwrap();
    page.apply_edit(0, 0, 0, "a".into(), 1).unwrap();
    assert!(matches!(store.checkpoint(page), Err(CoreError::StaleRevision)));
}

// ---- 页面目录 ----

fn type_text(store: &CoreStore, page: &Arc<CorePage>, text: &str, at_ms: i64) {
    let len = page.rendered().text.encode_utf16().count() as u32;
    let c = page.apply_edit(page.revision(), len, 0, text.into(), at_ms).unwrap();
    store
        .commit_delta(page.page_id(), page.epoch(), c.revision, format!("op-{}-{at_ms}", page.page_id()), c.update)
        .unwrap();
}

fn ids(store: &CoreStore) -> Vec<String> {
    store.pages().unwrap().into_iter().map(|p| p.id).collect()
}

fn mk(store: &CoreStore, after: Option<&str>) -> String {
    let p = store.create_page(after.map(String::from), format!("op-{}", new_page_id())).unwrap();
    p.page_id()
}

#[test]
fn catalog_order_and_insert_in_middle() {
    let (_d, path) = temp_db();
    let store = CoreStore::open(path).unwrap();
    let a = mk(&store, None);
    let b = mk(&store, Some(&a));
    let c = mk(&store, Some(&a));
    let got = ids(&store);
    assert_eq!(got[0], a);
    let mut rest = vec![b, c];
    rest.sort();
    assert_eq!(&got[1..], &rest[..]);
    assert!(store.pages().unwrap().iter().all(|p| !p.deleted));
}

#[test]
fn delete_and_restore_keep_position() {
    let (_d, path) = temp_db();
    let store = CoreStore::open(path).unwrap();
    let a = mk(&store, None);
    let b = mk(&store, Some(&a));
    let c = mk(&store, Some(&b));
    store.set_deleted(b.clone(), true).unwrap();
    assert_eq!(ids(&store), vec![a.clone(), b.clone(), c.clone()]);
    assert!(store.pages().unwrap()[1].deleted);
    store.set_deleted(b.clone(), false).unwrap();
    assert_eq!(ids(&store), vec![a, b.clone(), c]);
    assert!(store.pages().unwrap().iter().all(|p| !p.deleted));
    store.set_deleted(b, false).unwrap();
}

#[test]
fn summary_is_first_nonblank_visible_line_capped_at_40() {
    let (_d, path) = temp_db();
    let store = CoreStore::open(path).unwrap();
    let empty = store.create_page(None, "op-e".into()).unwrap();
    let p = store.create_page(Some(empty.page_id()), "op-p".into()).unwrap();
    type_text(&store, &p, "\n   \n  # 标题 \n正文", 1);
    let long = store.create_page(Some(p.page_id()), "op-l".into()).unwrap();
    type_text(&store, &long, &"字".repeat(50), 1);
    let infos = store.pages().unwrap();
    assert_eq!(infos[0].summary, "");
    assert_eq!(infos[0].modified_ms, None);
    assert_eq!(infos[1].summary, "# 标题");
    assert_eq!(infos[2].summary.chars().count(), 40);
}

#[test]
fn modified_is_max_line_time() {
    let (_d, path) = temp_db();
    let store = CoreStore::open(path).unwrap();
    let p = store.create_page(None, "op-m".into()).unwrap();
    type_text(&store, &p, "a", 100);
    type_text(&store, &p, "\nb", 300);
    let c = p.apply_edit(p.revision(), 0, 0, "x".into(), 200).unwrap();
    store.commit_delta(p.page_id(), p.epoch(), c.revision, "op-m3".into(), c.update).unwrap();
    assert_eq!(store.pages().unwrap()[0].modified_ms, Some(300));
}

#[test]
fn open_adopts_pages_missing_from_catalog() {
    let (_d, path) = temp_db();
    let mut want = vec![];
    {
        let store = CoreStore::open(path.clone()).unwrap();
        for i in 0..2 {
            let p = CorePage::create(new_page_id()).unwrap();
            want.push(p.page_id());
            store.commit_initial(p, format!("op-i{i}")).unwrap();
        }
    }
    want.sort();
    let store = CoreStore::open(path.clone()).unwrap();
    assert_eq!(ids(&store), want);
    let n = mk(&store, Some(&ids(&store)[1]));
    let got = ids(&store);
    assert_eq!(&got[..2], &want[..]);
    assert_eq!(got[2], n);
    drop(store);
    let store = CoreStore::open(path).unwrap();
    assert_eq!(ids(&store), got);
}

#[test]
fn catalog_state_survives_reopen() {
    let (_d, path) = temp_db();
    let before;
    {
        let store = CoreStore::open(path.clone()).unwrap();
        let a = mk(&store, None);
        let b = store.create_page(Some(a.clone()), "op-b".into()).unwrap();
        type_text(&store, &b, "hi", 5);
        store.set_deleted(a, true).unwrap();
        before = store.pages().unwrap();
    }
    let store = CoreStore::open(path).unwrap();
    let after = store.pages().unwrap();
    assert_eq!(before, after);
    assert_eq!(after[1].summary, "hi");
}

#[test]
fn create_page_with_missing_anchor_fails() {
    let (_d, path) = temp_db();
    let store = CoreStore::open(path).unwrap();
    mk(&store, None);
    let before = store.pages().unwrap();
    let r = store.create_page(Some(new_page_id()), "op-x".into());
    assert!(matches!(r, Err(CoreError::Storage { .. })));
    assert_eq!(store.pages().unwrap(), before);
}

#[test]
fn create_page_none_on_nonempty_catalog_is_a_root() {
    let (_d, path) = temp_db();
    let store = CoreStore::open(path).unwrap();
    let a = mk(&store, None);
    let b = mk(&store, Some(&a));
    let r = mk(&store, None);
    let got = ids(&store);
    assert_eq!(got.len(), 3);
    // b 挂在 a 下;r 是与 a 并列的根,按 UUID 与 a 排序,b 紧随 a。
    let ia = got.iter().position(|x| *x == a).unwrap();
    assert_eq!(got[ia + 1], b);
    assert!(got.contains(&r));
}
