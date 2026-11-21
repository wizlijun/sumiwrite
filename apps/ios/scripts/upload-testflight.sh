#!/usr/bin/env bash
# 打包并上传到 App Store Connect,供 TestFlight 使用。用法:bash apps/ios/scripts/upload-testflight.sh
# 团队与 Bundle ID 来自 Signing.local.xcconfig(git 忽略);上传用 Xcode 里登录的账号,脚本不碰任何密钥。
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$IOS/Signing.local.xcconfig"
if [ ! -f "$CFG" ]; then
  echo "缺少 apps/ios/Signing.local.xcconfig,见 apps/ios/README.md 的「签名」一节" >&2
  exit 1
fi
TEAM="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$CFG" | tr -d '[:space:]')"
if [ -z "$TEAM" ]; then echo "Signing.local.xcconfig 里没填 DEVELOPMENT_TEAM" >&2; exit 1; fi
RIME="$IOS/../../../rime-kit"
if [ ! -f "$RIME/scripts/fetch.sh" ]; then echo "缺 RimeKit:见 apps/ios/README.md" >&2; exit 1; fi
bash "$RIME/scripts/fetch.sh"
bash "$IOS/scripts/build-core.sh"
cd "$IOS"
xcodegen generate
# 构建号用年月日时分,每次上传都比上一次大。
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
OUT="$IOS/build/testflight"
rm -rf "$OUT" && mkdir -p "$OUT"
xcodebuild -project SumiWrite.xcodeproj -scheme SumiWrite -configuration Release \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates -derivedDataPath "$IOS/build/dd" \
  -archivePath "$OUT/SumiWrite.xcarchive" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/SumiWrite.xcarchive" -exportPath "$OUT" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates
echo "已上传构建号 $BUILD_NUMBER。App Store Connect 处理完(通常 5–15 分钟)后在 TestFlight 里可见。"
