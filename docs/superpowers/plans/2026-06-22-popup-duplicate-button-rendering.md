# Popup Duplicate Button Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the disabled Add to Anki duplicate indicator with the real macOS `plus.square.on.square` SF Symbol while retaining the stable inline WebView button architecture.

**Architecture:** A focused AppKit helper rasterizes the system symbol into a transparent 28-point, 3x PNG data URL. `PopupWebView` injects that URL before popup rendering, and `popup.js` uses it as a CSS mask only for duplicate mining state, with the existing SVG retained as a non-fatal fallback.

**Tech Stack:** Swift/AppKit, `NSImage`, `NSBitmapImageRep`, WKWebView `callAsyncJavaScript`, JavaScript, CSS masks, Swift contract scripts.

---

### Task 1: Define failing renderer and integration contracts

**Files:**
- Create: `script/test_popup_system_symbol_renderer.swift`
- Modify: `script/test_popup_duplicate_button_rendering.swift`
- Test: both scripts

- [ ] **Step 1: Add the renderer contract**

Create `script/test_popup_system_symbol_renderer.swift`:

```swift
import AppKit
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum PopupSystemSymbolRendererContract {
    static func main() throws {
        guard let dataURL = PopupSystemSymbolRenderer.duplicateSymbolDataURL else {
            fputs("FAIL: renderer should produce the duplicate system symbol\n", stderr)
            exit(1)
        }
        require(dataURL.hasPrefix("data:image/png;base64,"), "renderer should return a PNG data URL")

        let encoded = String(dataURL.dropFirst("data:image/png;base64,".count))
        guard let data = Data(base64Encoded: encoded),
              let bitmap = NSBitmapImageRep(data: data) else {
            fputs("FAIL: renderer output should decode as PNG\n", stderr)
            exit(1)
        }
        require(bitmap.pixelsWide == 84 && bitmap.pixelsHigh == 84, "renderer should use a 28-point 3x canvas")
        require(bitmap.hasAlpha, "renderer output should preserve transparency")

        let containsVisiblePixels = (0..<bitmap.pixelsHigh).contains { y in
            (0..<bitmap.pixelsWide).contains { x in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0
            }
        }
        require(containsVisiblePixels, "renderer output should contain visible symbol pixels")
        print("PASS: popup system symbol renderer contract")
    }
}
```

- [ ] **Step 2: Replace the source contract expectations**

Keep the existing source-loading helpers in `script/test_popup_duplicate_button_rendering.swift`, add `PopupWebView.swift` and the Xcode project, and replace the rendering assertions with:

```swift
let popupWebView = try source("Features/Popup/PopupWebView.swift")
let xcodeProject = try source("Hoshi Reader.xcodeproj/project.pbxproj")

require(
    xcodeProject.contains("Popup/PopupSystemSymbolRenderer.swift,"),
    "the synchronized Features group should include the popup symbol renderer in the app target"
)

require(
    popupWebView.contains("PopupSystemSymbolRenderer.duplicateSymbolDataURL")
        && popupWebView.contains("window.hoshiInlineButtonSymbols = {")
        && popupWebView.contains("\"duplicateSymbolDataURL\": duplicateSymbolDataURL"),
    "PopupWebView should inject the system duplicate symbol before rendering"
)
require(
    popupScript.contains("window.hoshiInlineButtonSymbols?.duplicate")
        && popupScript.contains("class=\"inline-system-symbol\"")
        && popupScript.contains("--inline-system-symbol-mask"),
    "duplicate Add to Anki state should prefer the injected system symbol mask"
)
require(
    popupScript.contains(#"<rect x="5" y="7" width="11" height="11""#),
    "duplicate Add to Anki state should retain the SVG fallback"
)
require(
    popupStyles.contains(".inline-system-symbol {")
        && popupStyles.contains("-webkit-mask: var(--inline-system-symbol-mask) center / contain no-repeat;")
        && popupStyles.contains("background: currentColor;"),
    "inline system symbols should use a currentColor CSS mask"
)
require(
    popupStyles.contains(".inline-action-button:disabled {\n    opacity: 0.45;\n    background: transparent;\n}"),
    "disabled inline action buttons should retain a transparent background"
)
require(
    popupScript.contains("slot.disabled = !enabled;")
        && popupScript.contains("if (slot.dataset.enabled === 'false') { return; }"),
    "duplicate Add to Anki entries should remain disabled and ignore clicks"
)
```

