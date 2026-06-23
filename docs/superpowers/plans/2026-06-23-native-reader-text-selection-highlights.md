# Native Reader Text Selection and Highlights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve native WebKit drag selection while retaining click-to-lookup, then restore highlight creation and persistence through the standard macOS context menu.

**Architecture:** Treat a non-collapsed browser selection as the source of truth and bypass the capture-phase click lookup when it exists. Extend `NativeReaderWKWebView`'s AppKit menu without replacing WebKit's standard items, reuse `highlights.js` for range creation, and forward successful creation through `NativeReaderWebView` into `NativeReaderModel` for book-scoped persistence.

**Tech Stack:** Swift 6, SwiftUI, AppKit, WebKit/WKWebView, injected JavaScript, xcstrings, focused Swift contract tests.

---

## File Map

- Modify `script/test_reader_popup_sasayaki_regressions.swift`: encode the selection, menu bridge, persistence, and localization contracts before production changes.
- Modify `NativeMac/NativeReaderView.swift`: arbitrate drag selection versus click lookup, add the AppKit highlight menu bridge, handle `selectionState`, and persist created highlights.
- Modify `Models/Highlight.swift`: provide localized user-facing color names for native menu items.
- Modify `Localizable.xcstrings`: add English and Simplified Chinese color labels.
- Modify `docs/READER_REGRESSION_TESTING.md`: make drag selection, Copy, highlight creation/deletion, and persistence part of the Reader actual-data matrix.

Existing user changes in these files must be preserved. Do not reset or replace whole files. No commit step is included because repository instructions require explicit commit authorization.

### Task 1: Add the failing Reader selection/highlight contract

**Files:**
- Modify: `script/test_reader_popup_sasayaki_regressions.swift`
- Test: `script/test_reader_popup_sasayaki_regressions.swift`

- [ ] **Step 1: Add focused assertions after the existing native Reader selection assertions**

Add assertions that require all missing boundaries:

```swift
assertContains(
    nativeReader,
    "const browserSelection = window.getSelection();\n                    if (browserSelection && !browserSelection.isCollapsed) { return; }",
    "native Reader drag selection must bypass click lookup so WebKit keeps the selected range"
)
assertContains(
    nativeReader,
    "config.userContentController.add(context.coordinator, name: \"selectionState\")",
    "native Reader must receive browser selection state for its AppKit context menu"
)
assertContains(
    nativeReader,
    "webView.configuration.userContentController.removeScriptMessageHandler(forName: \"selectionState\")",
    "native Reader must remove its selection-state script handler"
)
assertContains(
    nativeReader,
    "override func menu(for event: NSEvent) -> NSMenu?",
    "native Reader must extend the standard WebKit context menu"
)
assertContains(
    nativeReader,
    "let menu = super.menu(for: event) ?? NSMenu()",
    "native Reader must preserve WebKit standard context-menu items"
)
assertContains(
    nativeReader,
    "window.hoshiHighlights.createHighlight",
    "native Reader highlight actions must reuse the shared JavaScript range creator"
)
assertContains(
    nativeReader,
    "case \"selectionState\":",
    "native Reader must update native menu eligibility from browser selection state"
)
assertContains(
    nativeReader,
    "onHighlightCreated: model.addHighlight",
    "native Reader must forward WebView highlight creation into the book model"
)
assertContains(
    nativeReader,
    "func addHighlight(_ color: HighlightColor, _ creation: HighlightData)",
    "native Reader model must expose book-scoped highlight persistence"
)
assertContains(
    nativeReader,
    "try? BookStorage.save(highlights, inside: rootURL, as: FileNames.highlights)",
    "native Reader must persist created highlights in the current book"
)
for key in ["Yellow", "Green", "Blue", "Pink", "Purple"] {
    assertLocalized(
        localizationStrings,
        key,
        languages: ["en", "zh-Hans"],
        "native Reader highlight colors should have English and Simplified Chinese localization"
    )
}
```

- [ ] **Step 2: Run the focused contract and verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache \
xcrun swiftc -parse-as-library \
  Features/Reader/ReaderWebView/ReaderViewportGeometry.swift \
  script/test_reader_popup_sasayaki_regressions.swift \
  -o /tmp/test_reader_popup_sasayaki_regressions && \
