# iPhone Duo 半折打字 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iPhone Duo 横着半折时,正文只在折痕以上,折痕以下是系统软键盘的底座;其他机型不变。

**Architecture:** 纯判定 `DeskPosture.foldTop` 决定折痕顶(或 nil)。`DeskObserver`(iOS 27.1+)用 `UIHingeInteraction` 观察转轴,用 `reservedRegions(kind: .division)` 查折痕位置。`EditorController` 依据判定结果切换编辑区底边的约束,并把折痕顶上报给 SwiftUI 外壳画底座。

**Tech Stack:** Swift、UIKit(iOS 27.1 `UIHingeInteraction`、`UIViewReservedRegion`)、SwiftUI、XCTest。

**Spec:** `docs/superpowers/specs/2026-11-21-iphone-duo-desk-design.md`;规范落点 `docs/spec/platform/ios.md` §3.7。

## Global Constraints

- 最低系统仍是 iOS 17;所有 27.1 API 都放在 `@available(iOS 27.1, *)` / `if #available(iOS 27.1, *)` 之后。
- 不按机型名判断;普通 iPhone、iPad 上任何可见行为不变。
- 原有约束 `container.bottom == keyboardLayoutGuide.top` 是普通布局,不改写,只在半折时停用。
- 新文件放 `apps/ios/SumiWrite/Fold/`(`project.yml` 的 `path: SumiWrite` 自动收入)。
- 文档用简体中文;提交信息用英文祈使句,末尾加 Co-Authored-By 行。

## Review Focus

1. 半折时把手机转成竖拿(折痕变竖):应立即回到普通布局 → Task 2 `test_verticalDivisionIsIgnored`。
2. 软键盘比下半屏高:正文底边仍不低于键盘顶边 → Task 3 的 `<=` 必需约束;手工验收第 3 条。
3. 系统拼音组字中开合转轴:组字不断、不丢 → 只改约束,不碰文本;手工验收第 4 条。
4. `viewDidLayoutSubviews` 里重新判定引起布局循环 → Task 3 用 0.5pt 阈值;单测 `test_sameFoldTopDoesNotReapply` 不必加,靠代码审读。
5. 保留区在视图边缘之外或高度为 0 → Task 2 `test_divisionOutsideBoundsIsIgnored`。

---

### Task 1: 规范与验收清单

**Files:**
- Modify: `docs/spec/platform/ios.md`(在 §3.6 之后、`---` 之前加 §3.7)
- Modify: `apps/ios/README.md`(加「iPhone Duo 半折打字手工验收」一组;Verification 段说明 Duo 判定单测)

- [ ] **Step 1:** §3.7「iPhone Duo 半折打字」,状态行 `状态:[计划:iOS]`,内容按设计文档的「设计」一节写成规范口吻,标 **[用户定]** 和 **[我的判断]**。
- [ ] **Step 2:** README 手工验收(只能在 iPhone Duo 真机,或装了 iOS 27 运行时的 iPhone Duo 模拟器上做):
  1. 横拿半折:正文只在折痕以上,键盘弹在下半屏,折痕以下是底座;
  2. 开合转轴、半折时转成竖拿:平滑切换,画面不跳;「减少动态效果」开启时直接到位;
  3. 键盘比下半屏高时,正文不被挡;
  4. 拼音组字中开合转轴,组字不断;
  5. 聚焦打字时当前行在上半屏居中;
  6. 收起键盘后正文仍在上半屏,点正文键盘再弹出;
  7. 普通 iPhone、iPad 上一切照旧。
- [ ] **Step 3:** 运行 `bash docs/check.sh`,期望输出 `OK`。
- [ ] **Step 4:** 提交 `Specify the iPhone Duo half-folded writing layout`(连同设计文档与本计划)。

### Task 2: 纯判定 `DeskPosture`

**Files:**
- Create: `apps/ios/SumiWrite/Fold/DeskPosture.swift`
- Test: `apps/ios/SumiWriteTests/DeskPostureTests.swift`

**Interfaces:**
- Produces: `enum HingeState { case unknown, closed, partiallyOpen, fullyOpen }`;`enum DeskPosture { static func foldTop(hinge: HingeState?, divisions: [CGRect], bounds: CGRect) -> CGFloat? }`。返回值在 `bounds` 所在坐标系。

