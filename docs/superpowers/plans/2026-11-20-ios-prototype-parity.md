# iOS Prototype Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the formal iOS app (`apps/ios`) behave exactly like the 「玄霜试做」 prototype. That covers multiple pages, the overview and trash, the bottom menu bar, the settings sheet, toasts, hardware-keyboard commands, two bundled fonts and the prototype cursor. Page data must go through the Rust core catalog over FFI.

**Architecture:**
- `CoreStore` gains catalog calls: `pages`, `createPage`, `setDeleted`, plus migration on `open`. All order, trash state, summary and modified-time logic stays in Rust.
- A Swift `PageLibrary` forwards those calls and publishes the result with the prototype `PageStore` interface.
- `EditorController` is restructured after the prototype `EditorViewController` and becomes able to switch pages. It keeps the existing `PageModel` → `PagePersistence` write path.
- A SwiftUI `ContentView` ported from the prototype replaces `EditorShell` and `SettingsView`.

**Tech Stack:** Rust 1.99.0 + UniFFI 0.32.2 (`apps/ios/ffi`), Swift 5 / UIKit TextKit 2 / SwiftUI, XcodeGen, XCTest. Deployment target is iOS 17.0.

**Spec:** `docs/superpowers/specs/2026-11-20-ios-prototype-parity-design.md`. Prototype source: `~/git/sumiwrite-ios-spike/SumiSpike/` (`ContentView.swift`, `Editor.swift`, `Prefs.swift`, `PageStore.swift`, `Resources/Fonts`). Treat the prototype as read-only reference. "Copy verbatim" means the prototype's code for that item, adapted only where the spec §6 table says the formal app wins.

## Global Constraints

- Work in `/Users/bruce/git/sumiwrite-ios`, branch `ios-m0-m1`.
  - Don't push, merge or tag.
  - Don't touch `apps/notemd-plugin/`, `~/git/note.md` or the prototype directory.
- Toolchain:
  - Run `export PATH="$HOME/.cargo/bin:$PATH"` first.
  - Use Rust `cargo +1.99.0`, `SWIFT_VERSION 5.0`, deployment target iOS 17.0.
  - APIs newer than 17 need `#available`.
- Red line (AGENTS.md §4): no CRDT, line-time, merge, recovery, page-order, trash-state, summary or modified-time computation in Swift.
- Spec first (AGENTS.md §1).
  - Doc edits are in Simplified Chinese.
  - Every touched spec section keeps its status line.
  - `bash docs/check.sh` must print `OK`.
- Credentials (AGENTS.md §5): no bundle IDs, team IDs or signing values in committed files. Real values live only in the gitignored `apps/ios/Signing.local.xcconfig`.
- Module tests before every commit that touches code:
  - `bash apps/ios/scripts/test-sim.sh` must end with `** TEST SUCCEEDED **`.
  - `cargo +1.99.0 test --manifest-path apps/ios/ffi/Cargo.toml` must pass.
  - If `core/` changes, also run the three commands in `core/README.md` «Verification».
- Keep the formal app's fixes (spec §6):
  - core deltas and core undo;
  - CR/CRLF → LF;
  - caret-anchored `EditDiff`;
  - ambient `TypingSound` with its restart, rebuild and idle behaviour;
  - read-only after a save failure;
  - `writingToolsBehavior = .limited`;
  - the formal `caretRect` (a superset of the prototype's).
- Commit messages are English imperative sentences and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never `git add -f`; never commit `.superpowers/`.
- Code comments follow the existing style (short, Simplified Chinese).

## Review Focus

1. **Upgrading the M1 build already installed on the Duo.**
   - Situation: `page.sqlite3` has one page in `documents` and no catalog.
   - Expected: the text survives, it becomes page 1/1, and the saved caret is restored.
   - Tests: Task 1 `open_adopts_pages_missing_from_catalog`; Task 3 `test_opensMigratedSinglePage`.
2. **Trashing the only live page, or the last one.**
   - Expected: a new blank page becomes current. Restoring puts the old page back in its old slot, not at the end.
   - Tests: Task 3 `test_trashOnlyPageCreatesBlank` and `test_restoreReturnsToOriginalSlot`.
3. **Typing right after a page switch.**
   - Expected: the deltas land in the new page; the old page's last keystrokes are not lost or cross-written.
   - Test: Task 4 `test_switchThenTypeWritesBothPages`.
4. **⌘]/⌘N or a menu tap while composing pinyin.**
   - Expected: no switch and the toast 「请先完成输入」. The marked text stays.
   - Tests: Task 4 `test_pageCommandsDisabledWhileComposing`; Task 5 guard.
