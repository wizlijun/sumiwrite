//! `golden <out_dir>`:用桌面同一份内核造夹具与比对基准,供 Swift 侧逐项核对。
//! 写出 yrs-v1.json、yjs-v1.json(夹具原样)、desktop.sqlite3、golden.json。
use base64::{engine::general_purpose::STANDARD as B, Engine};
use write_core::storage::{serialize_pair, Store};
use write_core::{Document, Snapshot};

const RUST_FIXTURE: &str = include_str!("../../../../../core/tests/fixtures/yrs-v1.json");
const YJS_FIXTURE: &str = include_str!("../../../../../sync/tests/yjs-v1.json");
const DESKTOP_PAGE: &str = "5a1e0c3b-6f0d-4e0a-9d9e-1f2a3b4c5d6e";
const YJS_PAGE: &str = "87d92d1a-f37d-46e8-b83e-dc3e671fb425";

/// 生成 desktop.sqlite3,返回结束时的快照。
fn make_desktop(dir: &str) -> Snapshot {
    let db = format!("{dir}/desktop.sqlite3");
    for ext in ["", "-wal", "-shm"] {
        let _ = std::fs::remove_file(format!("{db}{ext}"));
    }
    let mut store = Store::open(&db).unwrap();
    let mut doc = Document::new(DESKTOP_PAGE, 1, 4242).unwrap();
    let t0: i64 = 1_763_600_000_000;
    // 首个事务:整页完整提交
    let u = doc.replace(doc.revision(), 0, 0, "桌面写的第一行", t0).unwrap();
    let pair = serialize_pair(&doc.snapshot().unwrap(), None, None).unwrap();
    store.commit_local_with(&doc, "op-0", &u, &pair, |_| Ok(())).unwrap();
    // 之后逐键追加增量(含换行、emoji、组合字符、删除、行中插入)
    let mut n = 1;
    let mut put = |doc: &mut Document, store: &mut Store, at: u32, len: u32, text: &str, ms: i64| {
        let u = doc.replace(doc.revision(), at, len, text, ms).unwrap();
        store
            .commit_local_delta_with(DESKTOP_PAGE, 1, doc.revision(), &format!("op-{n}"), &u, |_| Ok(()))
            .unwrap();
        n += 1;
    };
    let mut ms = t0 + 1000;
    for ch in "\nSecond line 😀 with emoji".chars() {
        let at = doc.body().encode_utf16().count() as u32;
        put(&mut doc, &mut store, at, 0, &ch.to_string(), ms);
        ms += 120;
    }
    let at = doc.body().encode_utf16().count() as u32;
    put(&mut doc, &mut store, at, 0, "\n第三行 👨‍👩‍👧 e\u{301}", ms);
    ms += 500;
    // 中途做一次检查点,检验「检查点 + 增量尾巴」的恢复路径
    let pair = serialize_pair(&doc.snapshot().unwrap(), None, None).unwrap();
    store.checkpoint_with(&doc, &pair, |_| Ok(())).unwrap();
    put(&mut doc, &mut store, 2, 0, "（插入）", ms);
    ms += 300;
    let len = doc.body().encode_utf16().count() as u32;
    put(&mut doc, &mut store, len - 2, 2, "", ms); // 删掉末尾 e+组合重音
    ms += 300;
    let at = doc.body().encode_utf16().count() as u32;
    put(&mut doc, &mut store, at, 0, "\n最后一行", ms);
    drop(store);
    doc.snapshot().unwrap()
}

fn main() {
    let out = std::env::args().nth(1).expect("usage: golden <out_dir>");
    std::fs::create_dir_all(&out).unwrap();
    let desktop = make_desktop(&out);

    let rf: serde_json::Value = serde_json::from_str(RUST_FIXTURE).unwrap();
    let jf: serde_json::Value = serde_json::from_str(YJS_FIXTURE).unwrap();
    let d = |v: &serde_json::Value| B.decode(v.as_str().unwrap()).unwrap();
    let page = rf["pageId"].as_str().unwrap();
    let ups: Vec<Vec<u8>> = rf["updates"].as_array().unwrap().iter().map(d).collect();
    let mut fwd = Document::load(page, 1, 999, &d(&rf["base"])).unwrap();
    for u in &ups {
        fwd.apply_remote(u).unwrap();
    }
    let mut rev = Document::load(page, 1, 998, &d(&rf["base"])).unwrap();
    for u in ups.iter().rev() {
        rev.apply_remote(u).unwrap();
    }
    let full = Document::load(page, 1, 997, &d(&rf["full"])).unwrap();
    let mut yjs = Document::load(YJS_PAGE, 1, 996, &d(&jf["base"])).unwrap();
    yjs.apply_remote(&d(&jf["update"])).unwrap();

    let golden = serde_json::json!({
        "rust_forward": fwd.snapshot().unwrap(),
        "rust_reverse": rev.snapshot().unwrap(),
        "rust_full": full.snapshot().unwrap(),
        "yjs": yjs.snapshot().unwrap(),
        "desktop": desktop,
    });
    std::fs::write(format!("{out}/golden.json"), serde_json::to_string_pretty(&golden).unwrap()).unwrap();
    std::fs::write(format!("{out}/yrs-v1.json"), RUST_FIXTURE).unwrap();
    std::fs::write(format!("{out}/yjs-v1.json"), YJS_FIXTURE).unwrap();
}
