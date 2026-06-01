# Mac Native Migration Inventory

This inventory tracks remaining UIKit, Catalyst, and iOS-shaped dependencies after the Mac-only migration started. It is a working checklist, not an execution log.

## Principles

- Hoshi Reader Mac is the product; do not keep iOS compatibility branches for theoretical reuse.
- Keep SwiftUI screens where they already behave well on Mac.
- Replace UIKit/Catalyst edges by small Mac capabilities, not by rewriting whole screens.
- Treat Reader, WKWebView, popup coordinates, and Google Drive sync as high-risk areas.

## Done

- Anki settings use the Mac AnkiConnect path only.
- `AnkiManager` no longer uses AnkiMobile URL callbacks or pasteboard metadata fetch.
- Settings pages no longer hide Mac-only controls behind desktop-layout gates.
- Bookshelf uses the Mac grid and in-tab Reader path.
- `LocalFileServer` no longer uses iOS background task handling.
- Update checks and update toolbar UI use the Mac path directly.
- Google Drive token fallback storage is Mac-only.
- `AppPlatform` now exposes Mac-only constants.
- Cover image loading no longer depends on `UIImage`; SwiftUI receives ImageIO thumbnails as `CGImage`.
- Dictionary page layout now uses explicit Mac safe-area constants instead of `UIDevice` layout checks and `UIApplication` safe-area helpers.
- App startup no longer installs iOS Home Screen Quick Action scene delegates.
- Reader resign-active autosync no longer wraps its flush task in an iOS background task.
- Sasayaki auto-scroll playback uses a Mac `ProcessInfo` activity instead of the iOS idle timer API.
- Reader foreground/background handling uses SwiftUI `scenePhase` instead of `UIApplication` lifecycle notifications.

## Remaining Low-Risk Candidates

| Area | Files | Current dependency | Suggested next step | Risk |
| --- | --- | --- | --- | --- |
| Update/download URL opening | `Features/Bookshelf/BookshelfView.swift` | Mostly SwiftUI `openURL`; verify no adjacent `UIApplication.shared.open` remains | No action unless new call sites appear | Low |
| CSS editor | `Features/Settings/CSSEditorView.swift` | UIKit import for `UITextView` selection and insertion | Keep until an AppKit text view bridge can preserve cursor insertion, monospaced editing, smart quotes/dashes disabling, and selector snippet insertion | Low/Medium |
| Keyboard shortcut capture | `Features/Settings/KeyboardShortcutsView.swift` | `UIViewRepresentable`, `UIPress`, `UIKey` | Replace with narrow `NSViewRepresentable` when native macOS target starts; preserve single-key and modified-key capture labels | Medium |
| Dictionary search field | `Features/Dictionary/CustomSearchField.swift` | `UITextField`, Japanese input mode control | Replace with AppKit search field only after confirming Japanese input behavior and focus timing | Medium |

## Low-Risk Candidate Notes

### CSS Editor

Current behavior:

- Uses SwiftUI `TextEditor`.
- Introspects the underlying `UITextView`.
- Disables smart quotes and dashes.
- Uses the live text view selection to insert font snippets and dictionary selector snippets.
- Restores first responder after insertion.

Native Mac replacement shape:

- Prefer keeping SwiftUI `TextEditor` if selection insertion can remain reliable.
- If not, introduce a narrow AppKit text view bridge only for selection/cursor operations.
- Preserve snippet insertion and focus behavior before removing the UIKit path.

### Keyboard Shortcut Capture

Current behavior:

- Shows a zero-sized `UIViewRepresentable` only while recording.
- Captures `UIPress`/`UIKey`.
- Converts captured keys to `ReaderKeyboardShortcut`.

Native Mac replacement shape:

- Use a zero-sized `NSViewRepresentable` with `keyDown` capture.
- Keep `ReaderKeyboardShortcut` as the shared storage model.
- Validate plain keys, modified keys, Escape/cancel behavior if added later, and label rendering.

### Dictionary Search Field

Current behavior:

- Uses a custom `UITextField`.
- Forces Japanese input mode when possible.
- Defers focus until the field is attached to a window or transition completes.

Native Mac replacement shape:

- Replace only after confirming how to request Japanese input on AppKit.
- Preserve autofocus behavior for dictionary tab opening and reader lookup jumps.
- Validate typing, search submit, and focus restore after tab changes.

## Medium-Risk Candidates

| Area | Files | Current dependency | Suggested next step | Risk |
| --- | --- | --- | --- | --- |
| Google Drive auth presentation | `Features/Sync/GoogleDriveAuth.swift` | `UIApplication.shared.connectedScenes` presentation anchor | Keep until auth is tested; later replace with a Mac-owned presentation anchor | Medium/High |
| Bookshelf chrome sync | `Features/Bookshelf/BookshelfView.swift` | `UIViewControllerRepresentable` helper for Reader chrome background | Keep while Reader remains Catalyst/WebView-backed | Medium |

## High-Risk / Defer

| Area | Files | Current dependency | Why defer |
| --- | --- | --- | --- |
| Reader shell and chrome | `Features/Reader/ReaderView/ReaderView.swift` | `AppPlatform.usesDesktopLayout`, safe area, `UIViewControllerRepresentable` chrome helpers | Reader layout has recent regressions; changes need fixture/screenshot validation |
| Paginated Reader WebView | `Features/Reader/ReaderWebView/ReaderWebView.swift`, `reader.js` | `UIViewRepresentable`, WKWebView scroll/selection bridge, `UIApplication.shared.open` | Highest risk for pagination, mouse wheel, selection, popup coordinates |
| Continuous Reader WebView | `Features/Reader/ScrollReaderWebView/ScrollReaderWebView.swift`, `scrollreader.js` | `UIViewRepresentable`, layout constants, link opening | High risk for scroll position, chapter boundaries, and visual regression |
| Popup WebView | `Features/Popup/PopupWebView.swift` | `UIViewRepresentable`, keyboard handling, external URL opening, popup coordinates | Popup and dictionary rendering must stay aligned |
| Fullscreen image viewer | `Features/Reader/ReaderView/FullscreenImageView.swift` | UIKit zoom wrapper | User-visible Reader media path; replace only with visual verification |
| Reader window utility | `Features/Reader/ReaderView/ReaderWindow.swift` | `UIApplication.shared.connectedScenes`, Catalyst titlebar hooks | Reader/window behavior is fragile; defer until window strategy is clear |

## Validation Gates

- For low-risk non-Reader changes, run Mac Catalyst compile.
- For dictionary/popup visual changes, capture screenshots before and after.
- For Reader changes, use `docs/READER_REGRESSION_TESTING.md` and fixture screenshots where possible.
- For sync/auth changes, verify login, token refresh, logout, and restart state before claiming done.
