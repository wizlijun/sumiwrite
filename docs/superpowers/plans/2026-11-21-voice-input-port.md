# 语音输入移植 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 rapp 的语音输入（按住说话、圆盘三选、气泡、AI 整理卡、实体键盘按住说话）按 rapp 的代码结构搬进新的共享 Swift 包 VoiceKit，并接进 Sumi Write iOS。

**Architecture:** VoiceKit 是本地 Swift 包 `/Users/bruce/git/voice-kit`（与 `rime-kit` 并列，无远端），分两个产品：`VoiceKit`（识别、状态机、几何、整理，不依赖 UI）和 `VoiceKitUI`（UIKit + CALayer 的覆盖层与整理卡）。每个 Swift 文件对应 rapp 的一个文件，名字、顺序、数值照搬。Sumi 只写宿主层：底栏麦克风、落地路径、右 ⌥、设置行。

**Tech Stack:** Swift 5.9 包，iOS 17+；Speech（iOS 26+ 用 SpeechAnalyzer，17–25 用 SFSpeechRecognizer）、AVFoundation、URLSession 流式请求、UIKit/CALayer；Sumi 侧为 SwiftUI 外壳加 UIKit 编辑面，工程由 XcodeGen `apps/ios/project.yml` 生成。

**Spec:** `docs/superpowers/specs/2026-11-21-voice-input-port-design.md`（下文称「设计」）。rapp 源码只读：`/Users/bruce/git/rapp`。调研底稿：`/Users/bruce/git/sumiwrite-ios/.superpowers/voice-port/rapp-voice-survey.md`。

## Global Constraints

- **对齐 rapp（用户原话「注意代码和它对齐」）。** 每个任务先通读对应的 rapp 文件，再按它的结构写 Swift：
  - 类型、方法、常量、枚举成员照用 rapp 的名字，例如 `VoicePick.send/.edit/.cancel`、`VoicePhase`、`VoiceStart`、`TidyPhase`、`VoiceKeyPhase.edit`；
  - 声明顺序跟 rapp 文件一致；
  - 数值照抄，并在注释里写出处，例如 `// voice_ring.dart _segment`；
  - rapp 里跟 Flutter、输入板、会话、热词、历史有关的部分不搬，在原处留一行注释说明去向。
- **「原话」只是宿主层的叫法。** VoiceKit 里不出现「原话」；标签和提示文案由宿主通过 `VoiceStyle` 传入。
- **LLM 接入点先不填（用户原话「LMM 的地址先不填」）。** 代码和设置行都要做；默认值是空的 url 和空的 key。接入点为空时 `LlmEndpoint.configured == false`，不整理，直接插原话。不得写入任何真实地址或 key。
- **部署与环境。**
  - 部署目标 iOS 17.0；SpeechAnalyzer 用 `if #available(iOS 26, *)` 包住。
  - VoiceKit 用 `swift-tools-version: 5.9`，`platforms: [.iOS("17.0")]`。
  - 不引入第三方依赖。
- **红线。**
  - 不改 rapp、`~/git/note.md`、`apps/notemd-plugin/`、Rust 内核。
  - 语音结果只走 `UITextView` 编辑路径落地，不直接改内核（AGENTS.md 红线 4）。
- **凭据。**
  - Bundle ID、签名值不进任何入库文件。
  - LLM key 只存钥匙串（`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`），不进 UserDefaults、不进日志。
- **文案与语言。**
  - 文档用简体中文；提交信息用英文祈使句，末尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
  - 界面文案逐字取自设计 §6，例如「松手 插入」「没听清」「需要麦克风和语音识别权限」「去设置」「已用 AI 整理」「先填写接入点和 key」。
- **测试从简**（用户：「不要过度的测试了」）。每个任务只写下面列出的测试，不加矩阵、不做性能测量。
- **验证命令。**
  - VoiceKit：`cd /Users/bruce/git/voice-kit && xcodebuild test -scheme VoiceKit-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' -quiet`，退出码 0 即通过。
  - Sumi：`cd /Users/bruce/git/sumiwrite-ios && bash apps/ios/scripts/test-sim.sh`，必须以 `** TEST SUCCEEDED **` 结束。
  - 文档：`bash docs/check.sh`，必须输出 `OK`。
- **工具链与提交。**
  - 先执行 `export PATH="$HOME/.cargo/bin:$PATH"`。
  - 不要 `git add -f`，不提交 `.superpowers/`，不 push。

## Review Focus

