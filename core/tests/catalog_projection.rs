use write_core::{catalog, projection, storage::{Store, FilePair}, Document};
use uuid::Uuid;

#[test]
fn empty_pages_get_a_filename_only_on_first_written_day_and_never_reuse_deleted_slots() {
    let temp=tempfile::tempdir().unwrap(); let mut store=Store::open(temp.path().join("state.db")).unwrap();
    store.transaction(|tx| {
        catalog::initialize(tx)?;
        let first=Uuid::new_v4().to_string();
        assert!(catalog::create(tx,&first,None)?.filename().is_none());
        assert_eq!(catalog::first_write(tx,&first,"2026-11-08")?.filename().unwrap(),"2026-11-08-01.writing.md");
        assert_eq!(catalog::first_write(tx,&first,"2026-11-09")?.local_date.as_deref(),Some("2026-11-08"));
        catalog::set_deleted(tx,&first,true)?;
        let mut last=None;
        for _ in 0..100 { let id=Uuid::new_v4().to_string(); catalog::create(tx,&id,last.as_deref())?; last=Some(id.clone()); catalog::first_write(tx,&id,"2026-11-08")?; }
        assert_eq!(catalog::get(tx,last.as_deref().unwrap())?.unwrap().filename().unwrap(),"2026-11-08-101.writing.md");
        Ok(())
    }).unwrap();
}

#[test]
fn server_filename_reassigns_only_provisional_collision_without_losing_local_delete() {
    let temp=tempfile::tempdir().unwrap(); let mut store=Store::open(temp.path().join("state.db")).unwrap();
    store.transaction(|tx| {
        catalog::initialize(tx)?;
        let a=Uuid::new_v4().to_string(); catalog::create(tx,&a,None)?;
        catalog::first_write(tx,&a,"2026-11-08")?; catalog::set_deleted(tx,&a,true)?;
        let b=catalog::Entry {id:Uuid::new_v4().to_string(),epoch:1,generation:0,deleted:false,local_date:Some("2026-11-08".into()),sequence:Some(1),after_id:None,registered:true};
        let changes=catalog::apply_remote(tx,&b)?;
        assert_eq!(changes.len(),2);
        assert_eq!(catalog::get(tx,&a)?.unwrap().sequence,Some(2));
        let mut stale=catalog::get(tx,&a)?.unwrap(); stale.generation=0; stale.deleted=false;
        catalog::apply_remote(tx,&stale)?;
        assert!(catalog::get(tx,&a)?.unwrap().deleted);
        Ok(())
    }).unwrap();
}

#[test]
fn failed_document_transaction_does_not_leave_directory_or_outbox_behind() {
    let temp=tempfile::tempdir().unwrap(); let mut store=Store::open(temp.path().join("state.db")).unwrap();
    store.transaction(catalog::initialize).unwrap();
    let id=Uuid::new_v4().to_string(); let doc=Document::new(&id,1,11).unwrap();
    let pair=write_core::storage::serialize_pair(&doc.snapshot().unwrap(),None,None).unwrap();
    assert!(store.commit_local_with(&doc,&Uuid::new_v4().to_string(),&doc.encode_full(),&pair,|tx| {
        catalog::create(tx,&id,None)?;
        Err(write_core::Error::Invalid("injected failure".into()))
    }).is_err());
    assert!(store.outbox().unwrap().is_empty());
    assert!(store.transaction(|tx|catalog::get(tx,&id)).unwrap().is_none());
    assert!(store.load(&id,12).is_err());
}

fn pair(text:&str)->FilePair { FilePair { markdown:text.into(),metadata:format!("metadata for {text}") } }

