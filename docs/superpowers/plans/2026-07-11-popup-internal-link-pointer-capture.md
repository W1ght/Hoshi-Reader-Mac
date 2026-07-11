# Popup Internal Link Pointer Capture Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore normal mouse activation of structured dictionary links while preserving drag-outside text selection and existing popup navigation history.

**Architecture:** Keep the shared redirect/history pipeline unchanged. Narrow the shared `popup.js` pointer-capture boundary so only non-interactive glossary content captures the pointer; Popup and Dictionary surfaces both inherit the fix.

**Tech Stack:** JavaScript in WKWebView, Swift contract scripts, SwiftUI/AppKit macOS application.

## Global Constraints

- Native macOS is the only supported target.
- Preserve lookup, redirect, back/forward history, layout, settings, persistence, and localization semantics.
- Preserve pointer capture for ordinary glossary text.
- Do not modify or commit unrelated worktree changes.
- Do not create a commit unless the user explicitly requests one.

---

### Task 1: Protect Interactive Dictionary Targets From Pointer Capture

**Files:**
- Modify: `script/test_popup_two_column_layout.swift`
- Modify: `Features/Popup/popup.js`

**Interfaces:**
- Consumes: `popupEventTarget(event)` and the existing `pointerdown` listener on `#entries-container`.
- Produces: `isPopupInteractiveTarget(target): boolean`, used only to decide whether the entries container calls `setPointerCapture`.

- [ ] **Step 1: Write the failing contract**

Add this assertion before the existing pointer-ownership assertion:

```swift
require(
    popupScript.contains("function isPopupInteractiveTarget(target)")
        && popupScript.contains("target.closest('a, button, summary, input, select, textarea, [role=\"button\"], [contenteditable=\"true\"]')")
        && compactWhitespace(popupScript).contains("if(isPopupInteractiveTarget(target)){popupPointerStart=null;suppressLookupClick=false;return;}"),
    "popup interactive controls should keep native pointer activation instead of being retargeted by glossary pointer capture"
)
```

- [ ] **Step 2: Run the contract and verify RED**

Run `swift script/test_popup_two_column_layout.swift`.

Expected: exit 1 with the new interactive-controls failure message.

- [ ] **Step 3: Implement the minimal pointer-boundary fix**

Add this helper before the popup pointer listeners:

```javascript
function isPopupInteractiveTarget(target) {
    return target instanceof Element
        && target.closest('a, button, summary, input, select, textarea, [role="button"], [contenteditable="true"]');
}
```

After the glossary-content eligibility guard and before assigning `popupPointerStart`, add:

```javascript
if (isPopupInteractiveTarget(target)) {
    popupPointerStart = null;
    suppressLookupClick = false;
    return;
}
```

- [ ] **Step 4: Run focused and shared contracts and verify GREEN**

Run:

```bash
swift script/test_popup_two_column_layout.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Features/Reader/ReaderWebView/ReaderViewportGeometry.swift script/test_reader_popup_sasayaki_regressions.swift -o /tmp/test_reader_popup_sasayaki_regressions
/tmp/test_reader_popup_sasayaki_regressions
```

Expected: both contracts exit 0 and print PASS messages.

- [ ] **Step 5: Review the diff for scope**

Run `git diff --check` and `git diff -- Features/Popup/popup.js script/test_popup_two_column_layout.swift`.

Expected: no whitespace errors; only the focused contract and interactive-target guard changed.

### Task 2: Verify the Exact Light App and User-Visible Navigation

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: Light build, bundle id `moe.shishamo.hoshi`, `三省堂国語辞典　第八版`, and shared popup navigation history.
- Produces: exact build/process identity evidence and manual mouse-navigation evidence.

- [ ] **Step 1: Build and launch an isolated Light instance**

Run `./script/build_and_run.sh --instance popup-internal-link-fix --verify`.

Expected: the script verifies `moe.shishamo.hoshi` and the exact executable below `.build/xcode-derived-data-popup-internal-link-fix/Build/Products/Debug/Niratan.app`.

- [ ] **Step 2: Verify normal mouse activation**

In the exact app, open Dictionary, search `サラダ`, scroll to `三省堂国語辞典　第八版`, and use a normal coordinate mouse click—not an accessibility link action—on `サラダオイル`.

Expected: the current lookup surface renders `サラダオイル` and retains the prior `サラダ` snapshot in history.

- [ ] **Step 3: Verify backward and forward restoration**

Use the existing action-bar back control, then forward control.

Expected: back restores `サラダ` at its saved scroll position and forward restores `サラダオイル` without opening a browser or closing the popup.

- [ ] **Step 4: Verify drag-outside selection regression**

Drag-select ordinary glossary text beyond a popup boundary and release.

Expected: selection remains available. If safe Reader-popup access requires changing user book progress or other user data, do not alter it and report this scenario as not covered.

- [ ] **Step 5: Record final status without committing**

Run `git status --short --branch`.

Expected: intended popup/test/spec/plan files plus pre-existing user files; no commit created.

### Task 3: Compose Popup History and Sasayaki Controls

**Files:**
- Modify: `script/test_popup_two_column_layout.swift`
- Modify: `script/test_reader_popup_sasayaki_regressions.swift`
- Modify: `Features/Popup/PopupView.swift`

**Interfaces:**
- Consumes: `userConfig.popupActionBar`, `backCount`, `forwardCount`, `backTrigger`, `forwardTrigger`, and optional Sasayaki cue/player state.
- Produces: a history-aware action-bar visibility rule and one merged control row when Sasayaki is available.

- [ ] **Step 1: Add a failing contract**

Require `PopupView` to compute `showsActionBar` from the preference or either history count, merge action controls into `sasayakiControls` when audio is present, and apply plain button styling with fixed hit frames.

- [ ] **Step 2: Run `swift script/test_popup_two_column_layout.swift` and verify RED**

Expected: the new Popup action-bar composition assertion fails.

- [ ] **Step 3: Implement the compact native operation bar**

Use `userConfig.popupActionBar || backCount > 0 || forwardCount > 0`. When Sasayaki audio exists, render history, audio, and close controls in one row; otherwise render the normal action bar. Use plain buttons and fixed transparent hit frames.

- [ ] **Step 4: Run focused and shared contracts and verify GREEN**

Run the same Popup and Reader/Popup/Sasayaki commands from Task 1 Step 4.

- [ ] **Step 5: Rebuild and verify the exact Light app**

Repeat Task 2 with normal pointer clicks. With the preference off, confirm the bar is initially hidden and appears after redirect; with it on, confirm it is always present. In a Sasayaki popup, confirm all controls share one row and have no individual button backgrounds.