- [ ] **Step 3: Verify RED**

Run:

```bash
swiftc -parse-as-library Features/Popup/PopupSystemSymbolRenderer.swift script/test_popup_system_symbol_renderer.swift -o /tmp/test_popup_system_symbol_renderer
```

Expected: compilation fails because `Features/Popup/PopupSystemSymbolRenderer.swift` does not exist.

Run:

```bash
swift script/test_popup_duplicate_button_rendering.swift
```

Expected: exits `1` with `FAIL: PopupWebView should inject the system duplicate symbol before rendering`.

### Task 2: Implement the system symbol renderer

**Files:**
- Create: `Features/Popup/PopupSystemSymbolRenderer.swift`
- Modify: `Hoshi Reader.xcodeproj/project.pbxproj:83-94`
- Test: `script/test_popup_system_symbol_renderer.swift`

- [ ] **Step 1: Add the focused renderer**

Create `Features/Popup/PopupSystemSymbolRenderer.swift`:

```swift
import AppKit
import Foundation

enum PopupSystemSymbolRenderer {
    static let duplicateSymbolDataURL = pngDataURL(symbolName: "plus.square.on.square")

    static func pngDataURL(
        symbolName: String,
        pointSize: CGFloat = 13,
        canvasPointSize: CGFloat = 28,
        pixelScale: Int = 3
    ) -> String? {
        guard pixelScale > 0,
              let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
              let symbolImage = baseImage.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
              ),
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(canvasPointSize) * pixelScale,
                pixelsHigh: Int(canvasPointSize) * pixelScale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else {
            return nil
        }

        bitmap.size = NSSize(width: canvasPointSize, height: canvasPointSize)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: canvasPointSize, height: canvasPointSize).fill(using: .copy)
        NSColor.black.set()
        symbolImage.draw(
            at: NSPoint(
                x: (canvasPointSize - symbolImage.size.width) / 2,
                y: (canvasPointSize - symbolImage.size.height) / 2
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }
}
```

- [ ] **Step 2: Verify the renderer contract GREEN**

Add `Popup/PopupSystemSymbolRenderer.swift,` beside the other Popup sources in the Features synchronized root group's `membershipExceptions`, so the `Hoshi Reader` target compiles the new file.

Run:

```bash
swiftc -parse-as-library Features/Popup/PopupSystemSymbolRenderer.swift script/test_popup_system_symbol_renderer.swift -o /tmp/test_popup_system_symbol_renderer && /tmp/test_popup_system_symbol_renderer
```

Expected: `PASS: popup system symbol renderer contract`.

### Task 3: Inject and render the system symbol mask

**Files:**
- Modify: `Features/Popup/PopupWebView.swift:384-410`
- Modify: `Features/Popup/popup.js:1354-1368`
- Modify: `Features/Popup/popup.css:167-180`
- Test: `script/test_popup_duplicate_button_rendering.swift`

- [ ] **Step 1: Inject the data URL before popup rendering**

In `webView(_:didFinish:)`, resolve `duplicateSymbolDataURL`, add the JavaScript symbol object before `renderPopup()`, and pass the argument:

