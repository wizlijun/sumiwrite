# apps/ios

iOS 应用(M0、M1)。与桌面共用同一套 Rust 内核 `core/`,经 `ffi/`(UniFFI)暴露给 Swift;Swift 里不含 CRDT、行时间、合并或恢复逻辑。设计见 [`docs/superpowers/specs/2026-11-20-ios-m0-m1-design.md`](../../docs/superpowers/specs/2026-11-20-ios-m0-m1-design.md)。

## 一次性准备

```
rustup +1.99.0 target add aarch64-apple-ios aarch64-apple-ios-sim
```

另需 Xcode 与 XcodeGen。

## 构建

- `bash apps/ios/scripts/build-core.sh`:产出 `build/SumiCoreFFI.xcframework`、`build/gen/sumi_ios_ffi.swift` 和 `build/fixtures/`(`yrs-v1.json`、`yjs-v1.json`、`desktop.sqlite3`、`golden.json`)。可重复执行。
- `xcodegen generate`(在 `apps/ios/` 下):生成 `SumiWrite.xcodeproj`,该工程不入库。
- 真机:`bash apps/ios/scripts/install-device.sh <设备名或 UDID>`,需先配好签名。

## Verification

```
bash apps/ios/scripts/test-sim.sh
cargo +1.99.0 test --manifest-path apps/ios/ffi/Cargo.toml
```

第一条构建内核、生成工程并在模拟器(默认 iPhone 17 Pro Max,可用 `SIM` 覆盖)上跑 XCTest,必须以 `** TEST SUCCEEDED **` 结束。

手工项(不进自动测试):性能测量,在真机上记录输入延迟与大页载入时间。

## 签名

复制 `Signing.example.xcconfig` 为 `Signing.local.xcconfig`,填自己的团队与 Bundle ID。该文件已被 `.gitignore` 忽略,仓库里不放任何真值。
