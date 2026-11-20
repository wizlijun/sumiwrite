//! A file pair is a recoverable projection, never a two-file atomic transaction.
use crate::{Error, Result};
use crate::storage::{FilePair, Sidecar, parse_pair, sha256};
use serde::{Deserialize, Serialize};
use std::{fs::{self, OpenOptions}, io::Write, path::{Path, PathBuf}};
use uuid::Uuid;

fn io(error: std::io::Error) -> Error { Error::Invalid(format!("projection: {error}")) }
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Baseline { pub markdown_sha256: Option<String>, pub metadata_sha256: Option<String> }
fn read_hash(path:&Path) -> Result<Option<String>> {
    match fs::symlink_metadata(path) {
        Ok(meta) if !meta.is_file() || meta.file_type().is_symlink() => Err(Error::Invalid("projection target is not a regular file".into())),
        Ok(_) => fs::read(path).map(|bytes|Some(sha256(&bytes))).map_err(io),
        Err(error) if error.kind()==std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(io(error)),
    }
}
pub const ARCHIVE_UNAVAILABLE: &str = "archive directory is unavailable";
pub const FIRST_WRITE_CONFLICT: &str = "archive holds a different file under this name; recover it before writing";
/// Resolve the projection pair inside an existing archive directory. Never creates anything.
pub fn paths(archive:&Path, filename:&str) -> Result<(PathBuf,PathBuf)> {
    if !filename.ends_with(".writing.md") || filename.contains(['/', '\\', '\0']) || filename.starts_with('.') {
        return Err(Error::Invalid("invalid writing filename".into()));
    }
    if !archive.is_absolute() { return Err(Error::Invalid(ARCHIVE_UNAVAILABLE.into())); }
    let dir=fs::canonicalize(archive).map_err(|_|Error::Invalid(ARCHIVE_UNAVAILABLE.into()))?;
    if !fs::metadata(&dir).map(|meta|meta.is_dir()).unwrap_or(false) { return Err(Error::Invalid(ARCHIVE_UNAVAILABLE.into())); }
    Ok((dir.join(filename),dir.join(format!("{}.meta.json",filename.strip_suffix(".md").unwrap()))))
}
/// Create nested directories under `root`, refusing symlinks and non-directories at every layer.
pub fn create_archive_under(root:&Path, components:&[&str]) -> Result<PathBuf> {
    let mut dir=fs::canonicalize(root).map_err(io)?;
    for name in components {
        dir.push(name);
        match fs::symlink_metadata(&dir) {
            Ok(meta) if meta.file_type().is_symlink() || !meta.is_dir() => return Err(Error::Invalid("writing directory must not be a symlink".into())),
            Ok(_) => {},
            Err(error) if error.kind()==std::io::ErrorKind::NotFound => fs::create_dir(&dir).map_err(io)?,
            Err(error) => return Err(io(error)),
        }
    }
    Ok(dir)
}
fn replace(path:&Path, bytes:&[u8]) -> Result<()> {
    let temporary=path.with_file_name(format!(".sumi-{}.tmp",Uuid::new_v4()));
    let result=(|| {
        let mut output=OpenOptions::new().write(true).create_new(true).open(&temporary).map_err(io)?;
        output.write_all(bytes).map_err(io)?; output.sync_all().map_err(io)?;
        fs::rename(&temporary,path).map_err(io)?;
        #[cfg(unix)] fs::File::open(path.parent().unwrap()).and_then(|dir|dir.sync_all()).map_err(io)?;
        Ok(())
    })();
    if temporary.exists() { let _=fs::remove_file(&temporary); }
    result
}
/// Accept only the prior published bytes or this exact pending projection.
/// The latter is essential when recovering after writing only one of the files.
/// External processes that ignore file coordination still have a TOCTOU window;
/// callers must retain recovery state and must not advertise arbitrary-writer CAS.
pub fn publish(archive:&Path, filename:&str, pair:&FilePair, baseline:&Baseline) -> Result<Baseline> {
    let (markdown,metadata)=paths(archive,filename)?;
    let next=Baseline { markdown_sha256:Some(sha256(pair.markdown.as_bytes())), metadata_sha256:Some(sha256(pair.metadata.as_bytes())) };
    let current_md=read_hash(&markdown)?; let current_meta=read_hash(&metadata)?;
    if (current_md!=baseline.markdown_sha256 && current_md!=next.markdown_sha256)
        || (current_meta!=baseline.metadata_sha256 && current_meta!=next.metadata_sha256) {
        return Err(Error::Invalid("external projection change; preserve and import before writing".into()));
    }
    if current_md!=next.markdown_sha256 { replace(&markdown,pair.markdown.as_bytes())?; }
    // A watcher or external tool can run while the first file is being replaced.
    if read_hash(&metadata)?!=current_meta { return Err(Error::Invalid("external metadata change during projection".into())); }
    if current_meta!=next.metadata_sha256 { replace(&metadata,pair.metadata.as_bytes())?; }
    if read_hash(&markdown)?!=next.markdown_sha256 || read_hash(&metadata)?!=next.metadata_sha256 {
        return Err(Error::Invalid("projection changed before verification".into()));
    }
    Ok(next)
}