1. **说话中被打断。** 来电、退到后台、音频路由变化（AirPods 接入）时：什么都不插入，覆盖层收起，音频会话还给打字音。测试见 Task 3（`interrupt` 不落地）和 Task 5（场景退到后台时调用 `cancel`）。
2. **按下麦克风时内置 Rime 正在组字。** 组字先按原文上屏，不丢。测试见 Task 5。
3. **接入点为空。** 长语音也不出现整理卡，松手立刻插入原话。测试见 Task 8。
4. **上一段还没结束又按下。** 包括 finishing 和整理卡还在的时候。新的按下被忽略，不会插入两次。测试见 Task 3（非 idle 时 `down` 无效）和 Task 7（整理中 `begin` 先落地上一段）。
5. **权限被拒绝。** 不录音，提示带「去设置」；授权后再按能正常开始。测试见 Task 2（`.denied`）。

---

### Task 1: 规范 §3.7、VoiceKit 骨架、SpeechLocale、VoiceKeyGate

**Files:**
- Modify: `docs/spec/platform/ios.md`
  - 加 §3.7「语音输入」，状态行 `[计划:iOS]`，内容是设计 §6 的行为摘要；
  - 在 §1「做」加一条语音输入，标 [用户定] 2026-11-21，附用户原话。
  - 状态行写法照文件里已有小节。
- Create（新仓库 `/Users/bruce/git/voice-kit`，先 `git init -b main`）：
  - `Package.swift`：产品 `VoiceKit`、`VoiceKitUI`；测试目标 `VoiceKitTests`、`VoiceKitUITests`；
  - `README.md`：用途、与 rapp 的文件对照（抄设计 §5 的表）、Verification 段写上面的 VoiceKit 命令；
  - `.gitignore`：`.build/`、`.swiftpm/`。
- Create:
  - `Sources/VoiceKit/Speech/SpeechLocale.swift`，搬 rapp `Sources/RappSession/SpeechLanguage.swift`；
  - `Sources/VoiceKit/Keys/VoiceKeyGate.swift`，搬 rapp `Sources/RappSession/VoiceKeyGate.swift`；
  - `Sources/VoiceKit/Keys/HIDKeyCodes.swift`；
  - `Sources/VoiceKitUI/VoiceStyle.swift`（先放空壳类型，让产品能编译）。
- Test:
  - `Tests/VoiceKitTests/SpeechLocaleTests.swift`，搬 rapp `Tests/*/SpeechLanguageTests.swift` 的全部用例；
  - `Tests/VoiceKitTests/VoiceKeyGateTests.swift`，搬 rapp `VoiceKeyGateTests.swift` 的共享用例表。

**Interfaces:**
- Produces:
  - `SpeechLocale`：API 与 rapp `SpeechLanguage` 同名同签名。
  - `VoiceKeyGate`、`VoiceGateInput`、`VoiceGateStep`、`VoiceKeyPhase { start, release, cancel, edit }`、`VoiceHotkey`（含 `.standard = holdModifier(61)`）：成员与 rapp Swift 版一致，仍用 mac 虚拟键码和 mac 修饰位。
  - `public enum HIDKeyCodes { public static func mac(_ usage: UIKeyboardHIDUsage) -> Int? }`：至少覆盖左右 Shift/Control/Option/Command、CapsLock、Esc（53）、Tab（48）。其他键返回 `nil`，宿主当作「普通键」处理。注释写明 `UIKeyModifierFlags` 的位与 mac 相同，可直接作为 flags 传入。
  - `public struct VoiceStyle`（Task 4 补全）。

- [ ] **Step 1:** 先改 `ios.md`，在 sumiwrite-ios 跑 `bash docs/check.sh`，应输出 `OK`。然后提交：`git commit -m "Specify voice input for iOS"`。
- [ ] **Step 2:** 建 voice-kit 仓库和 `Package.swift`，把 rapp 的两组测试原样搬成 XCTest，并加一条 `XCTAssertEqual(HIDKeyCodes.mac(.keyboardRightAlt), 61)`。运行 VoiceKit 验证命令，应因缺类型而编译失败。
- [ ] **Step 3:** 按 rapp 原文搬 `SpeechLocale`、`VoiceKeyGate`，再写 `HIDKeyCodes`。
- [ ] **Step 4:** 运行 VoiceKit 验证命令，应通过。
- [ ] **Step 5:** 在 voice-kit 提交：`git commit -m "Port the speech locale picker and the voice key gate from rapp"`。

