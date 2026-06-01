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

## Remaining Low-Risk Candidates

| Area | Files | Current dependency | Suggested next step | Risk |
| --- | --- | --- | --- | --- |
| Update/download URL opening | `Features/Bookshelf/BookshelfView.swift` | Mostly SwiftUI `openURL`; verify no adjacent `UIApplication.shared.open` remains | No action unless new call sites appear | Low |
| Cover image loading | `Util/CoverImage.swift` | `UIImage`/UIKit image path | Keep for Catalyst now; replace with `NSImage` only when native macOS target exists | Low |
| CSS editor | `Features/Settings/CSSEditorView.swift` | UIKit import for text editing | Inventory current editor behavior before replacing with AppKit text view | Low/Medium |
| Keyboard shortcut capture | `Features/Settings/KeyboardShortcutsView.swift` | `UIViewRepresentable`, UIKit key handling | Replace with narrow `NSViewRepresentable` when native macOS target starts | Medium |
| Dictionary search field | `Features/Dictionary/CustomSearchField.swift` | `UITextField`, input mode control | Replace with AppKit search field only after confirming Japanese input behavior | Medium |

## Medium-Risk Candidates

| Area | Files | Current dependency | Suggested next step | Risk |
| --- | --- | --- | --- | --- |
| Dictionary page layout | `Features/Dictionary/DictionarySearchView.swift` | `UIDevice.current.userInterfaceIdiom`, top/bottom inset assumptions | First capture screenshots; then make current Mac inset values explicit | Medium |
| Sasayaki idle behavior | `Features/Sasayaki/SasayakiPlayer.swift` | `UIApplication.shared.isIdleTimerDisabled` | Decide desired Mac behavior first; do not remove blindly if it affects long playback/auto-scroll | Medium |
| Google Drive auth presentation | `Features/Sync/GoogleDriveAuth.swift` | `UIApplication.shared.connectedScenes` presentation anchor | Keep until auth is tested; later replace with a Mac-owned presentation anchor | Medium/High |
| Bookshelf chrome sync | `Features/Bookshelf/BookshelfView.swift` | `UIViewControllerRepresentable` helper for Reader chrome background | Keep while Reader remains Catalyst/WebView-backed | Medium |

## High-Risk / Defer

| Area | Files | Current dependency | Why defer |
| --- | --- | --- | --- |
| Reader shell and chrome | `Features/Reader/ReaderView/ReaderView.swift` | `AppPlatform.usesDesktopLayout`, safe area, UIKit background tasks, `UIViewControllerRepresentable` chrome helpers | Reader layout has recent regressions; changes need fixture/screenshot validation |
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
