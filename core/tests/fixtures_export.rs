//! 内核以 `fixtures` feature 导出夹具,供以 git 依赖引用内核的下游测试使用。
#![cfg(feature = "fixtures")]

use serde_json::Value;
use write_core::fixtures::{FORK_V1, PENDING_INVALID_V1, YRS_V1};

fn on_disk(name: &str) -> Value {
    let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

#[test]
fn fixtures_export_parses() {
    for (name, text) in [
        ("yrs-v1.json", YRS_V1),
        ("pending-invalid-v1.json", PENDING_INVALID_V1),
        ("fork-v1.json", FORK_V1),
    ] {
        let exported: Value = serde_json::from_str(text).unwrap();
        assert_eq!(exported, on_disk(name), "{name}");
    }
    let yrs: Value = serde_json::from_str(YRS_V1).unwrap();
    let disk = on_disk("yrs-v1.json");
    assert_eq!(yrs["pageId"], disk["pageId"]);
    assert_eq!(yrs["expected"]["body"], disk["expected"]["body"]);
    assert!(yrs["pageId"].is_string());
}