5. **Prefs saved by M1 without the new `font` key.**
   - Expected: theme, size and spacing are kept and the font defaults to Plex.
   - Test: Task 2 `test_m1PrefsWithoutFontDecode`.

## Rulings made while planning (deviations from the design doc)

- **The blank page is registered immediately; design §5.5 is overruled.**
  - Shared spec `docs/spec/01-pages-and-storage.md` §3.2 says a new page 「立即写入本机 SQLite 目录」 and has no projection file until first write. The prototype also lists a blank page in the overview at once.
  - Spec wins (AGENTS.md §1). `newPage` therefore calls `createPage` at once.
  - Task 1 rewrites design §5.5 to say this.
  - Cost if wrong: an unwritten blank page shows as 「空白的一页」 in the overview, which is the same as desktop and the prototype.
- **`createPage` returns the page object, not a String.** The signature is `createPage(after: String?, opId: String) -> CorePage` and the caller reads `pageId()`. This saves a reload.
- **Summary source.** The summary comes from the visible (rendered) text, not the Markdown source, so typing `#` doesn't show as `\#`.
- **Writes stay in order.** Library writes go through the persistence serial queue (`PagePersistence.perform`), so catalog writes and deltas keep one ordering.

---

### Task 1: Spec edits and FFI catalog

**Files:**
- Modify: `docs/spec/platform/ios.md`. Three edits:
  - §1 做 「外观」 bullet: two bundled fonts.
  - §3.2: a hardware-keyboard command table.
  - §4.1: M1 gains page management; M2 keeps only crash recovery and the storage hardening tied to it.
- Modify: `docs/superpowers/specs/2026-11-20-ios-prototype-parity-design.md`. In §5.5 「空白页」, register at once per 01 §3.2, and drop the "my call" paragraph.
- Modify: `apps/ios/ffi/src/lib.rs` (the `CoreStore` impl, about lines 331–391).
- Test: `apps/ios/ffi/tests/api.rs`.

**Interfaces:**
- Produces, Rust:
  - `#[derive(Debug, Clone, PartialEq, uniffi::Record)] pub struct PageInfo { pub id: String, pub deleted: bool, pub summary: String, pub modified_ms: Option<i64> }`
  - `CoreStore::open(path)`: same signature; now initializes the catalog and adopts orphan pages.
  - `CoreStore::pages(&self) -> R<Vec<PageInfo>>`
  - `CoreStore::create_page(&self, after: Option<String>, op_id: String) -> R<Arc<CorePage>>`
  - `CoreStore::set_deleted(&self, page_id: String, deleted: bool) -> R<()>`
- Produces, Swift (generated):
  - `PageInfo(id:deleted:summary:modifiedMs:)`
  - `store.pages()`
  - `store.createPage(after:opId:)`
  - `store.setDeleted(pageId:deleted:)`
- Keep `page_ids`, `commit_initial`, `commit_delta`, `checkpoint` and `load_fresh` unchanged.

- [ ] **Step 1: Spec edits.**
  - ios.md §1 「外观」: 「六种主题、字号、行距;第一阶段内置 Sumi Plex(IBM Plex Mono Light + IBM Plex Sans SC Light)与 Sumi WenKai(LXGW WenKai Mono Lite)两组字体,其余四组仍按 05-fonts 按需下载 **[用户定]** 2026-11-20「全部照搬」」.
  - §3.2: add the table from design §5.3 「硬件键盘」:
    - ⌘N 新建一页
    - ⌘[ 上一页
    - ⌘] 下一页
    - ⇧⌘L 纸页列表
    - ⌘, 设置
    - ⌘= 字号 +2
    - ⌘- 字号 −2
    - ⌘0 字号 22
    - Esc 菜单

    Add the sentence 「组字期间以上命令一律不响应」.
  - §4.1: move page management (概览、新建、上一页、下一页、废纸篓、恢复) into M1. M2 keeps 崩溃恢复.
  - Status lines stay `[计划:iOS]`.
  - Edit design §5.5 per the ruling above.
  - Run `bash docs/check.sh` → `OK`.

