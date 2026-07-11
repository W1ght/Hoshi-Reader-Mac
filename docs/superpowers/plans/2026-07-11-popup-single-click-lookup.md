# Popup Single-Click Lookup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore nested dictionary lookup from a normal mouse click inside popup glossary text while preserving native drag selection, internal controls, and Shift-hover lookup.

**Architecture:** Install one popup interaction state machine per entries container. Record the original target and coordinates at `pointerdown`, classify movement beyond three points or a non-collapsed selection as native text selection, and dispatch short-click lookup directly from `pointerup` before WebKit pointer capture can retarget the synthetic click. Keep ruby annotations unselectable and sanitize copied/mined selection text through `getPopupSelectionText()`.

**Tech Stack:** JavaScript in WKWebView, Swift contract test script.

## Global Constraints

- Native macOS is the only supported target.
- Preserve popup and dictionary-page shared rendering behavior.
- Do not change Shift-hover lookup, internal link activation, native selection copying, or lookup stack semantics.
- Do not commit, push, tag, or release without explicit user approval.

---

### Task 1: Restore Single-Click Lookup Event Semantics

**Files:**
- Modify: `script/test_popup_two_column_layout.swift`
- Modify: `Features/Popup/popup.js`

**Interfaces:**
- Consumes: the existing `pointerdown`, `pointermove`, `pointerup`, and `click` listeners in `window.renderPopup`.
- Produces: `popupPointerInteraction` owns one pointer sequence and `suppressNextPopupClick` consumes the synthetic click after pointer-up handling.

- [ ] **Step 1: Write the failing contract assertion**

Add assertions that require one-time listener installation, the pointer interaction record, drag classification, direct pointer-up lookup, native-selection preservation, and the absence of eager `selectstart` suppression:

```swift
require(
    compactWhitespace(popupScript).contains("if(container.popupInteractionAttached){return;}container.popupInteractionAttached=true;")
        && popupScript.contains("let popupPointerInteraction = null;")
        && compactWhitespace(popupScript).contains("popupPointerInteraction={x:e.clientX,y:e.clientY,target,didDrag:false};")
        && compactWhitespace(popupScript).contains("popupPointerInteraction.didDrag=true;")
        && compactWhitespace(popupScript).contains("handlePopupLookupAtPoint(interaction.target,interaction.x,interaction.y);")
        && !popupScript.contains("container.addEventListener('selectstart'"),
    "popup should separate short-click lookup from native text selection without trusting a retargeted click"
)
```

- [ ] **Step 2: Run the contract and verify RED**

Run:

```bash
swift script/test_popup_two_column_layout.swift
```

Expected: the new interaction-state assertion fails before implementation.

- [ ] **Step 3: Implement the minimal fix**

Install the event boundary once. Record `{x, y, target, didDrag}` at `pointerdown`, set `didDrag` after three points of movement, release capture at `pointerup`, and either preserve/cache the native selection or call `handlePopupLookupAtPoint` with the original target and coordinates. Consume the following synthetic click once, while leaving links, buttons, summaries, and form controls on native activation paths. Remove the eager listener:

```javascript
container.addEventListener('selectstart', () => {
    suppressLookupClick = true;
    cachePopupSelection();
}, true);
```

Keep `ruby > rt` and `ruby > rp` non-selectable, and keep `getPopupSelectionText()` as the source for copy and mining text so ruby annotation text is omitted.

- [ ] **Step 4: Run focused regression contracts**

Run:

```bash
swift script/test_popup_two_column_layout.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library script/test_mining_context_ui_contract.swift -o /tmp/test_mining_context_ui_contract && /tmp/test_mining_context_ui_contract
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Features/Reader/ReaderWebView/ReaderViewportGeometry.swift script/test_reader_popup_sasayaki_regressions.swift -o /tmp/test_reader_popup_sasayaki_regressions && /tmp/test_reader_popup_sasayaki_regressions
```

Expected: all commands pass.

- [ ] **Step 5: Build, launch, and verify the Light app**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: build succeeds, bundle id is `moe.shishamo.hoshi`, and the running executable path matches this build's DerivedData product.

Manually verify with an existing EPUB without changing user data:

- Normal click on glossary text opens a child lookup popup.
- Shift-hover lookup still opens a child lookup popup.
- Drag-selecting glossary text preserves the native selection and does not open a child popup.
- Internal links and popup action buttons still activate normally.