```swift
let duplicateSymbolDataURL = PopupSystemSymbolRenderer.duplicateSymbolDataURL ?? ""
webView.callAsyncJavaScript(
    """
    window.hoshiUseViewportButtonFrames = true;
    window.hoshiUseInlineActionButtons = true;
    window.hoshiInlineButtonSymbols = {
        duplicate: duplicateSymbolDataURL || null
    };
    window.contextMiningAvailable = contextMiningAvailable;
    window.contextMiningLabel = contextMiningLabel;
    window.dictionaryStyles = dictionaryStyles;
    window.entryCount = entryCount;
    window.hoshiSelection.registerModifierTracking();
    window.hoshiSelection.registerShiftHoverLookup(16, hoverLookupDelayMs);
    window.renderPopup();
    """,
    arguments: [
        "dictionaryStyles": parent.dictionaryStyles,
        "entryCount": entries.count,
        "hoverLookupDelayMs": parent.hoverLookupDelayMs,
        "contextMiningAvailable": parent.onPrepareContextMining != nil,
        "contextMiningLabel": String(localized: "Select Context"),
        "duplicateSymbolDataURL": duplicateSymbolDataURL,
    ],
    in: nil,
    in: .page,
    completionHandler: { _ in
        webView.evaluateJavaScript("window.hoshiResetDictionaryEntryFocus?.();")
        webView.window?.makeFirstResponder(webView)
    }
)
```

- [ ] **Step 2: Prefer the system mask and restore the original SVG fallback**

Change only the duplicate branch of `inlineButtonIcon()`:

```javascript
if (state === 'duplicate') {
    const systemSymbol = window.hoshiInlineButtonSymbols?.duplicate;
    if (systemSymbol) {
        return `<span class="inline-system-symbol" style="--inline-system-symbol-mask: url(${systemSymbol})" aria-hidden="true"></span>`;
    }
    return '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="7" width="11" height="11" rx="2" fill="none" stroke="currentColor" stroke-width="2"/><rect x="8" y="4" width="11" height="11" rx="2" fill="none" stroke="currentColor" stroke-width="2"/><path d="M10 11h7m-3.5-3.5v7" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';
}
```

- [ ] **Step 3: Add the mask styling**

Add after the existing SVG rule:

```css
.inline-system-symbol {
    width: var(--popup-button-size);
    height: var(--popup-button-size);
    display: block;
    background: currentColor;
    -webkit-mask: var(--inline-system-symbol-mask) center / contain no-repeat;
    mask: var(--inline-system-symbol-mask) center / contain no-repeat;
}
```

- [ ] **Step 4: Verify the focused integration contract GREEN**

Run: `swift script/test_popup_duplicate_button_rendering.swift`

Expected: `PASS: popup duplicate button rendering contract`.

- [ ] **Step 5: Verify neighboring contracts and syntax**

Run:

```bash
swiftc -parse-as-library script/test_mining_context_ui_contract.swift -o /tmp/test_mining_context_ui_contract && /tmp/test_mining_context_ui_contract
/Users/wight/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --check Features/Popup/popup.js
git diff --check
```

Expected: mining-context contract passes; JavaScript and diff checks exit `0`.

### Task 4: Build and visually verify the exact Light app

**Files:**
- Verify only.

- [ ] **Step 1: Build, launch, and verify exact identity**

Run: `./script/build_and_run.sh --verify`

Expected: bundle identifier `moe.shishamo.hoshi` and the running executable path both point to the reported DerivedData Light product.

- [ ] **Step 2: Open the safe existing duplicate**

Run: `./script/build_and_run_native.sh --open-url 'hoshi://search?text=星'`

Expected: the exact built Light app displays `星` with Add to Anki exposed as disabled. Do not press the button.

- [ ] **Step 3: Inspect rendering and interaction state**

Confirm that the duplicate indicator uses the system `plus.square.on.square` proportions, is centered at the same optical size as the v0.5.0 reference, has no filled disabled background, and remains exposed as disabled in the accessibility tree. Also inspect another non-duplicate entry to confirm its normal Add to Anki icon is unchanged.

- [ ] **Step 4: Review final scope**

Run:

```bash
git status --short
git diff --check
git diff -- Features/Popup/PopupSystemSymbolRenderer.swift Features/Popup/PopupWebView.swift Features/Popup/popup.js Features/Popup/popup.css script/test_popup_system_symbol_renderer.swift script/test_popup_duplicate_button_rendering.swift docs/superpowers/specs/2026-06-22-popup-duplicate-button-rendering-design.md docs/superpowers/plans/2026-06-22-popup-duplicate-button-rendering.md
```

Expected: only the approved renderer, injection, mask, tests, design, and plan changes appear. Do not commit, push, tag, or release.