### Task 2: 识别引擎、音频采集、权限、VoiceInput

**Files:**
- Create:
  - `Sources/VoiceKit/Speech/SpeechEngine.swift`：协议和事件类型；
  - `AnalyzerEngine.swift`、`RecognizerEngine.swift`、`AudioCapture.swift`、`SpeechPermissions.swift`：搬 rapp `gui/macos/Runner/SpeechPlugin.swift`，拆成四个文件，去掉 Flutter 通道；
  - `Sources/VoiceKit/VoiceInput.swift`：搬 `gui/lib/embed/voice_input.dart`。
- Test: `Tests/VoiceKitTests/VoiceInputTests.swift`，用假引擎和假权限。

**Interfaces:**
- Consumes: Task 1 的 `SpeechLocale`。
- Produces:
  - `public enum VoiceEvent { case partial(String), final(String), level(Double), failed(String) }`。
  - `public protocol SpeechEngine: AnyObject { func start(locale: Locale) async throws -> AsyncStream<VoiceEvent>; func finish(); func cancel() }`。
  - `public final class SystemSpeechEngine: SpeechEngine`：iOS 26+ 用 `AnalyzerEngine`，否则用 `RecognizerEngine`。
    - 支持端侧时设 `requiresOnDeviceRecognition = true`。
    - `AudioCapture` 用 `AVAudioEngine` 的 tap，bufferSize 1024。只在说话期间把会话设为 `.record` / `.measurement`；结束时用 `.notifyOthersOnDeactivation` 停用会话。
    - 监听 `AVAudioSession.interruptionNotification` 和 `routeChangeNotification`，触发时发 `.failed("interrupted")`。
  - `public protocol SpeechPermissions { func status() -> SpeechAuth; func request() async -> SpeechAuth }`，其中 `public enum SpeechAuth { case granted, denied, undetermined }`。`SystemSpeechPermissions` 先请求语音识别，再请求麦克风。
  - `public enum VoiceStart { case ok, asked, denied, unavailable, preparing, cancelled }`；`public enum VoicePhase { case idle, starting, listening, finishing }`。
  - `@MainActor public final class VoiceInput: ObservableObject`：
    - 发布属性：`phase`、`text`、`level: Double`；
    - 初始化：`init(engine: SpeechEngine, permissions: SpeechPermissions, finalWait: Duration = .seconds(1), maxLength: Duration = .seconds(60))`；
    - 回调：`var onMaxLength: (() -> Void)?`、`var onInterrupted: (() -> Void)?`、`var restoreAudio: (() -> Void)?`，后者在每次会话结束后调用；
    - 方法：`func start() async -> VoiceStart`、`func stop() async -> String`、`func cancel() async`。
    - 语义照 `voice_input.dart`。例如权限未定时，`start` 只请求授权并返回 `.asked`，不录音。

- [ ] **Step 1:** 写测试：
  - `testStopReturnsFinal`：假引擎发 partial「你」、final「你好」，`stop()` 返回「你好」，`phase == .idle`；
  - `testStopFallsBackToLastPartial`：引擎不发 final，`finalWait` 设成 0.1 s，`stop()` 返回最后一个 partial；
  - `testUndeterminedOnlyAsks`：权限未定时 `start()` 返回 `.asked`，引擎的 `start` 没被调用；
  - `testDenied`：权限已拒绝时返回 `.denied`；
  - `testMaxLength`：`maxLength` 0.2 s 后 `onMaxLength` 被调用。
- [ ] **Step 2:** 运行 VoiceKit 验证命令，应编译失败。
- [ ] **Step 3:** 实现上面这些文件，`SpeechPlugin.swift` 里的每个方法都在新文件里有对应。
- [ ] **Step 4:** 运行 VoiceKit 验证命令，应通过。
- [ ] **Step 5:** 提交：`git commit -m "Port speech recognition and the voice input state machine from rapp"`。

### Task 3: VoiceRing 与 VoiceHold

**Files:**
- Create:
  - `Sources/VoiceKit/VoiceRing.swift`，搬 `gui/lib/embed/voice_ring.dart`；
  - `Sources/VoiceKit/VoiceHold.swift`，搬 `gui/lib/embed/voice_button.dart` 里的 `VoiceHold` 和文案常量。
- Test: `Tests/VoiceKitTests/VoiceRingTests.swift`、`VoiceHoldTests.swift`。