#[test]
fn interrupted_pair_write_can_resume_but_unrelated_files_are_never_overwritten() {
    let root=tempfile::tempdir().unwrap(); let filename="2026-11-08-01.writing.md"; let pair=pair("hello");
    let (md,meta)=projection::paths(root.path(),filename).unwrap();
    std::fs::write(&md,&pair.markdown).unwrap(); // crash after the first rename
    let baseline=projection::publish(root.path(),filename,&pair,&projection::Baseline::default()).unwrap();
    assert_eq!(std::fs::read_to_string(&meta).unwrap(),pair.metadata);
    std::fs::write(&md,"external author").unwrap();
    assert!(projection::publish(root.path(),filename,&self::pair("next"),&baseline).is_err());
    assert_eq!(std::fs::read_to_string(&md).unwrap(),"external author");
    assert_eq!(std::fs::read_to_string(&meta).unwrap(),pair.metadata);
}

#[test]
fn metadata_conflict_is_checked_before_any_markdown_write() {
    let root=tempfile::tempdir().unwrap(); let filename="2026-11-08-01.writing.md";
    let (md,meta)=projection::paths(root.path(),filename).unwrap();
    std::fs::write(&meta,"unrelated metadata").unwrap();
    assert!(projection::publish(root.path(),filename,&pair("hello"),&projection::Baseline::default()).is_err());
    assert!(!md.exists());
    assert!(projection::paths(root.path(),"../escape.writing.md").is_err());
}

#[cfg(unix)]
#[test]
fn symlinked_writing_directory_cannot_escape_vault() {
    let root=tempfile::tempdir().unwrap(); let outside=tempfile::tempdir().unwrap();
    std::os::unix::fs::symlink(outside.path(),root.path().join("inbox")).unwrap();
    let error=projection::create_archive_under(root.path(),&["inbox","writings"]).unwrap_err();
    assert!(error.to_string().contains("writing directory must not be a symlink"));
    assert_eq!(std::fs::read_dir(outside.path()).unwrap().count(),0);
}

#[test]
fn create_archive_under_builds_layers_and_rejects_symlink_layer() {
    let vault=tempfile::tempdir().unwrap();
    let dir=projection::create_archive_under(vault.path(),&["inbox","writings"]).unwrap();
    assert_eq!(dir,std::fs::canonicalize(vault.path().join("inbox/writings")).unwrap());
    assert!(dir.is_dir());
}

#[test]
fn paths_use_archive_directly() {
    let dir=tempfile::tempdir().unwrap(); let canon=std::fs::canonicalize(dir.path()).unwrap();
    let got=projection::paths(dir.path(),"2026-11-20-01.writing.md").unwrap();
    assert_eq!(got,(canon.join("2026-11-20-01.writing.md"),canon.join("2026-11-20-01.writing.meta.json")));
    assert!(!dir.path().join("inbox").exists());
}

#[cfg(unix)]
#[test]
fn paths_accept_symlinked_archive() {
    let dir=tempfile::tempdir().unwrap(); let real=dir.path().join("real"); std::fs::create_dir(&real).unwrap();
    let link=dir.path().join("link"); std::os::unix::fs::symlink(&real,&link).unwrap();
    let (md,_)=projection::paths(&link,"2026-11-20-01.writing.md").unwrap();
    assert!(md.starts_with(std::fs::canonicalize(&real).unwrap()));
}

#[test]
fn paths_reject_missing_archive_without_creating_it() {
    let dir=tempfile::tempdir().unwrap();
    let error=projection::paths(&dir.path().join("missing"),"2026-11-20-01.writing.md").unwrap_err();
    assert!(error.to_string().contains("archive directory is unavailable"));
    assert!(!dir.path().join("missing").exists());
}

#[test]
fn paths_reject_relative_or_file_archive() {
    let dir=tempfile::tempdir().unwrap(); let file=dir.path().join("plain"); std::fs::write(&file,"x").unwrap();
    for archive in [std::path::Path::new("relative/dir"),file.as_path()] {
        let error=projection::paths(archive,"2026-11-20-01.writing.md").unwrap_err();
        assert!(error.to_string().contains(projection::ARCHIVE_UNAVAILABLE));
    }
}