#[derive(Debug, Clone)]
pub enum FirstWrite { Written(Baseline), Adopted(Baseline), Replaced(Baseline), Conflict }
fn read_text(path:&Path) -> Result<Option<Vec<u8>>> {
    match fs::symlink_metadata(path) {
        Ok(meta) if !meta.is_file() || meta.file_type().is_symlink() => Err(Error::Invalid("projection target is not a regular file".into())),
        Ok(_) => fs::read(path).map(Some).map_err(io),
        Err(error) if error.kind()==std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(io(error)),
    }
}
/// First write for a page with no recorded baseline: write, adopt identical files, finish this
/// page's own interrupted write, replace this page's own older version, otherwise report a
/// conflict without touching the disk. Files are written markdown first, then sidecar, like `publish`.
pub fn publish_first(archive:&Path, filename:&str, pair:&FilePair) -> Result<FirstWrite> {
    let (markdown,metadata)=paths(archive,filename)?;
    let ours=parse_pair(&pair.markdown,&pair.metadata)?;
    let next=Baseline { markdown_sha256:Some(sha256(pair.markdown.as_bytes())), metadata_sha256:Some(sha256(pair.metadata.as_bytes())) };
    let (md,meta)=(read_text(&markdown)?,read_text(&metadata)?);
    let md_same=md.as_deref().map(|b|b==pair.markdown.as_bytes());
    let meta_same=meta.as_deref().map(|b|b==pair.metadata.as_bytes());
    let write=|written:fn(Baseline)->FirstWrite| -> Result<FirstWrite> {
        if md_same!=Some(true) { replace(&markdown,pair.markdown.as_bytes())?; }
        if meta_same!=Some(true) { replace(&metadata,pair.metadata.as_bytes())?; }
        Ok(written(next.clone()))
    };
    if md_same==Some(true) && meta_same==Some(true) { return Ok(FirstWrite::Adopted(next)); }
    // Nothing there, or each present file is already our pending bytes: an interrupted first write.
    if md_same!=Some(false) && meta_same!=Some(false) { return write(FirstWrite::Written); }
    // Pending markdown plus this page's older sidecar: an interrupted replace.
    if md_same==Some(true) {
        let own=meta.as_deref().and_then(|b|serde_json::from_slice::<Sidecar>(b).ok())
            .is_some_and(|theirs|theirs.page_id==ours.sidecar.page_id && theirs.epoch==ours.sidecar.epoch);
        return if own { write(FirstWrite::Replaced) } else { Ok(FirstWrite::Conflict) };
    }
    let (Some(md),Some(meta))=(md,meta) else { return Ok(FirstWrite::Conflict) };
    let (Ok(md),Ok(meta))=(String::from_utf8(md),String::from_utf8(meta)) else { return Ok(FirstWrite::Conflict) };
    match parse_pair(&md,&meta) {
        Ok(theirs) if theirs.sidecar.page_id==ours.sidecar.page_id && theirs.sidecar.epoch==ours.sidecar.epoch => write(FirstWrite::Replaced),
        _ => Ok(FirstWrite::Conflict),
    }
}