**Interfaces:**
- Consumes: Task 2 的 `VoiceInput`、`VoiceStart`；Task 1 的 `VoiceKeyPhase`。
- Produces:
  - `public enum VoicePick { case send, edit, cancel }`。
  - `public struct VoiceRing`：
    - `init(thumb: CGPoint, stage: CGSize, right: Bool)`；
    - 属性：`center: CGPoint`、`radius: CGFloat`；
    - 方法：`pick(_: CGPoint) -> VoicePick`、`segment(_: VoicePick, sweep: CGFloat = 1) -> CGPath`、`labelAt(_: VoicePick) -> CGPoint`、`probe(_: VoicePick) -> CGPoint`；
    - 数值照 `voice_ring.dart`。
  - 文案常量与 rapp 同名：`voiceBlank`、`voiceDenied`、`voicePreparing`、`voiceUnavailable`、`voiceLanguageHint`。`linux*`、`voiceBlocked`、`voiceBusy` 不搬，留注释说明。
  - `public enum VoiceSettings { case none, privacy, language }`。
  - `@MainActor public protocol VoiceSink: AnyObject`：
    - `func voiceWillStart() -> String?`：宿主先把组字上屏；返回 nil 表示可以开始，否则返回拒绝提示；
    - `func voiceInsert(_ text: String, pick: VoicePick)`：只会收到 `.send` 或 `.edit`；
    - `func voiceNotice(_ text: String, settings: VoiceSettings)`；
    - `func voiceDidEnd(_ pick: VoicePick?)`。
  - `@MainActor public final class VoiceHold: ObservableObject`：
    - 发布属性：`active: Bool`、`keyboard: Bool`、`pick: VoicePick`、`hint: String?`、`ring: VoiceRing?`。
    - 初始化：`init(voice: VoiceInput, sink: VoiceSink, pauseFor: Duration = .milliseconds(800))`。
    - 可选闭包，名字与 rapp 一致：`tidy: ((String, VoicePick) -> Bool)?`（返回 true 表示整理接管了落地）、`wouldTidy: ((String) -> Bool)?`、`prefetch: ((String?) -> Void)?`、`languageHintDue: (() -> Bool)?`、`languageHintShown: (() -> Void)?`。
    - 手指操作：`down(thumb:stage:right:) async`、`move(to: CGPoint)`、`up() async`。
    - 键盘操作：`keyDown() async` 开始说话，不生成 ring；`keyUp(_ phase: VoiceKeyPhase) async`，其中 `.release` 等于 send，`.cancel` 等于 cancel，`.edit` 等于 edit。
    - 打断：`interrupt()`，等于取消。
    - 每次切换 pick 时轻震一下（`UISelectionFeedbackGenerator`），按下时中等震一下。

- [ ] **Step 1:** 写测试：
  - `testRingPicks`：`ring.pick(ring.probe(x)) == x`，覆盖三种 pick，左右各一次；
  - `testReleaseOnEditInsertsRaw`：假 sink 加假引擎；`down` 后 `move(to: ring.probe(.edit))` 再 `up`，sink 收到 `voiceInsert("你好", pick: .edit)`；
  - `testReleaseOnCancelInsertsNothing`；
  - `testBlankNotice`：结果为空时 sink 收到 `voiceBlank`；
  - `testRefusedStart`：`voiceWillStart` 返回「请先完成输入」时，sink 收到这条提示，引擎没有启动；
  - `testInterruptInsertsNothing`；
  - `testDownIgnoredWhileBusy`：phase 不是 idle 时，`down` 不再触发 `voiceWillStart`。
- [ ] **Step 2:** 运行 VoiceKit 验证命令，应编译失败。
- [ ] **Step 3:** 实现这两个文件。
- [ ] **Step 4:** 运行 VoiceKit 验证命令，应通过。
- [ ] **Step 5:** 提交：`git commit -m "Port the voice ring and the hold-to-talk state machine from rapp"`。

### Task 4: VoiceKitUI 覆盖层

**Files:**
- Create:
  - `Sources/VoiceKitUI/VoiceStyle.swift`：补全；
  - `Sources/VoiceKitUI/VoiceOverlayView.swift`：搬 `gui/lib/embed/voice_overlay.dart` 的 `_VoiceOverlayState`、`VoiceRingPainter`；
  - `VoiceBarsLayer.swift`：搬 `VoiceBarsPainter`；
  - `VoiceBubbleView.swift`：搬 `VoiceBubbleFrame` 和 `_bubble`、`_tailOf`。
