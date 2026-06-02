# Mac Native Migration Inventory

This inventory tracks remaining UIKit, Catalyst, and iOS-shaped dependencies after the Mac-only migration started. It is a working checklist, not an execution log.

## Principles

- Hoshi Reader Mac is the product; do not keep iOS compatibility branches for theoretical reuse.
- Keep SwiftUI screens where they already behave well on Mac.
- Replace UIKit/Catalyst edges by small Mac capabilities, not by rewriting whole screens.
- Treat Reader, WKWebView, popup coordinates, and Google Drive sync as high-risk areas.

## Done

- Added an isolated native macOS app shell target, `Hoshi Reader Native`, backed by `NativeMac/`. It intentionally does not import the Catalyst app, Reader, popup, sync, Anki, or dictionary code yet. Build/run entry points are split between `script/build_and_run_catalyst.sh` and `script/build_and_run_native.sh`.
- Added a native macOS shell UI with sidebar and toolbar navigation for Bookshelf, Dictionary, Reader, and Settings placeholders. It remains disconnected from app data and the shipping Catalyst target.
- Reused the existing SwiftUI `StatisticsSettingsView` inside the native Settings placeholder, backed by the existing `UserConfig` model and minimal shared model membership.
- Added native Bookshelf and Dictionary lookup surfaces that reuse existing storage and lookup services: `BookStorage` for local book metadata/progress and `LookupEngine` for dictionary queries. Reader opening, dictionary popup rendering, import, sync, and Anki mining remain deferred.
- Added a native AppKit shortcut-capture probe in `NativeMac/` to validate `NSViewRepresentable` first-responder key capture and Escape cancel behavior before replacing the Catalyst shortcut bridge.
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
- Unused standalone Reader window code was removed; the file now only carries Reader navigation environment values.
- `AppPlatform` is reduced to Mac-only layout constants; the unused Catalyst flag is gone.
- User-configured colors persist as tested hex strings with legacy `UIColor` archive migration.
- Keyboard shortcut capture is isolated behind `ShortcutKeyCaptureView`; the settings page no longer imports UIKit directly. Escape cancel is deferred until the native macOS/AppKit bridge exists because Catalyst does not reliably deliver Escape through this path.
- CSS editor selection and insertion access is isolated behind `CSSEditorTextViewBridge`; selector snippet generation is pure Swift and covered by a script test.
- Dictionary search field is isolated behind `DictionarySearchTextFieldBridge`; `CustomSearchField` is now a SwiftUI wrapper with the existing public bindings.
- Sasayaki Now Playing artwork UIImage handling is isolated behind `SasayakiNowPlayingArtwork`; `SasayakiPlayer` no longer decodes UIKit images directly.
- App entry no longer imports UIKit or WebKit directly; segmented control appearance and WebView preloading are isolated in small app helpers.
- `ReaderKeyboardShortcut` no longer owns UIKit key conversion; `UIKey` mapping lives in `ReaderKeyboardShortcutUIKitBridge`.
- Google Drive authentication presentation anchor lookup is isolated behind `GoogleDrivePresentationAnchor`; OAuth/token flow remains unchanged.
- Bookshelf Reader chrome background sync is isolated behind `ReaderChromeBackgroundSync`; `BookshelfView` passes SwiftUI `Color` and no longer owns the `UIViewControllerRepresentable` implementation.

## Remaining Low-Risk Candidates

| Area | Files | Current dependency | Suggested next step | Risk |
| --- | --- | --- | --- | --- |
| Native macOS shell | `NativeMac/`, `Hoshi Reader.xcodeproj` | SwiftUI shell with Bookshelf metadata, Dictionary lookup, reused Statistics settings, and a shortcut-capture probe | Keep replacing placeholders with existing SwiftUI pages/services one at a time before sharing Reader code | Low |
| Update/download URL opening | `Features/Bookshelf/BookshelfView.swift` | Mostly SwiftUI `openURL`; verify no adjacent `UIApplication.shared.open` remains | No action unless new call sites appear | Low |
| CSS editor text bridge | `Features/Settings/CSSEditorTextViewBridge.swift` | UIKit import for `UITextView` selection and insertion | Replace this narrow bridge with AppKit after a native macOS target exists; preserve cursor insertion, monospaced editing, smart quotes/dashes disabling, and selector snippet insertion | Low/Medium |
| Keyboard shortcut capture bridge | `Features/Settings/ShortcutKeyCaptureView.swift` | `UIViewRepresentable`, `UIPress`, `UIKey` | Replace this narrow bridge with `NSViewRepresentable` when native macOS target starts; preserve single-key, modified-key, Escape cancel, and label behavior | Medium |
| Dictionary search field bridge | `Features/Dictionary/DictionarySearchTextFieldBridge.swift` | `UITextField`, Japanese input mode control | Replace this narrow bridge with AppKit only after confirming Japanese input behavior and focus timing | Medium |
| Sasayaki Now Playing artwork | `Features/Sasayaki/SasayakiNowPlayingArtwork.swift` | `UIImage` for `MPMediaItemArtwork` | Replace this helper with AppKit/CoreGraphics artwork generation if native macOS media APIs allow it | Low/Medium |
| App appearance helper | `App/AppAppearance.swift` | `UISegmentedControl` appearance and `UIFont` | Replace with native SwiftUI/AppKit appearance only after top tab sizing is validated | Low |
| WebView preloader helper | `App/WebViewPreloader.swift` | `WKWebView` warmup | Keep isolated; revisit when Reader WebView migration starts | Low |
| Keyboard shortcut UIKit mapping | `Core/ReaderKeyboardShortcutUIKitBridge.swift` | `UIKey` and `UIKeyModifierFlags` conversion | Replace with an AppKit `NSEvent` bridge when native macOS target starts | Low |
| Google Drive auth presentation anchor | `Features/Sync/GoogleDrivePresentationAnchor.swift` | `UIApplication.shared.connectedScenes` and `UIWindow` | Replace with a native macOS presentation anchor when moving sync auth to AppKit | Medium |
| Bookshelf Reader chrome sync bridge | `Features/Bookshelf/ReaderChromeBackgroundSync.swift` | `UIViewControllerRepresentable` and `UIWindow` background mutation | Replace with native window background control after Reader shell migration is planned | Medium |