fn real_pair(page:&str, epoch:u32, text:&str) -> FilePair {
    let mut doc=Document::new(page,epoch,5).unwrap();
    doc.replace(doc.revision(),0,0,text,1).unwrap();
    write_core::storage::serialize_pair(&doc.snapshot().unwrap(),None,None).unwrap()
}
const NAME:&str="2026-11-20-01.writing.md";
fn put(dir:&std::path::Path, pair:&FilePair) {
    let (md,meta)=projection::paths(dir,NAME).unwrap();
    std::fs::write(md,&pair.markdown).unwrap(); std::fs::write(meta,&pair.metadata).unwrap();
}
fn disk(dir:&std::path::Path) -> (String,String) {
    let (md,meta)=projection::paths(dir,NAME).unwrap();
    (std::fs::read_to_string(md).unwrap(),std::fs::read_to_string(meta).unwrap())
}

#[test]
fn publish_first_writes_when_absent() {
    let dir=tempfile::tempdir().unwrap(); let page=Uuid::new_v4().to_string(); let p=real_pair(&page,1,"hello");
    let projection::FirstWrite::Written(b)=projection::publish_first(dir.path(),NAME,&p).unwrap() else { panic!("expected Written") };
    assert_eq!(disk(dir.path()),(p.markdown.clone(),p.metadata.clone()));
    assert_eq!(b.markdown_sha256,Some(write_core::storage::sha256(p.markdown.as_bytes())));
    assert_eq!(b.metadata_sha256,Some(write_core::storage::sha256(p.metadata.as_bytes())));
}

#[cfg(unix)]
#[test]
fn publish_first_adopts_identical_files() {
    use std::os::unix::fs::MetadataExt;
    let dir=tempfile::tempdir().unwrap(); let page=Uuid::new_v4().to_string(); let p=real_pair(&page,1,"hello");
    put(dir.path(),&p);
    let (md,meta)=projection::paths(dir.path(),NAME).unwrap();
    let before=[&md,&meta].map(|f|std::fs::metadata(f).unwrap());
    assert!(matches!(projection::publish_first(dir.path(),NAME,&p).unwrap(),projection::FirstWrite::Adopted(_)));
    for (f,old) in [&md,&meta].into_iter().zip(before) {
        let now=std::fs::metadata(f).unwrap();
        assert_eq!((now.ino(),now.mtime(),now.mtime_nsec()),(old.ino(),old.mtime(),old.mtime_nsec()));
    }
}

#[test]
fn publish_first_replaces_own_old_version() {
    let dir=tempfile::tempdir().unwrap(); let page=Uuid::new_v4().to_string();
    let mut doc=Document::new(&page,1,5).unwrap();
    doc.replace(doc.revision(),0,0,"v1",1).unwrap();
    let v1=write_core::storage::serialize_pair(&doc.snapshot().unwrap(),None,None).unwrap();
    put(dir.path(),&v1);
    doc.replace(doc.revision(),2,0," and more",2).unwrap();
    let v2=write_core::storage::serialize_pair(&doc.snapshot().unwrap(),None,None).unwrap();
    assert_ne!(v1.markdown,v2.markdown);
    assert!(matches!(projection::publish_first(dir.path(),NAME,&v2).unwrap(),projection::FirstWrite::Replaced(_)));
    assert_eq!(disk(dir.path()),(v2.markdown,v2.metadata));
}

fn assert_conflict(dir:&std::path::Path, p:&FilePair) {
    let before=disk(dir);
    assert!(matches!(projection::publish_first(dir,NAME,p).unwrap(),projection::FirstWrite::Conflict));
    assert_eq!(disk(dir),before);
}

#[test]
fn publish_first_conflicts_on_other_page() {
    let dir=tempfile::tempdir().unwrap();
    put(dir.path(),&real_pair(&Uuid::new_v4().to_string(),1,"other"));
    assert_conflict(dir.path(),&real_pair(&Uuid::new_v4().to_string(),1,"mine"));
}

#[test]
fn publish_first_conflicts_on_other_epoch() {
    let dir=tempfile::tempdir().unwrap(); let page=Uuid::new_v4().to_string();
    put(dir.path(),&real_pair(&page,2,"old"));
    assert_conflict(dir.path(),&real_pair(&page,1,"mine"));
}