- [ ] **Step 2: Write the failing tests in `apps/ios/ffi/tests/api.rs`.** Use the existing `temp_db()`.
  - `fn type_text(store: &CoreStore, page: &Arc<CorePage>, text: &str, at_ms: i64)`: appends `text` at the end via `apply_edit` and then `commit_delta`.
  - `catalog_order_and_insert_in_middle`:
    - Create `a = create_page(None)`, `b = create_page(Some(a))`, then `c = create_page(Some(a))`.
    - `pages()` ids: index 0 is `a`. Indices 1–2 are `{b, c}` in ascending UUID order, because siblings sort by UUID (01 §2.1).
    - All three have `deleted == false`.
  - `delete_and_restore_keep_position`:
    - Create `a`, `b` after `a`, `c` after `b`.
    - `set_deleted(b, true)`: order is still `[a,b,c]` and `b.deleted == true`.
    - `set_deleted(b, false)`: `[a,b,c]`, all live.
    - A second `set_deleted(b, false)` is `Ok`. This checks idempotency.
  - `summary_is_first_nonblank_visible_line_capped_at_40`:
    - Type `"\n   \n  # 标题 \n正文"`. The summary is `"# 标题"`: visible text, trimmed, no backslash.
    - Type 50×`"字"` on a fresh page: the summary is 40 chars.
    - An empty page gives summary `""` and `modified_ms == None`.
  - `modified_is_max_line_time`: type `"a"` at 100, `"\nb"` at 300, then insert at offset 0 at 200. `modified_ms == Some(300)`.
  - `open_adopts_pages_missing_from_catalog`:
    - Use the M1 path: `CorePage::create` + `commit_initial` for two pages, `p1` and `p2`, with no catalog calls.
    - Reopen. `pages()` lists both, in ascending `page_id` order.
    - A later `create_page(None)` comes after them.
    - Reopening again doesn't duplicate them.
  - `catalog_state_survives_reopen`:
    - Create `a`, `b`. Type `"hi"` into `b`. `set_deleted(a, true)`.
    - Reopen. `pages()` equals the pre-close list, with `b.summary == "hi"`.
  - `create_page_with_missing_anchor_fails`: `create_page(Some(new_page_id()), …)` is `Err(CoreError::Storage{..})`, and `pages()` is unchanged.

- [ ] **Step 3: Run the tests and confirm they fail.**
  - Run: `cargo +1.99.0 test --manifest-path apps/ios/ffi/Cargo.toml`
  - Expected: compile errors for `pages`, `create_page`, `set_deleted` and `PageInfo`.

- [ ] **Step 4: Implement in `lib.rs`.**
  - **`open`:** in one `s.transaction`:
    - Run `catalog::initialize`.
    - Collect ids from `SELECT page_id FROM documents ORDER BY page_id` that `catalog::get` returns `None` for.
    - Anchor each one on the last entry of `catalog::list` (or the previously adopted id) with `catalog::create`.
  - **`create_page`:**
    - Build `Document::new(&new_page_id(), 1, random_client_id())`.
    - Serialize the pair as `commit_initial` does.
    - Call `commit_local_with(&doc, &op_id, &doc.encode_full(), &pair, |tx| catalog::create(tx, &id, after.as_deref()).map(|_| ()))`.
    - Return `CorePage::wrap(doc)`.
  - **`pages`:**
    - In one transaction, call `catalog::list`.
    - Load each entry's state from `documents` (`state`, `epoch`) with `Document::load(id, epoch, random_client_id(), &state)`, or use `Store::load`. A catalog entry with no document gives summary `""` and `None`.
    - The summary comes from `SourceMap::new(&doc.body(), doc.revision())` rendered text: split on `'\n'`, `trim()`, take the first non-empty line, `.chars().take(40)`.
    - `modified_ms` is the max `last_ms` over `doc.snapshot()?.lines`.
  - **`set_deleted`:** a transaction around `catalog::set_deleted`.
  - **Errors:** map them with `store_err`.
  - **Core changes:** don't change `core/` unless a needed function is private. If one is, make the smallest `pub` change and run the core Verification commands.

- [ ] **Step 5: Run the tests and confirm they pass.**
  - Run: `cargo +1.99.0 test --manifest-path apps/ios/ffi/Cargo.toml` → all pass.
  - Run: `bash apps/ios/scripts/test-sim.sh` → `** TEST SUCCEEDED **`. This proves the regenerated bindings still build.

- [ ] **Step 6: Commit.**
  - `git add docs/spec/platform/ios.md docs/superpowers/specs/2026-11-20-ios-prototype-parity-design.md apps/ios/ffi`
  - Message: `Expose the core page catalog to iOS and move page management into M1`.