## Low-Risk Candidate Notes

### CSS Editor

Current behavior:

- Uses SwiftUI `TextEditor`.
- `CSSEditorView` stays SwiftUI-only.
- `CSSEditorTextViewBridge` introspects the underlying `UITextView`.
- The bridge disables smart quotes and dashes.
- The bridge exposes live selection, insertion, cursor placement, and focus restore through a narrow handle.
- Dictionary selector snippets are generated by pure Swift logic in `CSSEditorSnippet`.

Native Mac replacement shape:

- Prefer keeping SwiftUI `TextEditor` if selection insertion can remain reliable.
- Replace only `CSSEditorTextViewBridge` with an AppKit text view bridge for selection/cursor operations once the native macOS target exists.
- Preserve snippet insertion and focus behavior before removing the UIKit path.

### Keyboard Shortcut Capture

Current behavior:

- `KeyboardShortcutsView` stays SwiftUI-only and delegates capture to `ShortcutKeyCaptureView`.
- Shows a zero-sized `UIViewRepresentable` only while recording.
- Captures `UIPress`/`UIKey`.
- Converts captured keys to `ReaderKeyboardShortcut`.
- Escape cancel is not reliable in the Catalyst bridge and should be handled by the future AppKit bridge.

Native Mac replacement shape:

- Use a zero-sized `NSViewRepresentable` with `keyDown` capture.
- Keep `ReaderKeyboardShortcut` as the shared storage model.
- Validate plain keys, modified keys, Escape/cancel behavior, and label rendering.
- The native shell now contains a probe for first-responder key capture and Escape cancel; the next production step is to map this event result into `ReaderKeyboardShortcut` without importing AppKit into the storage model.

### Dictionary Search Field

Current behavior:

- `CustomSearchField` is SwiftUI-only and preserves the existing `searchText`, `isFocused`, and `onSubmit` API.
- `DictionarySearchTextFieldBridge` owns the custom `UITextField`.
- The bridge forces Japanese input mode when possible.
- The bridge defers focus until the field is attached to a window or transition completes.

Native Mac replacement shape:

- Replace only `DictionarySearchTextFieldBridge` after confirming how to request Japanese input on AppKit.
- Preserve autofocus behavior for dictionary tab opening and reader lookup jumps.
- Validate typing, search submit, and focus restore after tab changes.

## Medium-Risk Candidates

| Area | Files | Current dependency | Suggested next step | Risk |
| --- | --- | --- | --- | --- |
| Google Drive auth flow validation | `Features/Sync/GoogleDriveAuth.swift`, `Features/Sync/GoogleDrivePresentationAnchor.swift` | ASWebAuthenticationSession and token callback state | Validate login, callback, token refresh, logout, and restart state before further auth changes | Medium/High |
| Bookshelf chrome sync validation | `Features/Bookshelf/ReaderChromeBackgroundSync.swift` | Window background mutation while Reader is active | Validate Reader enter/exit, tab switch, and full-screen background restoration before further changes | Medium |

## High-Risk / Defer

| Area | Files | Current dependency | Why defer |
| --- | --- | --- | --- |
| Reader shell and chrome | `Features/Reader/ReaderView/ReaderView.swift` | `AppPlatform.usesDesktopLayout`, safe area, `UIViewControllerRepresentable` chrome helpers | Reader layout has recent regressions; changes need fixture/screenshot validation |
| Paginated Reader WebView | `Features/Reader/ReaderWebView/ReaderWebView.swift`, `reader.js` | `UIViewRepresentable`, WKWebView scroll/selection bridge, `UIApplication.shared.open` | Highest risk for pagination, mouse wheel, selection, popup coordinates |
| Continuous Reader WebView | `Features/Reader/ScrollReaderWebView/ScrollReaderWebView.swift`, `scrollreader.js` | `UIViewRepresentable`, layout constants, link opening | High risk for scroll position, chapter boundaries, and visual regression |
| Popup WebView | `Features/Popup/PopupWebView.swift` | `UIViewRepresentable`, keyboard handling, external URL opening, popup coordinates | Popup and dictionary rendering must stay aligned |
| Fullscreen image viewer | `Features/Reader/ReaderView/FullscreenImageView.swift` | UIKit zoom wrapper | User-visible Reader media path; replace only with visual verification |

## Validation Gates

- For low-risk non-Reader changes, run Mac Catalyst compile.
- For dictionary/popup visual changes, capture screenshots before and after.
- For Reader changes, use `docs/READER_REGRESSION_TESTING.md` and fixture screenshots where possible.
- For sync/auth changes, verify login, token refresh, logout, and restart state before claiming done.