/tmp/test_reader_popup_sasayaki_regressions
```

Expected: `FAIL` at the first newly added assertion, reporting that the native Reader drag selection guard is missing. Confirm the test compiled and failed on behavior, not syntax.

### Task 2: Preserve WebKit drag selection

**Files:**
- Modify: `NativeMac/NativeReaderView.swift` inside the injected Reader `click` listener
- Test: `script/test_reader_popup_sasayaki_regressions.swift`

- [ ] **Step 1: Guard the click-to-lookup listener with the browser selection**

Change the injected listener to:

```javascript
document.addEventListener('click', event => {
    if (event.target?.closest?.('a, button, input, textarea, select, [contenteditable="true"]')) { return; }
    const browserSelection = window.getSelection();
    if (browserSelection && !browserSelection.isCollapsed) { return; }
    const selected = window.hoshiSelection.selectText(event.clientX, event.clientY, lookupScanLength);
    if (!selected) { webkit.messageHandlers.tapOutside.postMessage(null); }
}, true);
```

This deliberately does not clear the selection or send `tapOutside` after a drag.

- [ ] **Step 2: Run the focused contract and confirm it advances past the drag-selection assertion**

Run the Task 1 command.

Expected: the drag-selection assertion passes; the test remains RED at the next missing native highlight-menu assertion.

### Task 3: Restore the native AppKit highlight bridge and persistence

**Files:**
- Modify: `NativeMac/NativeReaderView.swift` in `NativeReaderModel`, `NativeReaderView`, `NativeReaderWKWebView`, `NativeReaderWebView`, and its `Coordinator`
- Test: `script/test_reader_popup_sasayaki_regressions.swift`

- [ ] **Step 1: Add book-scoped persistence to `NativeReaderModel`**

Add next to `removeHighlight`:

```swift
func addHighlight(_ color: HighlightColor, _ creation: HighlightData) {
    guard let range = chapterRange, let rootURL else { return }
    highlights.append(Highlight(
        id: creation.id,
        character: range.start + creation.start,
        offset: creation.offset,
        text: creation.text,
        color: color,
        createdAt: Date()
    ))
    try? BookStorage.save(highlights, inside: rootURL, as: FileNames.highlights)
}
```

Do not bump `highlightRevision`: `highlights.js` already renders the newly created range in the live document, and forcing a reload would disturb Reader state.

- [ ] **Step 2: Extend `NativeReaderWKWebView`'s standard menu**

Add selection state and callback properties, build a submenu only for an active selection, and retain the standard WebKit menu:

```swift
final class NativeReaderWKWebView: WKWebView, ShortcutEventDispatchResponder {
    weak var shortcutManager: ShortcutManager?
    var hasSelection = false
    var onHighlightCreated: ((HighlightColor, HighlightData) -> Void)?
    private static let highlightMenuIdentifier = NSUserInterfaceItemIdentifier("hoshi.reader.highlights")

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard hasSelection else { return menu }

        if let existingItem = menu.items.first(where: { $0.identifier == Self.highlightMenuIdentifier }) {
            menu.removeItem(existingItem)
        }

        let submenu = NSMenu(title: String(localized: "Highlights"))
        for color in HighlightColor.allCases {
            let item = NSMenuItem(
                title: color.localizedName,
                action: #selector(createHighlight(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = color.rawValue
            submenu.addItem(item)
        }

        let item = NSMenuItem(title: String(localized: "Highlights"), action: nil, keyEquivalent: "")
        item.identifier = Self.highlightMenuIdentifier
        item.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: String(localized: "Highlights"))
        item.submenu = submenu
        menu.insertItem(item, at: 0)
        return menu
    }

    @objc private func createHighlight(_ sender: NSMenuItem) {
        guard hasSelection,
              let rawValue = sender.representedObject as? String,
              let color = HighlightColor(rawValue: rawValue) else {
            return
        }
        let id = UUID()
        let script = "window.hoshiHighlights.createHighlight('\\(color.rawValue)', '\\(id.uuidString)')"
        evaluateJavaScript(script) { [weak self] result, _ in
            guard let body = result as? [String: Any],
                  let start = body["start"] as? Int,
                  let offset = body["offset"] as? Int,
                  let text = body["text"] as? String else {
                return
            }
            self?.hasSelection = false
            self?.onHighlightCreated?(color, HighlightData(
                id: id,
                start: start,
                offset: offset,
                text: text
            ))
        }
    }

    override func keyDown(with event: NSEvent) {
        if shortcutManager?.handleKeyDown(event) == true { return }
        super.keyDown(with: event)
    }
}
```

The identifier prevents duplicate Hoshi submenus if WebKit reuses an `NSMenu` instance. Do not remove or reorder WebKit's other items.

- [ ] **Step 3: Wire selection state and highlight callbacks through `NativeReaderWebView`**

Add:

```swift
var onHighlightCreated: (HighlightColor, HighlightData) -> Void
```

Register the existing JS message in `makeNSView`:

```swift
config.userContentController.add(context.coordinator, name: "selectionState")
```

After constructing the native web view, forward the callback without retaining the coordinator:

```swift
let coordinator = context.coordinator
webView.onHighlightCreated = { [weak coordinator] color, creation in
    coordinator?.parent.onHighlightCreated(color, creation)
}
```

Remove the handler in `dismantleNSView`:

```swift
webView.configuration.userContentController.removeScriptMessageHandler(forName: "selectionState")
```

Handle its message before the other selection payload:

```swift
case "selectionState":
    guard let hasSelection = message.body as? Bool,
          let webView = message.webView as? NativeReaderWKWebView else {
        return
    }
    webView.hasSelection = hasSelection