- Test: `Tests/VoiceKitUITests/VoiceOverlayTests.swift`。

**Interfaces:**
- Consumes: Task 3 的 `VoiceHold`、`VoiceRing`、`VoicePick`；Task 2 的 `VoiceInput`。
- Produces:
  - `public struct VoiceStyle`：
    - 字段：`foreground: UIColor`、`background: UIColor`、`font: UIFont`、`labels: [VoicePick: String]`、`hints: [VoicePick: String]`、`keyboardHint: String`、`listening: String`（默认「正在听…」）、`reduceMotion: Bool`；
    - 外观照设计 §6.2：选中段前景色填满、字用背景色，未选中段前景色 8% 渐隐；遮罩是背景色 60%；
    - 气泡三种样子：insert 实心，edit 描边加小标签（标签文字取 `labels[.edit]`），cancel 整体 40%、音量条压平。
  - `public final class VoiceOverlayView: UIView`：
    - `init(hold: VoiceHold, voice: VoiceInput, style: VoiceStyle)`；`var style: VoiceStyle`，可以改，用于主题切换；
    - `isUserInteractionEnabled = false`。宿主把它铺满窗口、放在最上层；它自己订阅 hold 和 voice 并重画。
    - `hold.keyboard == true` 时不画圆盘和环带，只画气泡，气泡底部离窗口底 64 pt，提示行用 `keyboardHint`。
    - 时长 240/200 ms、24 根音量条、尾巴 6 pt、气泡最多 4 行并只显示末尾，全部照 rapp。
    - `reduceMotion` 时不做动画。

- [ ] **Step 1:** 写测试 `testOverlayRendersEveryPick`：用假引擎驱动一个 hold，分别处于 send / edit / cancel 和键盘模式，在 390×844 上 `layoutIfNeeded` 后用 `UIGraphicsImageRenderer` 渲染，不崩溃。把四张 PNG 写到 `FileManager.default.temporaryDirectory/voice-overlay-*.png`，并在报告里列出路径，供控制者目测。
- [ ] **Step 2:** 运行 VoiceKit 验证命令，应编译失败。
- [ ] **Step 3:** 实现这几个文件。
- [ ] **Step 4:** 运行 VoiceKit 验证命令，应通过；对照设计 §6.2 和 `.superpowers/voice-port/mockups.html` 目测 PNG。
- [ ] **Step 5:** 提交：`git commit -m "Port the voice overlay from rapp"`。

### Task 5: 接入 Sumi（麦克风按钮与落地）

**Files:**
- Modify:
  - `apps/ios/project.yml`：加包 `VoiceKit`，`path: ../../../voice-kit`，产品 `VoiceKit` 和 `VoiceKitUI`；Info.plist 属性 `NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`，文案取自设计 §6.5。
  - `apps/ios/SumiWrite/Editor/EditorController.swift`：
    - `func voiceWillStart() -> String?`：系统输入法组字中返回「请先完成输入」，纸页不可写时返回「这一页现在不能写」，否则先 `prepareToSwitch()`（Rime 组字上屏）再返回 nil；
    - `func insertVoice(_ text: String)`：走与 `paste(_:)` 相同的路径，不播打字音，之后执行 `revealCaret()`；
    - `var voiceAvailable: Bool`：纸页可写为 true。
  - `apps/ios/SumiWrite/App/ContentView.swift`：
    - 底栏右端放麦克风按钮，44×44，`mic` 图标，17pt light。透明度和打字时隐藏的规则与「···」相同；`voiceAvailable == false` 时变灰、不响应。
    - 用 `DragGesture(minimumDistance: 0, coordinateSpace: .global)` 驱动 `down` / `move` / `up`。
    - 提示条支持一个可选按钮「去设置」，此时显示 4 s。
    - `scenePhase` 不是 `.active` 时调用 `voiceHost.hold.interrupt()`。
    - 加 VoiceOver 动作：双击开始，再双击结束。
  - `apps/ios/SumiWrite/Sound/TypingSound.swift`：加 `func reclaimSession()`，重新配置 `.playback` + `.mixWithOthers` 并重启播放器。
  - `apps/ios/README.md`：一次性准备里加 voice-kit 的路径。
- Create: `apps/ios/SumiWrite/Voice/VoiceHost.swift`，以及 `Voice/VoiceStyle+Theme.swift`（从 `Theme` 和当前字体生成 `VoiceStyle`）。
- Test: `apps/ios/SumiWriteTests/VoiceLandingTests.swift`。