---

### Task 2: Bundled fonts and prefs model

**Files:**
- Create: `apps/ios/SumiWrite/Resources/Fonts/`. Copy these six files byte-for-byte from the prototype `Resources/Fonts`:
  - `IBMPlexMono-Light.ttf`, `IBMPlexMono-OFL.txt`
  - `IBMPlexSansSC-Light.otf`, `IBMPlexSansSC-LICENSE.txt`
  - `LXGWWenKaiMonoLite-Regular.ttf`, `LXGWWenKaiMonoLite-OFL.txt`
- Create: `apps/ios/SumiWrite/Appearance/SumiFont.swift`.
- Create: `apps/ios/SumiWrite/Appearance/PrefsModel.swift`.
- Modify: `apps/ios/project.yml`. Register the fonts under `UIAppFonts`, for example through XcodeGen `info.properties` while keeping `GENERATE_INFOPLIST_FILE`, which Xcode merges. The resulting app's Info.plist must list the three font files.
- Modify: `apps/ios/SumiWrite/Appearance/EditorPrefs.swift`.
- Modify: `apps/ios/SumiWrite/Appearance/Theme.swift`. Add `var isDark: Bool`, which is false only for `.paper` and `.sepia`, and `var name: String`, using the Chinese names from design §5.4. Remove the private `isLight` extension from `EditorController` and use `!isDark`.
- Test: `apps/ios/SumiWriteTests/AppearanceTests.swift`.

**Interfaces:**
- Produces:
  - `enum SumiFont: String, Codable, CaseIterable, Identifiable { case plex, wenkai }` with:
    - `var name: String`: the strings from prototype `Prefs.swift`.
    - `func uiFont(size: CGFloat) -> UIFont`: copy the prototype body verbatim. That's the Plex cascade to `IBMPlexSansSC-Light`, and the WenKai fallback `.monospacedSystemFont(ofSize:weight: .light)`.
  - `EditorPrefs.font: SumiFont = .plex`, decoded with `decodeIfPresent`.
  - `EditorPrefs.defaultFontSize = 22.0` and `EditorPrefs.defaultLineSpacing = 1.6` (static).
  - `func EditorPrefs.bumpingFontSize(_ delta: Double) -> EditorPrefs`: clamps to `fontSizeRange`.
  - `@MainActor final class PrefsModel: ObservableObject`:
    - `@Published var prefs: EditorPrefs`. Its `didSet` saves through `PrefsStore`; if `save` returns false, it reverts to the old value.
    - `init(store: PrefsStore)`.
    - `func bumpSize(_ delta: Double)`.
    - `func resetSize()`: sets `fontSize` to 22 and `lineSpacing` to 1.6.

- [ ] **Step 1: Write the failing tests.**
  - `test_bundledFontsRegister`: `UIFont(name:size:)` is non-nil for `"IBMPlexMono-Light"`, `"IBMPlexSansSC-Light"` and `"LXGWWenKaiMonoLite-Regular"`.
  - `test_plexCascadesToSansSC`: `SumiFont.plex.uiFont(size: 22).fontDescriptor.object(forKey: .cascadeList)` contains a descriptor named `IBMPlexSansSC-Light`.
  - `test_m1PrefsWithoutFontDecode`:
    - Decode the JSON `{"theme":"sepia","fontSize":30,"lineSpacing":2,"caretMotion":"steady","focusTyping":false,"typingSound":true,"soundPack":"thock"}`.
    - Expect `.sepia`, 30, 2, `.plex` and the other fields as given.
  - `test_bumpSizeClampsAndResets`: 95 + 2 → 96; 9 − 2 → 8; `resetSize()` → 22 / 1.6.
  - `test_prefsModelPersists`: set `prefs.theme = .crt`. A new `PrefsModel` on the same `UserDefaults(suiteName:)` loads `.crt`.

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `bash apps/ios/scripts/test-sim.sh`
  - Expected: compile failure on `SumiFont` and `PrefsModel`.

- [ ] **Step 3: Implement.**
  - Copy the fonts and edit `project.yml`.
  - `EditorController.baseFont` becomes `prefs.font.uiFont(size: CGFloat(prefs.fontSize))`.

