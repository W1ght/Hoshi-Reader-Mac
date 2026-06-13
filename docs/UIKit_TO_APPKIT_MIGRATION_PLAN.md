# UIKit To AppKit Migration Plan

Hoshi Reader Mac is migrating from the shipping Mac Catalyst app to a native macOS app. The migration keeps proven SwiftUI screens, models, storage, and services, while replacing UIKit/Catalyst implementation edges with macOS SwiftUI and narrow AppKit capabilities.

## Product Baseline

- `Hoshi Reader` remains the shipping and release baseline.
- `Hoshi Reader Native` is the replacement candidate and must not become the release path until feature, persistence, interaction, and Reader regression gates pass.
- Mac user-visible behavior is authoritative. Upstream iOS behavior is reference material, not a reason to regress desktop behavior.
- Persistence paths, bundle/container changes, bookmarks, sidecars, tokens, and user settings require explicit upgrade-risk review.

## Migration Method

1. Reuse shared SwiftUI screens and business services when their Mac behavior is already sound.
2. Remove iOS-only behavior that has no Mac product role.
3. Isolate platform dependencies behind small capability-owned boundaries.
4. Add native AppKit implementations only where macOS requires them.
5. Validate the native path against the Catalyst baseline before deleting the Catalyst implementation.
6. Migrate Reader, Popup, and WebView edges last and only with fixture, screenshot, and interaction evidence.

Do not duplicate or rewrite a whole screen merely to make it native. AppKit is appropriate for windows, panels, responder-chain behavior, key capture, menus, focus, file selection, titlebar/chrome integration, and `NSView`/`WKWebView` lifecycle.

## Phase Status

| Phase | Status | Current result |
| --- | --- | --- |
| 0. Platform inventory | Complete for the current codebase | UIKit/Catalyst dependencies are classified in `docs/MAC_NATIVE_MIGRATION_INVENTORY.md` |
| 1. Remove iOS-only branches | Substantially complete | Mac paths use AnkiConnect, Mac lifecycle behavior, Mac storage assumptions, and Mac-only layout decisions |
| 2. Capability boundaries | Complete for low-risk edges | Shortcut capture, CSS editing, dictionary search, artwork, appearance, OAuth anchor, Reader chrome sync, and URL opening have owned boundaries |
| 3. Low-risk AppKit bridges | Complete for the current inventory | Native implementations exist for the low-risk boundaries required by shared screens |
| 4. Native target and shell | Complete | `Hoshi Reader Native` builds independently and hosts native sidebar/detail navigation |
| 5. Shared feature reuse | Functionally advanced | Bookshelf metadata, dictionary lookup/rendering, Settings, Reader, popup lookup, statistics, highlights, and Sasayaki paths are present |
| 6. Validation and hardening | Active | Interactive visual validation, real-account integrations, hardware paths, Reader baselines, and CI artifacts remain |
| 7. High-risk WebView replacement | Pending evidence | Catalyst Reader/Popup wrappers remain until native behavior is proven across the regression matrix |
| 8. Release cutover | Not started | Catalyst remains the shipping target until all cutover gates pass |

## Active Work

### Validation And Hardening

- Validate every native Settings section with the outer sidebar expanded and collapsed.
- Validate immediate System/Light/Dark switching, grouped card backgrounds, segmented controls, focus, keyboard navigation, and window resizing.
- Validate Reader enter/exit, chrome/background restoration, normal/resized/full-screen windows, popup placement, and image viewing.
- Validate Google Drive login, callback, token refresh, logout, and restart state with a real account.
- Validate AnkiConnect recovery and hardware-dependent controller/audio behavior where local equipment is available.
- Select stable Reader screenshot baselines and publish screenshot, geometry, and diff artifacts for Reader-affecting CI runs.

### High-Risk Migration Order

1. Popup window/chrome and coordinate bridges around the shared dictionary renderer.
2. Fullscreen image viewer replacement.
3. Continuous Reader `WKWebView` wrapper.
4. Paginated Reader `WKWebView` wrapper and mouse-wheel/selection behavior.
5. Reader shell/chrome cleanup after WebView behavior is stable.

For each item, keep Catalyst and native behavior comparable until the corresponding visual and interaction matrix passes. Do not combine pagination, popup coordinate, safe-area, and chrome changes into one unreviewable rewrite.

## Cutover Gates

The native app can replace Catalyst only when all of the following are true:

- Bookshelf, import, dictionary, Settings, Reader, popup lookup, statistics, highlights, Sasayaki, AnkiConnect, local audio, shortcuts, and sync are functionally available.
- Existing user books, sidecars, bookmarks, dictionary configuration, Anki configuration, tokens, and UserDefaults survive upgrade testing.
- Reader regression coverage passes for horizontal/vertical, paginated/continuous, normal/resized/full-screen, chapter boundaries, image pages, popup/nested popup, and Sasayaki highlight states.
- Google Drive auth and sync pass real-account validation.
- Native signing, entitlements, packaging, notarization, DMG creation, update behavior, and release workflow are verified.
- The Catalyst app remains buildable until the native release decision is explicit and reversible.

## Validation Entry Points

```bash
./script/build_and_run_catalyst.sh --verify
./script/build_and_run_native.sh --verify
./script/verify_reader_harness.sh
```

Reader-affecting work must also follow `docs/READER_REGRESSION_TESTING.md`. Signing and release failures must be separated from source/build regressions.
