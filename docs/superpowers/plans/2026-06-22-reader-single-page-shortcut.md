# Reader Single-Page Shortcut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure one physical Reader previous/next shortcut press produces exactly one page-navigation request.

**Architecture:** Make shortcut dispatch ownership explicit. The application-local event monitor will pass through events whose focused responder owns dispatch, while `NativeReaderWKWebView.keyDown` remains the sole dispatcher for Reader WebView events; all other shortcuts retain the local-monitor path.

**Tech Stack:** Swift, AppKit `NSEvent`, WebKit `WKWebView`, repository Swift contract tests.

---

### Task 1: Add a failing single-owner dispatch regression

**Files:**
- Modify: `script/test_reader_popup_sasayaki_regressions.swift`
- Test: `script/test_reader_popup_sasayaki_regressions.swift`

- [x] **Step 1: Write the failing contract assertions**

Add assertions requiring a responder ownership marker, source-aware dispatch, monitor pass-through for an owning responder, and removal of event-signature deduplication:

```swift
assertContains(
    shortcutManager,
    "protocol ShortcutEventDispatchResponder: AnyObject {}",
    "focused AppKit responders must be able to own shortcut dispatch"
)
assertContains(
    shortcutManager,
    "handle(event, source: .localMonitor)",
    "the local monitor must identify its dispatch source"
)
assertContains(
    shortcutManager,
    "source == .localMonitor, responder is ShortcutEventDispatchResponder",
    "the local monitor must defer to a focused responder that owns shortcut dispatch"
)
assertContains(
    nativeReader,
    "final class NativeReaderWKWebView: WKWebView, ShortcutEventDispatchResponder",
    "the Reader WKWebView must be the sole dispatcher while focused"
)
assertNotContains(
    shortcutManager,
    "handledEventSignature",
    "mutually exclusive dispatch paths must not rely on timestamp deduplication"
)
```

- [x] **Step 2: Run the focused contract and verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Features/Reader/ReaderWebView/ReaderViewportGeometry.swift script/test_reader_popup_sasayaki_regressions.swift -o /tmp/test_reader_popup_sasayaki_regressions && /tmp/test_reader_popup_sasayaki_regressions
```

Expected: `FAIL` stating that focused responders cannot yet own shortcut dispatch.

### Task 2: Make Reader WebView dispatch ownership exclusive

**Files:**
- Modify: `Core/Shortcuts/ShortcutManager.swift`
- Modify: `NativeMac/NativeReaderView.swift`
- Modify: `Hoshi Reader.xcodeproj/project.pbxproj`
- Delete: `Core/Shortcuts/ShortcutEventSignature.swift`
- Delete: `script/test_shortcut_event_signature.swift`

- [x] **Step 1: Add explicit dispatch source and responder ownership**

In `ShortcutManager.swift`, declare the ownership protocol and dispatch source:

```swift
protocol ShortcutEventDispatchResponder: AnyObject {}

private enum ShortcutDispatchSource {
    case localMonitor
    case responder
}
```

Route monitor events through `handle(event, source: .localMonitor)` and focused control events through `handle(event, source: .responder)`. Change `shouldHandle` to accept the source and pass monitor events through when the focused responder conforms:

```swift
if source == .localMonitor, responder is ShortcutEventDispatchResponder {
    return false
}
```

Remove `handledEventSignature`, `consumeHandledEvent`, and all `ShortcutEventSignature` construction.

- [x] **Step 2: Mark the Reader WebView as the focused owner**

Change the declaration in `NativeReaderView.swift`:

```swift
final class NativeReaderWKWebView: WKWebView, ShortcutEventDispatchResponder {
```

Keep its existing `keyDown` consumption behavior unchanged.

- [x] **Step 3: Remove obsolete signature files**

Delete `Core/Shortcuts/ShortcutEventSignature.swift` and `script/test_shortcut_event_signature.swift`, then remove `Shortcuts/ShortcutEventSignature.swift` from the Core synchronized-group membership exceptions in `project.pbxproj`; the single-owner architecture no longer compares rewrapped event timestamps.

- [x] **Step 4: Run the focused contract and verify GREEN**

Run the command from Task 1. Expected: `Reader popup and Sasayaki regression checks passed`.

- [x] **Step 5: Run shortcut boundary tests**

Run:

```bash
xcrun swiftc -parse-as-library Core/Shortcuts/KeyboardShortcutBinding.swift Core/Shortcuts/ShortcutAction.swift Core/Shortcuts/ShortcutDispatchResolver.swift script/test_shortcut_dispatch_resolution.swift -o /tmp/test_shortcut_dispatch_resolution && /tmp/test_shortcut_dispatch_resolution
xcrun swiftc -parse-as-library Core/Shortcuts/KeyboardShortcutBinding.swift Core/Shortcuts/ShortcutAction.swift Core/Shortcuts/ShortcutConflictChecker.swift script/test_shortcut_scope_resolution.swift -o /tmp/test_shortcut_scope_resolution && /tmp/test_shortcut_scope_resolution
xcrun swiftc -parse-as-library Core/Shortcuts/KeyboardShortcutBinding.swift Core/Shortcuts/ShortcutAction.swift Core/Shortcuts/ShortcutRegistry.swift Features/Reader/ReaderShortcutActions.swift Features/Dictionary/DictionaryShortcutActions.swift Features/Popup/PopupShortcutActions.swift Features/Sasayaki/SasayakiShortcutActions.swift Features/Settings/ApplicationShortcutRegistry.swift script/test_shortcut_registry.swift -o /tmp/test_shortcut_registry && /tmp/test_shortcut_registry
```

Expected: all three scripts print their respective passed messages.

### Task 3: Verify the native Light app

**Files:**
- Verify only; no planned production edits.

- [ ] **Step 1: Check the patch for unrelated changes and whitespace errors**

Run:

```bash
git diff --check
git diff -- Core/Shortcuts/ShortcutManager.swift NativeMac/NativeReaderView.swift script/test_reader_popup_sasayaki_regressions.swift
```

Expected: no whitespace errors; only single-owner shortcut routing changes appear in scoped source files.

- [ ] **Step 2: Build, launch, and verify exact app identity**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: build succeeds and verification reports bundle id `moe.shishamo.hoshi` plus a running executable inside the exact DerivedData `.app`.

- [ ] **Step 3: Perform safe Reader smoke verification when possible**

Using an already-present EPUB without importing, deleting, or replacing user data, lightly press Previous Page and Next Page and confirm each press advances one page. If no suitable Reader state is available, report this manual scenario as unverified.

No commits are included because repository instructions require explicit user authorization before committing.
