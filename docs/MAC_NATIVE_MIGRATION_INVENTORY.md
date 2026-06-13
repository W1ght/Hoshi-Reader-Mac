# Mac Native Migration Inventory

This inventory tracks remaining UIKit, Catalyst, and iOS-shaped dependencies after the Mac-only migration started. It is a working checklist, not an execution log.

## Principles

- Hoshi Reader Mac is the product; do not keep iOS compatibility branches for theoretical reuse.
- Keep SwiftUI screens where they already behave well on Mac.
- Replace UIKit/Catalyst edges by small Mac capabilities, not by rewriting whole screens.
- Treat Reader, WKWebView, popup coordinates, and Google Drive sync as high-risk areas.

## Current Phase

The current inventory has completed the low-risk extraction, native-shell, and Reader regression-tool migration stages. Native is now the sole development target; work is in validation and Catalyst deletion:

- Prove native Settings, Bookshelf, Dictionary, Reader chrome, and popup behavior interactively across appearance, sidebar, window-size, and full-screen variants.
- Prove Google Drive, AnkiConnect, local audio, Sasayaki, and controller paths with the required accounts or hardware.
- Select stable Native Reader screenshot baselines and add CI artifacts.
- Remove remaining Catalyst WebView wrappers, UIKit bridges, target membership, scripts, and release assumptions in reviewable slices.

## Done

- Added an isolated native macOS app shell target, `Hoshi Reader Native`, backed by `NativeMac/`. Build/run entry points are split between `script/build_and_run_catalyst.sh` and `script/build_and_run_native.sh`.
- Added a native macOS shell UI with sidebar and toolbar navigation for Bookshelf, Dictionary, Reader, and Settings surfaces.
- Reused existing SwiftUI settings pages inside the native Settings surface, backed by the existing `UserConfig` model and shared services.
- Native Settings uses a shared grouped-card form layer for reused SwiftUI settings pages, with explicit native page/card palettes, stable detail-width layout, compact glass-style segmented controls, and immediate System/Light/Dark appearance refresh.
- Added native Bookshelf and Dictionary lookup surfaces that reuse existing storage and lookup services: `BookStorage` for local book metadata/progress and `LookupEngine` for dictionary queries.
- Added a native in-tab Reader path backed by `WKWebView`, local bookmarks, popup lookup, statistics, highlight list, image viewing, mouse wheel paging, and Sasayaki playback. Reader remains the highest-risk native surface and needs native visual regression coverage before release.
- Ported the Debug Reader Regression Lab, deterministic scenario launcher, settings/bookmark restoration, Reader metrics, popup/Sasayaki automation, window discovery, and screenshot capture harness to `Hoshi Reader Native`.
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
- Low-risk native bridge pass is complete for the current inventory: CSS editor selection/insertion, shortcut capture, dictionary search field, shortcut event mapping, Google Drive presentation anchor, Reader chrome background sync, Sasayaki artwork, app appearance isolation, WebView preloader isolation, and Bookshelf update URL opening have native-safe paths or are confirmed Catalyst-only.

## Completed Low-Risk Candidate Notes

### CSS Editor

Current behavior:

- Uses SwiftUI `TextEditor`.
- `CSSEditorView` stays SwiftUI-only.
- `CSSEditorTextViewBridge` uses `UITextView` on Catalyst and a narrow AppKit `NSTextView` accessor on native macOS.
- The bridge disables smart quotes, dashes, and automatic text replacement where the platform supports it.
- The bridge exposes live selection, insertion, cursor placement, and focus restore through a narrow handle.
- Dictionary selector snippets are generated by pure Swift logic in `CSSEditorSnippet`.

### Keyboard Shortcut Capture

Current behavior:

- `KeyboardShortcutsView` stays SwiftUI-only and delegates capture to `ShortcutKeyCaptureView`.
- Shows a zero-sized platform capture view only while recording.
- Captures `UIPress`/`UIKey` on Catalyst and `NSEvent` through `NSViewRepresentable` on native macOS.
- Converts captured keys to `ReaderKeyboardShortcut` through the shared platform bridge.
- Escape cancel is handled by the native AppKit capture path.
- Keep `ReaderKeyboardShortcut` as the shared storage model.

