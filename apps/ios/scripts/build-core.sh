#!/usr/bin/env bash
# 构建内核 XCFramework、生成 Swift 绑定、生成 M0 夹具。可重复执行,每次先清旧产物。
# 用法:bash apps/ios/scripts/build-core.sh
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"
export IPHONEOS_DEPLOYMENT_TARGET=17.0
TC=+1.99.0
MANIFEST="$IOS/ffi/Cargo.toml"
TARGET_DIR="$IOS/ffi/target"
B="$IOS/build"

rm -rf "$B/gen" "$B/headers" "$B/fixtures" "$B/SumiCoreFFI.xcframework"
mkdir -p "$B/gen" "$B/headers" "$B/fixtures"

cargo $TC build --release --lib --manifest-path "$MANIFEST" --target aarch64-apple-ios
cargo $TC build --release --lib --manifest-path "$MANIFEST" --target aarch64-apple-ios-sim
cargo $TC build --release --lib --manifest-path "$MANIFEST"

(cd "$IOS/ffi" && cargo $TC run --release --bin uniffi-bindgen -- \
  generate --library "$TARGET_DIR/release/libsumi_ios_ffi.dylib" --language swift --out-dir "$B/gen")
cp "$B/gen/sumi_ios_ffiFFI.h" "$B/headers/"
cp "$B/gen/sumi_ios_ffiFFI.modulemap" "$B/headers/module.modulemap"
# 头文件与 modulemap 只放进 xcframework,不留在源码组里
rm -f "$B/gen/sumi_ios_ffiFFI.h" "$B/gen/sumi_ios_ffiFFI.modulemap"

xcodebuild -create-xcframework \
  -library "$TARGET_DIR/aarch64-apple-ios/release/libsumi_ios_ffi.a" -headers "$B/headers" \
  -library "$TARGET_DIR/aarch64-apple-ios-sim/release/libsumi_ios_ffi.a" -headers "$B/headers" \
  -output "$B/SumiCoreFFI.xcframework"

cargo $TC run --release --manifest-path "$MANIFEST" --bin golden -- "$B/fixtures"
ls -la "$B/fixtures"
