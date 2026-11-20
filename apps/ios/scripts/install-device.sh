#!/usr/bin/env bash
# 构建并装到真机。用法:bash apps/ios/scripts/install-device.sh <设备名或 UDID>
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
DEV="${1:-}"
if [ -z "$DEV" ]; then echo "用法: install-device.sh <设备名或 UDID>" >&2; exit 2; fi
if [ ! -f "$IOS/Signing.local.xcconfig" ]; then
  echo "缺少 apps/ios/Signing.local.xcconfig,见 apps/ios/README.md 的「签名」一节" >&2
  exit 1
fi
# 内嵌输入法 RimeKit 在 ~/git/rime-kit(与 project.yml 的本地包路径一致);它的二进制与词库由 fetch.sh 取。
RIME="$IOS/../../../rime-kit"
if [ ! -f "$RIME/scripts/fetch.sh" ]; then
  echo "缺 RimeKit:见 apps/ios/README.md" >&2
  exit 1
fi
bash "$RIME/scripts/fetch.sh"
bash "$IOS/scripts/build-core.sh"
cd "$IOS"
xcodegen generate
if [[ "$DEV" =~ ^[0-9A-Fa-f-]{20,}$ ]]; then DEST="platform=iOS,id=$DEV"; else DEST="platform=iOS,name=$DEV"; fi
xcodebuild -project SumiWrite.xcodeproj -scheme SumiWrite -configuration Release \
  -destination "$DEST" -allowProvisioningUpdates -derivedDataPath "$IOS/build/dd" build
APP="$IOS/build/dd/Build/Products/Release-iphoneos/SumiWrite.app"
xcrun devicectl device install app --device "$DEV" "$APP"
