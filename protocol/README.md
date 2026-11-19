# sumi-protocol

Internal service-contract types between the note.md host and the Sumi plugin backend, never exposed to plugin WebViews: durability requests, receipts and events (`durability`), font aliases and status (`fonts`), sync-service messages (`sync`) and the service envelope (`service`). This is an internal host↔backend contract, not the sync wire protocol (that is the Yjs V1 update format in `../core`); the iOS app does not use it.

It depends on the editing core through `write-core = { path = "../core" }`.

## Verification

```sh
cargo +1.99.0 test --manifest-path protocol/Cargo.toml
cargo +1.99.0 clippy --manifest-path protocol/Cargo.toml --all-targets -- -D warnings
```
