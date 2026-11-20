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

## 真机安装

1. 复制签名模板:`cp apps/ios/Signing.example.xcconfig apps/ios/Signing.local.xcconfig`,在 `Signing.local.xcconfig` 里填自己的团队与 Bundle ID(详见下一节「签名」)。该文件被 git 忽略;没有它,安装脚本会直接退出。
2. 做过一次性准备(见上)。
3. 设备连上电脑并解锁,运行 `bash apps/ios/scripts/install-device.sh "<设备名>"`(设备名或 UDID 均可)。脚本依次构建内核、生成工程、用 `xcodebuild -allowProvisioningUpdates` 构建,再用 `xcrun devicectl device install app` 装到设备。
4. 首次安装后,在设备的「设置 › 通用 › VPN 与设备管理」里信任开发者,然后才能打开应用。

## 手工验收(M1)

在真机上逐条执行;模拟器测不了这些。

1. 拼音输入中英文,选词上屏,正文与内核一致;
2. emoji 与组合字;粘贴 `# 标题`、`**粗体**` 等 Markdown 后显示为富文本,直接键入的 `#`、`*` 按字面保留;
3. 撤销与重做;
4. 全程看不到系统细线光标,呼吸与常亮都对;
5. 六种主题、字号、行距;
6. 聚焦打字时画面不跳;
7. 打字音随静音键;
8. 接上硬件键盘时留白收回;
9. 划掉应用再打开,正文、光标位置还在;
10. 打开 VoiceOver,能读正文,并报告插入点与选区;
11. 空行上的光标位置正确:在空行(含文末空行)里光标落在行首的正确高度,不偏上、不偏下,也不消失;
12. 接硬件键盘时,⌘Z 撤销、⇧⌘Z 重做都生效;摇一摇撤销也生效;三者的结果与第 3 条的撤销一致,即都经内核;
13. 真实拼音组字时,带下划线的标记文本不被打断(不闪、不被改写、不跳光标),组字过程中不写库,选词上屏后上屏的文字被保存(划掉应用再打开仍在);
14. 打开「减少动态效果」与关闭它各试一次:光标呼吸与聚焦滚动的视觉都对(开启时不呼吸、不做滚动动画,关闭时恢复),两种状态下画面都不跳;
15. 键盘避让:悬浮键盘、拆分键盘、硬件键盘下,插入点都不被键盘遮住,留白随键盘变化并在收起时收回;若在 iPad 台前调度的窗口里使用,同样成立;
16. 打字音:关静音键后有声,开静音键后无声(第 7 条);正在播放音乐时不会被打断,而是混音;按键到出声没有可察觉的延迟;被电话或 Siri 打断后,回到应用继续打字,声音能自动恢复;
17. 设置面板:切换主题、字号、行距、光标样式、音效包,正文立即(实时)生效;划掉应用再打开,这些设置都还在。

## 签名

复制 `Signing.example.xcconfig` 为 `Signing.local.xcconfig`,填自己的团队与 Bundle ID。该文件已被 `.gitignore` 忽略,仓库里不放任何真值。