```

At the `NativeReaderWebView` call site, add:

```swift
onHighlightCreated: model.addHighlight,
```

- [ ] **Step 4: Run the focused contract and verify the Swift source contracts advance to localization**

Run the Task 1 command.

Expected: menu bridge and persistence assertions pass; the test remains RED only for missing color localizations.

### Task 4: Localize highlight color menu items

**Files:**
- Modify: `Models/Highlight.swift`
- Modify: `Localizable.xcstrings`
- Test: `script/test_reader_popup_sasayaki_regressions.swift`

- [ ] **Step 1: Give every highlight color an explicit localized name**

Add to `HighlightColor`:

```swift
var localizedName: String {
    switch self {
    case .yellow: String(localized: "Yellow")
    case .green: String(localized: "Green")
    case .blue: String(localized: "Blue")
    case .pink: String(localized: "Pink")
    case .purple: String(localized: "Purple")
    }
}
```

- [ ] **Step 2: Add English and Simplified Chinese xcstrings entries**

Add `Yellow`, `Green`, `Blue`, `Pink`, and `Purple`. Use the English words as English values and `黄色`, `绿色`, `蓝色`, `粉色`, and `紫色` as `zh-Hans` values. Preserve the xcstrings JSON structure and all unrelated translations.

- [ ] **Step 3: Run the focused contract and verify GREEN**

Run the Task 1 command.

Expected final line:

```text
reader popup/Sasayaki regressions passed
```

- [ ] **Step 4: Inspect the scoped diff**

Run:

```bash
git diff --check -- NativeMac/NativeReaderView.swift Models/Highlight.swift Localizable.xcstrings script/test_reader_popup_sasayaki_regressions.swift
git diff -- NativeMac/NativeReaderView.swift Models/Highlight.swift Localizable.xcstrings script/test_reader_popup_sasayaki_regressions.swift
```

Expected: no whitespace errors; no unrelated existing Reader/statistics changes are removed.

### Task 5: Update the Reader verification truth source and validate the exact app

**Files:**
- Modify: `docs/READER_REGRESSION_TESTING.md`
- Verify: exact native Light app

- [ ] **Step 1: Extend the actual-data matrix**

Add this bullet after the lookup bullet:

```markdown
- native text selection and highlights: drag across text without opening click lookup, Copy from the standard context menu, create each highlight color, delete a highlight, and reopen the book to confirm persistence;
```

- [ ] **Step 2: Run the focused regression contract fresh**

Run the Task 1 command again.

Expected: exit 0 and `reader popup/Sasayaki regressions passed`.

- [ ] **Step 3: Build, launch, and verify the exact Light app identity**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: exit 0, bundle id `moe.shishamo.hoshi`, and the running executable path inside the exact DerivedData `.app` reported by the script. A signing-certificate failure is environment evidence, not automatically a code regression; report it exactly if encountered.

- [ ] **Step 4: Perform safe actual-EPUB interaction checks**

Using the exact app launched in Step 3 and an already-present book only, check:

1. A normal click still opens lookup.
2. Dragging text leaves the native selection visible and does not open lookup.
3. Copy returns selected base text without furigana annotations.
4. Right-click keeps WebKit's standard items and shows the localized Highlights submenu.
5. Each color creates a visible highlight; deletion from Highlights removes it.
6. Closing and reopening the same book retains the highlight.
7. Repeat selection in horizontal/vertical and paginated/continuous modes if those settings can be changed and restored safely.

Do not import, replace, rename, or delete books. Restore any Reader settings changed for validation. Record any matrix item not exercised rather than claiming it passed.

- [ ] **Step 5: Final scope and status check**

Run:

```bash
git diff --check
git status --short --branch
```

Expected: only pre-existing user changes plus the explicitly planned files are modified; no commit, tag, push, or release action has occurred.
