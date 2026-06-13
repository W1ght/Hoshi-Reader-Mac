# UIKit To AppKit Migration Plan

Hoshi Reader Mac is now developed exclusively as a native macOS app. Existing Catalyst releases remain downloadable historical artifacts, but Catalyst compatibility is no longer a product requirement. The migration keeps proven SwiftUI screens, models, storage, and services while deleting UIKit/Catalyst implementation edges in controlled slices.

## Product Baseline

- `Hoshi Reader Native` is the sole development target and the only candidate for future releases.
- `Hoshi Reader` is a legacy Catalyst target pending deletion. It may be inspected for historical behavior or data-format intent, but it receives no new features and is not a required build.
- Mac user-visible behavior is authoritative. Upstream iOS behavior is reference material, not a reason to regress desktop behavior.
- Persistence paths, bundle/container changes, bookmarks, sidecars, tokens, and user settings require explicit upgrade-risk review.

## Migration Method

1. Reuse shared SwiftUI screens and business services when their Mac behavior is already sound.
2. Remove iOS-only behavior that has no Mac product role.
3. Isolate platform dependencies behind small capability-owned boundaries.
4. Add native AppKit implementations only where macOS requires them.
5. Validate the native path against explicit user behavior and data requirements, not Catalyst compile parity.
6. Delete Catalyst branches and files once the corresponding native capability and migration safety are established.

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
| 6. Native validation and hardening | Active | Interactive visual validation, real-account integrations, hardware paths, Native Reader baselines, and CI artifacts remain |
| 7. Catalyst removal | Active | Remove legacy target code, UIKit bridges, scripts, tests, and project membership in verified slices |
| 8. Native release pipeline | Pending | Replace Catalyst archive/DMG assumptions before the next release |

## Active Work

### Validation And Hardening

- Validate every native Settings section with the outer sidebar expanded and collapsed.
- Validate immediate System/Light/Dark switching, grouped card backgrounds, segmented controls, focus, keyboard navigation, and window resizing.
- Validate Reader enter/exit, chrome/background restoration, normal/resized/full-screen windows, popup placement, and image viewing.
- Validate Google Drive login, callback, token refresh, logout, and restart state with a real account.
- Validate AnkiConnect recovery and hardware-dependent controller/audio behavior where local equipment is available.
- Select stable Reader screenshot baselines and publish screenshot, geometry, and diff artifacts for Reader-affecting CI runs.

### Catalyst Removal Order

1. Completed: port the Reader Regression Lab, scenario launcher, metrics, and screenshot capture to Native.
2. Remove low-risk Catalyst-only helpers and dead `#if targetEnvironment(macCatalyst)` branches.
3. Remove Catalyst Popup, fullscreen image, continuous Reader, and paginated Reader wrappers after Native coverage exists.
4. Remove the Catalyst app target, ShareExtension coupling, schemes, and target memberships.
5. Remove Catalyst build/run scripts and Catalyst assertions from tests and docs.
6. Replace Catalyst release archive, signing, and DMG workflow with the Native pipeline.

Do not keep a dual-platform abstraction solely to preserve Catalyst. A removal slice must keep Native building and must preserve user data and the affected Native behavior. Reader pagination, popup coordinates, safe area, and chrome should still be removed in separate reviewable slices.

## Native Release Gates

The next release can ship only when all of the following are true:

- Bookshelf, import, dictionary, Settings, Reader, popup lookup, statistics, highlights, Sasayaki, AnkiConnect, local audio, shortcuts, and sync are functionally available.
- Existing user books, sidecars, bookmarks, dictionary configuration, Anki configuration, tokens, and UserDefaults survive upgrade testing.
- Reader regression coverage passes for horizontal/vertical, paginated/continuous, normal/resized/full-screen, chapter boundaries, image pages, popup/nested popup, and Sasayaki highlight states.
- Google Drive auth and sync pass real-account validation.
- Native signing, entitlements, packaging, notarization, DMG creation, update behavior, and release workflow are verified.
- The Catalyst target and release assumptions have been removed or are isolated from the Native archive path.
- `script/release_mac.sh` and `.github/workflows/release-mac.yml` have been replaced or verified to archive the Native target rather than Catalyst.

## Validation Entry Points

```bash
./script/build_and_run_native.sh --verify
./script/verify_reader_harness.sh
```

Reader-affecting work must also follow `docs/READER_REGRESSION_TESTING.md`. Signing and release failures must be separated from source/build regressions.