**Interfaces:**
- Consumes: Task 2–4 的全部公开类型。
- Produces:
  - `@MainActor final class VoiceHost: VoiceSink, ObservableObject`：
    - 初始化：`init(controller: EditorController, prefs: PrefsModel, engine: SpeechEngine = SystemSpeechEngine(), permissions: SpeechPermissions = SystemSpeechPermissions())`；
    - 属性：`hold`、`voice`、`var onNotice: ((String, VoiceSettings) -> Void)?`；
    - 方法：`attach(to window: UIWindow)`，挂上 `VoiceOverlayView`。
    - 标签：send「插入」、edit「原话」、cancel「取消」；提示：「松手 插入」「松手 插入原话」「松手 取消」。
    - 语言提示只出一次，记在 UserDefaults 键 `voice.languageHintShown`。
    - `voice.restoreAudio` 调 `TypingSound.reclaimSession()`。
    - `VoiceSettings.privacy` 和 `.language` 都打开 `UIApplication.openSettingsURLString`。

- [ ] **Step 1:** 写测试，用 `SumiWriteTests` 里已有的假 Rime 和假引擎：
  - `testRimeCompositionCommitsBeforeVoice`：Rime 组字「ni」时 `voiceWillStart()` 返回 nil，组字原文已进入正文；
  - `testVoiceLandsInPage`：`insertVoice("你好")` 后 `page.body()` 含「你好」，一次撤销后不含；
  - `testSystemCompositionRefuses`：有系统 marked text 时返回「请先完成输入」。
- [ ] **Step 2:** 运行 Sumi 验证命令，应编译失败。
- [ ] **Step 3:** 实现上述改动。
- [ ] **Step 4:** 运行 Sumi 验证命令，应以 `** TEST SUCCEEDED **` 结束。
- [ ] **Step 5:** 提交：`git commit -m "Add hold-to-talk voice input to the page"`。

### Task 6: 实体键盘长按右 ⌥

**Files:**
- Modify:
  - `apps/ios/SumiWrite/Appearance/EditorPrefs.swift`：加 `var voiceKey: Bool = true`，旧存档解码时缺这个字段取默认值。
  - `apps/ios/SumiWrite/Editor/EditorController.swift`：按键入口 `unhandled(_:began:)` 和 `SumiTextView.pressesBegan/Ended`。
    - 在 Rime 之前把按键交给 `VoiceKeyGate`：键码经 `HIDKeyCodes.mac` 转换，flags 用 `key.modifierFlags.rawValue`，`elapsed` 由 0.3 s 计时器喂入，跟 rapp `voice_hotkey.dart` 的驱动方式一样。
    - gate 吞掉的键不再往下传。
    - `voiceKey == false` 或纸页不可写时，跳过 gate。
  - `apps/ios/SumiWrite/App/AppearanceView.swift`：「输入法」一节加开关「按住右 ⌥ 说话」。
- Modify: `VoiceHost`：
  - gate 给出 `.start` 时调 `hold.keyDown()`，给出 `.release` / `.cancel` / `.edit` 时调 `hold.keyUp(_)`；
  - `keyboardHint` 为「松开 ⌥ 插入 · Esc 取消 · Tab 原话」。
- Test: 加到 `VoiceLandingTests.swift`。

**Interfaces:**
- Consumes: Task 1 的 `VoiceKeyGate`、`HIDKeyCodes`；Task 3 的 `keyDown` / `keyUp`。
- Produces: `EditorController.voiceKeys: VoiceKeyGate`（内部用）。

- [ ] **Step 1:** 写测试 `testRightOptionHoldStartsAndTabInsertsRaw`：假引擎在 final 给出「你好」；送入右 ⌥ 按下，推进 elapsed 0.3 s，`hold.active` 为 true；再送入 Tab，正文得到「你好」，且 Tab 没有插入制表符。另写一条：`voiceKey = false` 时，右 ⌥ 不启动。
- [ ] **Step 2:** 运行 Sumi 验证命令，应失败。
- [ ] **Step 3:** 实现。
- [ ] **Step 4:** 运行 Sumi 验证命令，应以 `** TEST SUCCEEDED **` 结束。
- [ ] **Step 5:** 提交：`git commit -m "Hold the right Option key to talk"`。

### Task 7: AI 整理核心（LlmApi、VoiceTidy、TidyHeld）