- [ ] **Step 4: Run the tests and confirm they pass.**
  - Run: `bash apps/ios/scripts/test-sim.sh` → `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**
  - Message: `Bundle the Plex and WenKai fonts and add an observable prefs model`.

---

### Task 3: PageLibrary

**Files:**
- Create: `apps/ios/SumiWrite/Core/PageLibrary.swift`.
- Modify: `apps/ios/SumiWrite/Core/PagePersistence.swift`. Remove the single-page `open(directory:)` and `OpenResult`; replace them with the library open below. Keep `committed`, `flushAndCheckpoint`, `waitUntilIdle` and `onFailure`.
- Modify: `apps/ios/SumiWrite/Core/SelectionStore.swift`. The key is per page: `"\(prefix).\(page.pageId())"`, with `prefix` defaulting to `"sumi.selection"`.
- Test:
  - Create `apps/ios/SumiWriteTests/PageLibraryTests.swift`.
  - Update `PagePersistenceTests.swift` and `SelectionStoreTests.swift`.

**Interfaces:**
- Consumes (Task 1): `CoreStore.pages()`, `createPage(after:opId:)`, `setDeleted(pageId:deleted:)`, `loadFresh(pageId:)`, `PageInfo`.
- Produces:
  - `func PagePersistence.perform<T>(_ body: (CoreStore) throws -> T) throws -> T`
    - Runs `queue.sync`, so it is ordered after queued deltas.
    - A thrown error sets the same failed state as a delta failure and calls `onFailure`.
  - `enum LibraryOpenResult { case ready(PageLibrary, PagePersistence, CorePage); case failed(String) }`
    - The `CorePage` is the current page, already loaded.
    - Failure text: `"打不开纸页"`.
  - `@MainActor final class PageLibrary: ObservableObject`:
    - `static func open(directory: URL, defaults: UserDefaults) -> LibraryOpenResult`
      - Database file: `page.sqlite3`. Keep the name so M1 data migrates.
      - Current id key: `"sumi.currentPage"`.
      - If the saved id is not live, use the first live page.
      - If there are no live pages, `createPage(after: pages.last?.id)`.
    - Published state:
      - `@Published private(set) var pages: [PageInfo]`
      - `@Published private(set) var currentID: String`
    - Derived lists:
      - `var live: [PageInfo]`: in catalog order.
      - `var trash: [PageInfo]`: by `modifiedMs` descending; nil sorts last.
      - `var position: (index: Int, count: Int)`: 1-based.
    - `func refresh()`: re-reads `pages()` through `perform`.
    - Navigation. Each returns the `CorePage` to show when the current page changes, or `nil` when nothing changes:
      - `func open(_ id: String) -> CorePage?`
      - `func next() -> CorePage?`
      - `func prev() -> CorePage?`
      - `func newPage() -> CorePage?`
    - Trash:
      - `func moveToTrash(_ id: String) -> CorePage?`: non-nil only when the current page changed.
      - `func restore(_ id: String)`
    - Semantics follow prototype `PageStore` exactly, except for the trash order below:
      - `next` on the last live page calls `newPage`.
      - `prev` on the first page returns nil.
      - `newPage` = `createPage(after: currentID)`.
      - `moveToTrash(current)` target: the next live page, else the previous live page, else a new page with `createPage(after: id)`. Spec 01 §3.3 says to prepare the target first, so the target is ready **before** `setDeleted(id, true)`.
      - Every mutation calls `refresh()` and saves `currentID` to defaults.
      - On a thrown error, `currentID` is left unchanged and nil is returned. The failure already reached `onFailure`.

- [ ] **Step 1: Write the failing tests in `PageLibraryTests`.** Use a temp directory and a fresh `UserDefaults(suiteName:)`.
  - `test_firstLaunchCreatesOnePage`: position 1/1, `live.count == 1`.
  - `test_nextOnLastCreatesAndPrevOnFirstStays`:
    - `next()` returns non-nil and the position is 2/2.
    - `prev()` → 1/2.
    - `prev()` → nil, still 1/2.
  - `test_newPageInsertsAfterCurrent`:
    - Start with pages A, B (B after A). Open A and call `newPage()` → C.
    - `live` ids equal the catalog order from `pages()` filtered by `!deleted`, and C comes right after A or after B, depending on UUID (01 §2.1).
    - Assert C's index is 1 if `C.id < B.id`, else 2.
  - `test_trashCurrentGoesToNextThenPrev`:
    - With A, B, C and current B: trashing B makes C current.
    - Trashing C then makes A current.
  - `test_trashOnlyPageCreatesBlank`:
    - Trash the only page. A new page is current, at position 1/1.
    - `trash.count == 1`.
  - `test_restoreReturnsToOriginalSlot`:
    - With A, B, C, trash B and then restore B.
    - `live` ids are `[A,B,C]`.
  - `test_currentPageRestoredAcrossOpen`: open B, then reopen the library on the same dir and defaults. `currentID == B`.
  - `test_opensMigratedSinglePage`:
    - Seed the dir with the M1 path: `CoreStore.open`, `CorePage.create`, `commitInitial`, then type `"旧"` via `applyEdit` + `commitDelta`. No catalog calls.
    - `open` → `.ready`, position 1/1, and the current page body is `"旧"`.
  - `test_selectionIsPerPage`:
    - Save different ranges for two pages.
    - Each restores its own; an unknown page restores to its end.

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `bash apps/ios/scripts/test-sim.sh` → compile failure.

- [ ] **Step 3: Implement `PageLibrary`, `perform` and the per-page `SelectionStore`.**
  - Update `SumiWriteApp`/`EditorController` call sites minimally so the app builds and shows the current page: open the library and pass its current page and persistence. Full wiring is Task 4/5.

- [ ] **Step 4: Run the tests and confirm they pass.**
  - Run: `bash apps/ios/scripts/test-sim.sh` → `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**
  - Message: `Add a page library backed by the core catalog`.