### Dictionary Search Field

Current behavior:

- `CustomSearchField` is SwiftUI-only and preserves the existing `searchText`, `isFocused`, and `onSubmit` API.
- `DictionarySearchTextFieldBridge` owns the custom platform text field.
- Catalyst uses `UITextField` and keeps the existing Japanese input mode preference.
- Native macOS uses `NSTextField`, preserves continuous typing, return-to-submit, and focus restoration without forcing system input source changes.

### Other Low-Risk Edges

- Sasayaki now playing artwork uses `UIImage` only on Catalyst and `NSImage` on native macOS.
- `GoogleDrivePresentationAnchor` uses `UIApplication` only on Catalyst and `NSApplication` / `NSWindow` on native macOS; OAuth semantics are unchanged.
- `ReaderChromeBackgroundSync` is platform conditional: Catalyst keeps the existing `UIViewControllerRepresentable` window sync, native macOS uses a narrow `NSViewRepresentable` window background sync.
- `AppAppearance` is Catalyst-only appearance tuning; native macOS has no UIKit dependency there.
- `WebViewPreloader` is already WebKit-only and has no UIKit dependency.
- Bookshelf update/download URL opening uses SwiftUI `openURL`; no adjacent `UIApplication.shared.open` remains in the Bookshelf update path.

## Medium-Risk Candidates

| Area | Files | Current dependency | Suggested next step | Risk |
| --- | --- | --- | --- | --- |
| Native Settings visual validation | `NativeMac/NativeReuseViews.swift`, `Features/Settings/*View.swift`, `NativeMac/HoshiNativeMacApp.swift` | Shared SwiftUI settings pages hosted inside the native shell | Validate every settings section with outer sidebar expanded/collapsed, Light/Dark/System switching, grouped card backgrounds, and compact controls before treating Settings as native-stable | Medium |
| Google Drive auth flow validation | `Features/Sync/GoogleDriveAuth.swift`, `Features/Sync/GoogleDrivePresentationAnchor.swift` | ASWebAuthenticationSession and token callback state | Validate login, callback, token refresh, logout, and restart state before further auth changes | Medium/High |
| Bookshelf chrome sync validation | `Features/Bookshelf/ReaderChromeBackgroundSync.swift` | Window background mutation while Reader is active | Validate Reader enter/exit, tab switch, and full-screen background restoration before further changes | Medium |

## Catalyst Deletion Queue

| Area | Files | Legacy dependency | Native/removal requirement |
| --- | --- | --- | --- |
| Reader shell and chrome | `Features/Reader/ReaderView/ReaderView.swift` | `AppPlatform.usesDesktopLayout`, safe area, `UIViewControllerRepresentable` chrome helpers | Reader layout has recent regressions; changes need fixture/screenshot validation |
| Paginated Reader WebView | `Features/Reader/ReaderWebView/ReaderWebView.swift`, `reader.js` | `UIViewRepresentable`, WKWebView scroll/selection bridge, `UIApplication.shared.open` | Highest risk for pagination, mouse wheel, selection, popup coordinates |
| Continuous Reader WebView | `Features/Reader/ScrollReaderWebView/ScrollReaderWebView.swift`, `scrollreader.js` | `UIViewRepresentable`, layout constants, link opening | High risk for scroll position, chapter boundaries, and visual regression |
| Popup WebView | `Features/Popup/PopupWebView.swift` | `UIViewRepresentable`, keyboard handling, external URL opening, popup coordinates | Popup and dictionary rendering must stay aligned |
| Fullscreen image viewer | `Features/Reader/ReaderView/FullscreenImageView.swift` | UIKit zoom wrapper | User-visible Reader media path; replace only with visual verification |

## Validation Gates

- `Hoshi Reader Native` verification is the required build gate. Catalyst compile failures do not block migration work.
- Catalyst deletion must not silently change shared persistence or service behavior.
- For dictionary/popup visual changes, capture screenshots before and after.
- For Reader changes, use `docs/READER_REGRESSION_TESTING.md` and fixture screenshots where possible.
- For sync/auth changes, verify login, token refresh, logout, and restart state before claiming done.
- Remove Catalyst implementations as soon as the Native path and affected user-data behavior have the required evidence.