**Files:**
- Create（voice-kit）：
  - `Sources/VoiceKit/Tidy/LlmApi.swift`：搬 `gui/lib/llm_api.dart` 的 `LlmEndpoint`、`normalizeLlmUrl`、`LlmResult`（`done` / `failed(reason:log:)` / `cancelled`）、`LlmCall`、`LlmApi.run`、`_statusReason`、`_errorCode`。`probe`、`hotwords`、`load` / `save` 不搬，留注释说明。
  - `Sources/VoiceKit/Tidy/VoiceTidy.swift`：搬 `gui/lib/embed/voice_tidy.dart`。
  - `Sources/VoiceKit/Tidy/TidyHeld.swift`：搬 `gui/lib/embed/tidy_held.dart`，写文件时用 `.completeFileProtection`。
- Test: `Tests/VoiceKitTests/LlmApiTests.swift`、`VoiceTidyTests.swift`。

**Interfaces:**
- Produces:
  - `public struct LlmEndpoint: Equatable { url: String; key: String; var configured: Bool; var base: String? }`；`public func normalizeLlmUrl(_: String) -> String?`；`public let llmUrlHint = "http://localhost:28001"`。
  - `public final class LlmCall { var result: LlmResult { get async }; func cancel() }`。
  - `public struct LlmApi`：
    - 初始化：`init(session: URLSession = .shared)`；
    - 方法：`func run(_ e: LlmEndpoint, _ app: String, _ input: String, think: Bool = false, firstByte: Duration = .seconds(10), onText: (@MainActor (String) -> Void)? = nil) -> LlmCall`。
    - 请求为 `POST {base}/v1/apps/{app}`，头 `Authorization: Bearer {key}`，body `{"input": …, "stream": true}`；用 `URLSession.bytes` 流式读取。
  - `public let tidyApp = "dictation"`；`public enum TidyPhase { case idle, tidying, ready, note }`；`public struct VoiceAi { app, original, result }`。
  - `@MainActor public final class VoiceTidy: ObservableObject`：
    - 构造参数与 rapp 对应：`endpoint: () -> LlmEndpoint`、`api: LlmApi`、`allowed: (AnyHashable) -> Bool`、`think: () -> Bool = { false }`、`edit: (AnyHashable, String, VoiceAi?) -> Void`、`keep: (AnyHashable, String) -> Void`、`overall = 30 s`、`settle = 1.5 s`、`revealRate`、`revealMax`（取 rapp 值）、`held: ((AnyHashable, String?) -> Void)?`；
    - 发布属性：`phase`、`original`、`shown`、`note`、`pick`；
    - `static func long(_: String) -> Bool`：去掉空白后多于 10 个字符；
    - 公开方法名与 rapp 一一对应（开始整理、预取、立即落地、还原、展开对比、放弃）。实现者照 rapp 取名，并在 Task 7 报告里列出最终签名，供 Task 8 使用。

- [ ] **Step 1:** 写测试，HTTP 用自定义 `URLProtocol` 打桩：
  - `testNormalizeLlmUrl`：`localhost:28001/` 得 `http://localhost:28001`，空串得 nil，`ftp://x` 得 nil；
  - `testRunStreamsAndFinishes`：桩分两块返回「下午」「三点」；`onText` 依次收到「下午」「下午三点」，结果为 `.done("下午三点")`；
  - `testRunUnauthorized`：401 得 `.failed`，reason 为「LLM 接入点的 key 不对」；
  - `testRunWithoutEndpoint`：空 endpoint 得 `.failed`，reason 为「没有设置 LLM 接入点」，且没有发出请求；
  - `testLong`：10 个字为 false，11 个字为 true，空白不计；
  - `testTidyLandsWithAi`：成功后 phase 经过 tidying、ready，过了 settle 时间后 `edit` 收到整理结果和非 nil 的 `VoiceAi`；
  - `testTidyFailureKeepsOriginal`：失败时 `edit` 收到原话，ai 为 nil；
  - `testHeldRoundTrip`：TidyHeld 写入后能取回，取一次后消失。
- [ ] **Step 2:** 运行 VoiceKit 验证命令，应编译失败。
- [ ] **Step 3:** 实现这三个文件。
- [ ] **Step 4:** 运行 VoiceKit 验证命令，应通过。
- [ ] **Step 5:** 提交：`git commit -m "Port the LLM client and voice tidy from rapp"`。

### Task 8: 整理卡、Sumi 整理接线与设置