---

### Task 4: Editor parity

**Files:**
- Modify:
  - `apps/ios/SumiWrite/Editor/EditorController.swift`
  - `apps/ios/SumiWrite/Editor/SumiTextView.swift`
  - `apps/ios/SumiWrite/Appearance/CaretMetrics.swift`
- Create:
  - `apps/ios/SumiWrite/Editor/SumiCursorView.swift`
  - `apps/ios/SumiWrite/Editor/EditorCommand.swift`
  - `apps/ios/SumiWrite/Editor/FadeMask.swift`
- Delete: `apps/ios/SumiWrite/Editor/SettingsView.swift`, and the `CaretView` overlay in `SumiTextView.swift`.
- Test:
  - Modify `apps/ios/SumiWriteTests/EditorControllerTests.swift`.
  - Delete `test_caretOverlayIsHiddenFromAccessibility`.
  - Rewrite tests that depend on `statusBar`, `menuButton` or `CaretView`.

**Interfaces:**
- Consumes:
  - `PrefsModel` (Task 2).
  - `PageLibrary`, `PagePersistence.perform` and the per-page `SelectionStore` (Task 3).
- Produces:
  - `enum EditorCommand { case newPage, prev, next, overview, appearance, menu }`. The font-size commands are handled inside the controller through `PrefsModel`.
  - `EditorController` API:
    - `init(persistence: PagePersistence?, page: CorePage?, prefs: PrefsModel, selection: SelectionStore, sound: TypingSoundPlaying?)`. Nil means the open failed, which is read-only, as today.
    - `var onCommand: ((EditorCommand) -> Void)?`
    - `var canSwitchPage: Bool`: `textView.markedTextRange == nil`.
    - `func saveNow()`: saves the selection for the current page, then `flushAndCheckpoint`.
    - `func show(page: CorePage)`:
      - Saves the old page's selection.
      - Rebuilds `PageModel` and `CoreUndoManager` for the new page.
      - Puts the caret at the end, per spec §6 "切页光标到文末".
      - Exits focus.
    - `func focusEditor()`: `becomeFirstResponder`.
  - `enum FadeMask { static func opacity(distance d: CGFloat, lineHeight lh: CGFloat, height H: CGFloat) -> CGFloat }`
  - `final class SumiCursorView: UIView, UITextCursorView`
    - `isBlinking` is always false.
    - `resetBlinkAnimation()` is empty.
    - In `didMoveToWindow`: a `CABasicAnimation(keyPath: "opacity")` from 1.0 to 0.25, duration 2, `autoreverses`, `repeatCount = .infinity`, `easeInEaseOut`, `isRemovedOnCompletion = false`. It is removed when `caretMotion == .steady`.

