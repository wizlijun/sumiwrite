# Sumi Write 插件壳(notemd.sumi)

note.md 宿主里的 Sumi Write 插件:前端界面、Rust 后台(crate `notemd-sumi-backend`,二进制 `notemd-sumi`)、资源(字体、音效、许可文本)与插件侧校验脚本。编辑内核、协议与会话逻辑来自本仓库的 `core/`、`protocol/`,后台按 tag `core-v0.1.0` 引用。插件 SDK 与 `plugin-protocol` 归 note.md,后台按 tag `plugin-sdk-v0.1.0` 引用。签名、公证与上架归 note.md,本目录不含任何凭据。

## 目录结构

- `backend/`:Rust 后台 crate(`src/`、`tests/`、`native/`、`build.rs`、`Cargo.lock`)。
- `src/`、`index.html`、`vite.config.ts`、`vitest.config.ts`、`tsconfig.json`、`package.json`:前端。
- `manifest.v2.json`:插件清单。
- `resources/`:`sounds/`、`sumi/`(字体与许可文本,按字节保持不变)。
- `scripts/`:`build-artifact.sh`、`verify-stage.py`、`verify-linux-binary.py`、`verify-sounds.py` 及其测试。

## 构建待签名构建物

```sh
apps/notemd-plugin/scripts/build-artifact.sh --target <三元组> --out <目录> [--debug]
```

输出 `<目录>/stage/`(未签名的安装布局)与 `<目录>/checklist.json`(含 `source_commit` 与每个文件的 SHA-256)。`<目录>` 必须不存在或为空。脚本不读任何签名或公证凭据;签名、公证与上架在 note.md。格式见 [`docs/handoff/03-notemd-contract.md`](../../docs/handoff/03-notemd-contract.md) §5。

## Verification

```sh
cargo +1.99.0 test --manifest-path apps/notemd-plugin/backend/Cargo.toml
cargo +1.99.0 clippy --manifest-path apps/notemd-plugin/backend/Cargo.toml --all-targets -- -D warnings
npm --prefix apps/notemd-plugin ci
npm --prefix apps/notemd-plugin test
npm --prefix apps/notemd-plugin run check
npm --prefix apps/notemd-plugin run build
python3 -I -m unittest discover -s apps/notemd-plugin/scripts -p 'test_*.py'
```

带 `#[ignore]` 的联机测试只需编译通过。

## 本地联调 SDK

默认按 tag 取 SDK。要联调本地 note.md 的 SDK 时,在 `backend/Cargo.toml` 末尾临时加入下面的片段,不要提交:

```toml
[patch."https://github.com/wizlijun/note.md"]
notemd-plugin-sdk = { path = "../../../note.md/notemd-plugin-sdk" }
```
