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