- [ ] **Step 1: Write the failing tests.**
  - `test_fadeOpacityFormula`, with lh = 10 and H = 200:
    - d=0 → 1
    - d=5 → 1
    - d=10 → `0.55 * (1 - pow(10/100, 2))` = 0.5445, accuracy 1e-4
    - d=100 → 0
  - `test_caretRectWidthAndBlankLine`:
    - Font size 22 → width `min(3, max(2, 22/11))` = 2.
    - Font size 44 → 3.
    - On an empty line with lineSpacing 1.6, the rect's height ≤ the font's `lineHeight` and its top is pixel-aligned.
  - `test_pageCommandsDisabledWhileComposing`:
    - `setMarkedText("ni", …)`.
    - For every `keyCommands` action, `controller.canPerformAction(action, withSender: nil) == false`.
    - After `unmarkText()`, the `⌘N` action is true.
  - `test_fontSizeCommands`: ⌘= → 24, ⌘- → 22, ⌘0 → 22 after bumping. Check through `prefs.prefs.fontSize`.
  - `test_switchThenTypeWritesBothPages`:
    - Type "a" into page A, then `show(page: B)` immediately and type "b".
    - `persistence.waitUntilIdle()`.
    - Reopen the store: A's body is "a" and B's is "b".
    - B's selection is at the end after `show`.
  - `test_selectionWithinHalfSecondOfEditKeepsFocus`:
    - Enter focus with 4 quick inputs.
    - A `textViewDidChangeSelection` within 0.5s of the last edit, with a different range, keeps focus.
    - After 0.5s it exits focus.
    - Inject the clock with `var now: () -> Date`.
  - `test_statusBarAndHomeIndicatorHidden`: both `prefersStatusBarHidden` and `prefersHomeIndicatorAutoHidden` are true.
  - `test_cursorViewInstalled`:
    - The text view's `UITextSelectionDisplayInteraction.cursorView` is a `SumiCursorView`.
    - `textView.tintColor == theme.foreground`.

- [ ] **Step 2: Run the tests and confirm they fail.**
  - Run: `bash apps/ios/scripts/test-sim.sh` → compile failure.

- [ ] **Step 3: Implement.** Copy from prototype `Editor.swift`:
  - **Cursor:** install `SumiCursorView` in `viewDidLoad` and `viewDidAppear`.
  - **Removed:** `statusBar`, `menuButton`, `SettingsView` and the caret overlay. Remove `CaretMetrics.opacity` and `period`; keep `width`.
  - **Layout:**
    - The container's top, leading and trailing are pinned to the safe area.
    - Its bottom is pinned to `keyboardLayoutGuide.topAnchor`.
    - `followsUndockedKeyboard = true`.
  - **`viewDidLayoutSubviews`:** set the mask frame with implicit animations off. Then insets, `setFocusInsets`, `updateFade(0)`, `centerCaret(false)`.
  - **`shouldChangeTextIn`:** record `editSelection` and `lastEditTime`, plus the marked-text-prefix-shorter-means-backspace key classification. Feed that classification to the existing `TypingSound` key kind if it differs.
  - **Selection change:** the selection follows input if it equals `editSelection` or comes within 0.5s of `lastEditTime`. `inEdit`, `arrowNav` and following input recenter; anything else exits focus.
  - **`centerCaret`:** animates (0.2s easeOut) only when the caret's line changed and Reduce Motion is off.
  - **Drag:** begins → exit focus; insets reset once scrolling settles.
  - **Exit:** sets `primed`, which is `FocusTypingTracker.resumeOnNextInput`.
  - **`keyCommands`:** the nine commands with the prototype's titles. `canPerformAction` returns false for them while `markedTextRange != nil`.
  - **`applyPrefs` order:** as in design §5.3. Turning focus typing off exits focus.
  - **`-SumiDemo`:** copy `runDemo` from the prototype. Only `ProcessInfo` arguments trigger it.
  - **Prefs:** observe `PrefsModel.$prefs` with Combine → `applyPrefs`. Remove `updatePrefs`.