- [ ] **Step 1:** 写测试(bounds = `CGRect(x: 0, y: 0, width: 1000, height: 700)`,横向折痕 `CGRect(x: 0, y: 340, width: 1000, height: 20)`):
  - `test_partiallyOpenWithHorizontalDivision` → `340`
  - `test_fullyOpenOrClosedIsNil`:`.fullyOpen`、`.closed`、`.unknown`、`nil` 都 → nil
  - `test_verticalDivisionIsIgnored`:`CGRect(x: 490, y: 0, width: 20, height: 700)` → nil
  - `test_noDivisionIsNil`:`[]` → nil
  - `test_divisionOutsideBoundsIsIgnored`:`y: 700` 或 `y: -20`(minY 不在 `(0, 700)` 内)、高度 0 的保留区 → nil
- [ ] **Step 2:** 运行测试,期望编译失败(类型不存在)。
- [ ] **Step 3:** 实现:`hinge == .partiallyOpen`;取第一个 `width > height`、`height > 0`、与 bounds 横向相交、`minY` 严格落在 `(bounds.minY, bounds.maxY)` 内的保留区,返回其 `minY`。
- [ ] **Step 4:** 运行测试,期望通过。随 Task 3 一起提交。

### Task 3: 观察转轴、切换布局、画底座

**Files:**
- Create: `apps/ios/SumiWrite/Fold/DeskObserver.swift`
- Modify: `apps/ios/SumiWrite/Editor/EditorController.swift`(`viewDidLoad` 的约束、`viewDidLayoutSubviews`、`applyPrefs` 之外不动)
- Modify: `apps/ios/SumiWrite/App/ContentView.swift`(`ContentView`、`FailureView` 背景层加底座)

**Interfaces:**
- Consumes: Task 2 的 `HingeState`、`DeskPosture.foldTop`。
- Produces:
  - `@available(iOS 27.1, *) final class DeskObserver { init(view: UIView, onChange: @escaping () -> Void); var hinge: HingeState? { get }; func divisions(in view: UIView) -> [CGRect] }`:把 `UIHingeInteraction` 加到 `view` 上,`update.hinge == nil` 时 `hinge = nil`;`divisions` 返回 `view.reservedRegions(kind: .division)` 中激活项的 `frame`。
  - `EditorController.onDeskChange: ((CGFloat?) -> Void)?`:折痕顶的窗口 y 坐标,离开半折时为 nil。
  - `EditorController.deskFoldTop: CGFloat?`(只读,当前判定结果,编辑面坐标)。

- [ ] **Step 1:** `DeskObserver`:`UIHinge.Status` 映射到 `HingeState`;每次更新调 `onChange`。
- [ ] **Step 2:** `EditorController`:
  - 保留原约束,存为 `keyboardBottom`;另建 `foldBottom`(`container.bottom == view.top + c`,优先级 999)和 `keyboardCap`(`container.bottom <= keyboardLayoutGuide.top`,必需),初始不激活。
  - `viewDidLoad` 末尾:`if #available(iOS 27.1, *) { desk = DeskObserver(view: view) { [weak self] in self?.updateDesk() } }`(属性存为 `AnyObject?`,避免整个类标 availability)。
  - `updateDesk()`:算 `DeskPosture.foldTop`;与当前值差不到 0.5pt 就返回;否则切换三条约束(nil → 只开 `keyboardBottom`;有值 → 关 `keyboardBottom`、开另两条并设 `foldBottom.constant`);`reduceMotion` 时直接 `view.layoutIfNeeded()`,否则 `UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction])` 里 `layoutIfNeeded`;从 nil 变成有值时调 `focusEditor()`;最后 `onDeskChange?(值转成窗口坐标)`。
  - `viewDidLayoutSubviews` 开头调 `updateDesk()`(iOS 27.1 以下为空操作)。
- [ ] **Step 3:** 外壳:`@State private var deskTop: CGFloat?`,在 `onAppear` 里接 `controller.onDeskChange = { deskTop = $0 }`;背景 `ZStack` 里主题底色之上加一层:`deskTop` 有值时,从该 y 到屏幕底的矩形,颜色为 `fg.opacity(0.04)`,`.ignoresSafeArea()`,`.allowsHitTesting(false)`。用 `GeometryReader` 以全局坐标对齐。
- [ ] **Step 4:** 构建并跑全部测试:`bash apps/ios/scripts/test-sim.sh`,期望以 `** TEST SUCCEEDED **` 结束(iOS 26.5 模拟器,证明普通机型不变);再跑 `cargo +1.99.0 test --manifest-path apps/ios/ffi/Cargo.toml`。
- [ ] **Step 5:** `bash docs/check.sh` 输出 `OK` 后提交 `Keep the text above the fold when iPhone Duo is half-folded`。