#[test]
fn publish_first_conflicts_on_edited_body() {
    let dir=tempfile::tempdir().unwrap(); let page=Uuid::new_v4().to_string();
    let old=real_pair(&page,1,"old");
    put(dir.path(),&FilePair { markdown:format!("{}\nextra line",old.markdown),metadata:old.metadata.clone() });
    assert_conflict(dir.path(),&real_pair(&page,1,"mine"));
}

#[test]
fn publish_first_conflicts_on_half_pair() {
    let page=Uuid::new_v4().to_string(); let old=real_pair(&page,1,"old"); let mine=real_pair(&page,1,"mine");
    for keep_markdown in [true,false] {
        let dir=tempfile::tempdir().unwrap();
        let (md,meta)=projection::paths(dir.path(),NAME).unwrap();
        let (kept,bytes)=if keep_markdown { (&md,&old.markdown) } else { (&meta,&old.metadata) };
        std::fs::write(kept,bytes).unwrap();
        assert!(matches!(projection::publish_first(dir.path(),NAME,&mine).unwrap(),projection::FirstWrite::Conflict));
        assert_eq!((md.exists(),meta.exists()),(keep_markdown,!keep_markdown));
        assert_eq!(std::fs::read_to_string(kept).unwrap(),*bytes);
    }
}

#[test]
fn publish_first_finishes_interrupted_write_with_markdown_only() {
    let dir=tempfile::tempdir().unwrap(); let p=real_pair(&Uuid::new_v4().to_string(),1,"mine");
    let (md,_)=projection::paths(dir.path(),NAME).unwrap(); std::fs::write(md,&p.markdown).unwrap();
    assert!(matches!(projection::publish_first(dir.path(),NAME,&p).unwrap(),projection::FirstWrite::Written(_)));
    assert_eq!(disk(dir.path()),(p.markdown,p.metadata));
}

#[test]
fn publish_first_finishes_interrupted_write_with_sidecar_only() {
    let dir=tempfile::tempdir().unwrap(); let p=real_pair(&Uuid::new_v4().to_string(),1,"mine");
    let (_,meta)=projection::paths(dir.path(),NAME).unwrap(); std::fs::write(meta,&p.metadata).unwrap();
    assert!(matches!(projection::publish_first(dir.path(),NAME,&p).unwrap(),projection::FirstWrite::Written(_)));
    assert_eq!(disk(dir.path()),(p.markdown,p.metadata));
}

#[test]
fn publish_first_finishes_interrupted_replace() {
    let dir=tempfile::tempdir().unwrap(); let page=Uuid::new_v4().to_string();
    let v1=real_pair(&page,1,"v1"); let v2=real_pair(&page,1,"v2 longer");
    let (md,meta)=projection::paths(dir.path(),NAME).unwrap();
    std::fs::write(md,&v2.markdown).unwrap(); std::fs::write(meta,&v1.metadata).unwrap();
    assert!(matches!(projection::publish_first(dir.path(),NAME,&v2).unwrap(),projection::FirstWrite::Replaced(_)));
    assert_eq!(disk(dir.path()),(v2.markdown,v2.metadata));
}

#[test]
fn publish_first_conflicts_when_sidecar_belongs_to_other_page() {
    let dir=tempfile::tempdir().unwrap();
    let mine=real_pair(&Uuid::new_v4().to_string(),1,"mine"); let other=real_pair(&Uuid::new_v4().to_string(),1,"other");
    let (md,meta)=projection::paths(dir.path(),NAME).unwrap();
    std::fs::write(md,&mine.markdown).unwrap(); std::fs::write(meta,&other.metadata).unwrap();
    assert_conflict(dir.path(),&mine);
}

#[test]
fn publish_first_rejects_missing_archive() {
    let dir=tempfile::tempdir().unwrap(); let missing=dir.path().join("gone");
    let error=projection::publish_first(&missing,NAME,&real_pair(&Uuid::new_v4().to_string(),1,"x")).unwrap_err();
    assert!(error.to_string().contains(projection::ARCHIVE_UNAVAILABLE));
    assert!(!missing.exists());
}