- [ ] **Step 4: Run the tests and confirm they pass.**
  - Run: `bash apps/ios/scripts/test-sim.sh` → `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit.**
  - Message: `Port the prototype editor behaviour onto the core-backed editor`.

---

### Task 5: SwiftUI shell, overview, appearance, and device install

**Files:**
- Modify: `apps/ios/SumiWrite/App/SumiWriteApp.swift`. Replace `EditorShell` with `ContentView`.
- Create: `apps/ios/SumiWrite/App/ContentView.swift`. It holds the chrome, the toast, `EditorHost` (a `UIViewControllerRepresentable` that wires `onCommand`) and the switch guard.
- Create: `apps/ios/SumiWrite/App/OverviewView.swift`.
- Create: `apps/ios/SumiWrite/App/AppearanceView.swift`.
- Modify: `apps/ios/README.md`. Add a manual-acceptance checklist.

**Interfaces:**
- Consumes:
  - `PageLibrary` (Task 3).
  - `PrefsModel`, `SumiFont`, `ThemeID.isDark` and `ThemeID.name` (Task 2).
  - `EditorController`'s `onCommand`, `canSwitchPage`, `saveNow`, `show(page:)` and `focusEditor` (Task 4).
- Produces: the app.

- [ ] **Step 1: Port the prototype `ContentView.swift` verbatim**, with `store` → `PageLibrary` and `prefs` → `PrefsModel`. All values are in design §5.4:
  - **Layout:**
    - The menu bar is 48 high with 4 bottom padding.
    - Button order: ‹, 「n / N」, ›, 新建, 总览, 设置, 移到废纸篓, then the ··· / × toggle.
    - Symbols are 17pt `.light` in a 44×44 hit area.
    - Capsule background: 10% open, 0% closed.
  - **Opacity:** 0.35 closed, 0 while typing and closed, 1 open, animated with `.easeOut(0.3)`.
  - **Typing:** `typingRecently` resets after 2.5s.
  - **Toast:**
    - The capsule shows for 1.8s, 64 from the bottom.
    - Copy: 「已移到废纸篓,可在总览里恢复」 and 「请先完成输入」.
  - **Switch guard:**
    - `canSwitchPage` false → toast.
    - Otherwise `saveNow()`, then the library call, then `show(page:)` if non-nil, then `focusEditor()`.
  - **Window:**
    - `.statusBarHidden(true)`, `.persistentSystemOverlays(.hidden)` and `.preferredColorScheme(isDark ? .dark : .light)`.
    - A scenePhase change away from `.active` calls `saveNow()`. Keep the existing background-task wrapper from `sceneDidEnterBackground`.
  - **Sheets:**
    - Both use `.presentationDetents([.medium, .large])`.
    - On dismiss they `focusEditor()`.
    - Opening the overview calls `library.refresh()` first.
- [ ] **Step 2: `OverviewView`, ported verbatim.**
  - The title 「纸页」 inline, with a 「完成」 toolbar button.
  - 「继续书写」:
    - A tap opens the page.
    - A swipe shows a destructive 「移到废纸篓」.
  - 「废纸篓」:
    - Hidden when empty.
    - A tap or a swipe 「恢复」 restores, with `arrow.uturn.backward` in blue.
  - Each row:
    - The summary, or a grey 「空白的一页」, on one line.
    - A caption with `Date(ms)` formatted `.abbreviated` / `.shortened`.
    - A pencil icon on the current page.
- [ ] **Step 3: `AppearanceView`, ported verbatim.**
  - 主题: an inline picker with 18pt circles in the background colour and a 3pt foreground stroke.
  - 字体: an inline picker with the prototype footer.
  - 排版:
    - 「字号 N pt」 slider 8–96 step 1.
    - 「行距 x.x」 slider 1–3 step 0.1.
    - 「恢复默认字号与行距」.
  - 书写:
    - 光标 平缓呼吸/常亮.
    - 聚焦打字 and 打字音 toggles.
- [ ] **Step 4: README checklist.**
  - In `apps/ios/README.md`, add a 「原型对齐手工验收」 list. Cover:
    - menu show and hide while typing;
    - ‹ › at both ends;
    - 新建;
    - trash and restore, including the only page;
    - overview rows;
    - every settings control taking effect live;
    - all nine hardware shortcuts;
    - shortcuts refused while composing pinyin;
    - status bar and home indicator hidden;
    - the breathing cursor;
    - relaunch restoring the page and caret.
  - Run `bash docs/check.sh` → `OK`.
- [ ] **Step 5: Run the tests.**
  - `bash apps/ios/scripts/test-sim.sh` → `** TEST SUCCEEDED **`.
  - `cargo +1.99.0 test --manifest-path apps/ios/ffi/Cargo.toml` → pass.
- [ ] **Step 6: Commit.**
  - Message: `Port the prototype shell, overview and appearance sheet`.
- [ ] **Step 7: Install on the Duo (controller only, after the final review).**
  - Run `bash apps/ios/scripts/install-device.sh "iPhone DUO" > <scratchpad>/install-duo.log 2>&1`.
  - Then `xcrun devicectl device process launch --device "iPhone DUO" <PRODUCT_BUNDLE_IDENTIFIER from apps/ios/Signing.local.xcconfig>`. If the phone reports "Locked", ask the user to unlock it.
