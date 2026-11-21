#!/usr/bin/env bash
# Verification 入口:构建内核、生成工程、在模拟器上跑 XCTest。
# 用法:bash apps/ios/scripts/test-sim.sh   (SIM 环境变量可改模拟器,如 SIM="iPhone 18 Pro,OS=27.2";
# 默认钉在 iOS 26.5:不写 OS 时 xcodebuild 只找最新系统上的同名模拟器)
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
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
xcodebuild test -project SumiWrite.xcodeproj -scheme SumiWrite \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 17 Pro Max,OS=26.5}" \
  -derivedDataPath "$IOS/build/dd-sim"