**Files:**
- Create（voice-kit）：`Sources/VoiceKitUI/TidyCardView.swift`，搬 `gui/lib/embed/voice_tidy_card.dart`。
  - 包括微光 1400 ms、光标 1000 ms、倒计时条、状态行和按钮。
  - 文案经 `VoiceStyle` 新增的字段传入：`tidying`「AI 整理中…」、`readySoon`「整理好了，马上插入」、`ready`「整理好了」、`restore`「还原」、`insert`「插入」、`insertNow`「直接插入」、`originalPrefix`「原话 · 」。
- Modify（Sumi）：
  - `EditorPrefs`：加 `var voiceTidy: Bool = true`。
  - Create `apps/ios/SumiWrite/Voice/TidyEndpointStore.swift`：url 存 UserDefaults 键 `voice.llm.url`；key 存钥匙串 service `voice.llm.key`。两者默认都为空。
  - `VoiceHost`：
    - 建 `VoiceTidy`，`endpoint` 读 `TidyEndpointStore`；
    - `wouldTidy`：`prefs.voiceTidy && endpoint.configured && VoiceTidy.long(text)`；
    - `edit` 有 ai 时分两步落地，先 `insertVoice(original)`，再 `controller.replaceVoice(original:with:)`，然后提示「已用 AI 整理」1.5 s；
    - 整理卡挂在覆盖层同一窗口；
    - `TidyHeld` 目录用 Application Support 下的 `voice-held`，key 用页 id。下次启动时，若有残留，把原话追加到那一页末尾，并提示「上次没插入的语音已放回本页末尾」。
  - `EditorController`：
    - `func replaceVoice(original: String, with text: String)`：只替换刚插入的那一段，走编辑路径，单独构成一步撤销；
    - 整理中按任意键时，先调 tidy 的立即落地（插原话），然后照常处理这个键。
  - `AppearanceView`：「输入法」一节加三行：
    - 「长语音先让 AI 整理」开关，说明「超过 10 个字时，先发给下面填的接入点整理再插入」；
    - 「接入点」TextField，占位 `llmUrlHint`；
    - 「key」SecureField。
    - 接入点未填好时开关变灰，并说明「先填写接入点和 key」。
  - `project.yml` 的 Info.plist：`NSLocalNetworkUsageDescription`「连接你在设置里填写的 AI 整理接入点」；`NSAppTransportSecurity.NSAllowsLocalNetworking = true`。
- Test: 加到 `VoiceLandingTests.swift`。

**Interfaces:**
- Consumes: Task 7 的 `VoiceTidy`、`LlmEndpoint`、`LlmApi`、`TidyHeld`，以及 Task 7 报告里列出的方法签名。

- [ ] **Step 1:** 写测试：
  - `testEmptyEndpointInsertsRawImmediately`：接入点为空，说了 20 个字、选插入，正文立即得到原话，`tidy.phase == .idle`；
  - `testTidyTwoStepUndo`：用 `URLProtocol` 桩给出整理结果；落地后正文是整理文本，撤销一次回到原话，再撤销一次两者都不在。
- [ ] **Step 2:** 运行 Sumi 验证命令，应失败。
- [ ] **Step 3:** 实现上述改动。
- [ ] **Step 4:** 运行 VoiceKit 和 Sumi 两条验证命令，均应通过。
- [ ] **Step 5:** 两个仓库各自提交：voice-kit 用 `git commit -m "Port the tidy card from rapp"`；Sumi 用 `git commit -m "Tidy long dictation through the LLM gateway when one is set"`。

### Task 9: 文档与真机清单

**Files:**
- Modify:
  - `docs/spec/platform/ios.md` §3.7：状态行改为文件里已有的「已实现、待真机验收」一类写法；证据链接指向 `VoiceLandingTests.swift` 和 voice-kit 测试。写不出出处的标 `[未定]`。
  - `apps/ios/README.md`：
    - Verification 段的测试说明加语音一句；
    - 手工验收加「语音输入」清单：按住三选、Rime 组字上屏、AirPods 中途接入取消、拒绝权限后「去设置」、右 ⌥ / Esc / Tab、接入点空着时直接插入、打字音在语音后仍响。
  - `docs/handoff/04-known-gaps.md`：如果有已知缺口，比如端侧整理未做，就加一条。
- [ ] **Step 1:** 改文档，跑 `bash docs/check.sh`，应输出 `OK`。
- [ ] **Step 2:** 提交：`git commit -m "Document voice input and its device checklist"`。
