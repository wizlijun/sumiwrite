#!/usr/bin/env bash
# Verification 入口:构建内核、生成工程、在模拟器上跑 XCTest。
# 用法:bash apps/ios/scripts/test-sim.sh   (SIM 环境变量可改模拟器名)
set -euo pipefail
IOS="$(cd "$(dirname "$0")/.." && pwd)"
bash "$IOS/scripts/build-core.sh"
cd "$IOS"
xcodegen generate
xcodebuild test -project SumiWrite.xcodeproj -scheme SumiWrite \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 17 Pro Max}" \
  -derivedDataPath "$IOS/build/dd-sim"
