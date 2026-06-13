# Mac Native Migration Inventory

This inventory records the current native macOS architecture and the remaining validation risks.

## Current Architecture

- One Xcode App target and scheme: `Hoshi Reader`.
- Product: `Hoshi Reader.app`.
- Bundle id: `de.manhhao.hoshi`.
- App entry and native shell: `NativeMac/`.
- Shared services and feature UI: `Core/`, `Features/`, `Models/`, and `Util/`.
- AppKit bridges: shortcut capture, shortcut event mapping, CSS editor text access, dictionary search field, Google OAuth presentation anchor, Reader window background, and native WKWebView hosting.
- Release artifact: native DMG with all code signatures removed, no notarization, plus SHA-256 checksum.

## Removed

- Mac Catalyst target, scheme behavior, build destination, and release product lookup.
- `App/` Catalyst entry helpers and `ShareExtension/`.
- UIKit branches and Catalyst-only platform conditions.
- Catalyst Reader shell, paginated/continuous Swift wrappers, fullscreen image wrapper, and Popup `UIViewRepresentable`.
- SwiftUI Introspect dependency used by the Catalyst CSS editor path.
- Catalyst build/run script and Catalyst assumptions in the Reader harness.

The shared `reader.js`, `scrollreader.js`, selection, highlight, and popup assets remain because the native Reader uses them.

## Remaining Risk

| Area | Required evidence |
| --- | --- |
| Reader/WKWebView | Horizontal/vertical, paginated/continuous, normal/resized/full-screen, boundaries, images, popup, nested popup, Sasayaki highlight |
| Persistence upgrade | Existing books, bookmarks, sidecars, dictionaries, Anki config, tokens, and UserDefaults survive upgrade from the last Catalyst release |
| Google Drive | Login, callback, refresh, logout, restart, and sync conflict behavior with a real account |
| AnkiConnect | Reconnect, fetch preservation, successful/duplicate/failed mining |
| Audio/controllers | Local word audio, Sasayaki controls, external audio behavior, supported controllers |
| Release | Native DMG contents, checksum, install/open instructions, and an explicit decision about future signing/notarization |

## Gates

- `./script/build_and_run.sh --verify` is the default build gate.
- `./script/verify_native_release_contract.sh` prevents the retired target and release assumptions from returning.
- `./script/verify_reader_harness.sh` is required for Reader-affecting work.
- UI, account, and hardware behavior must not be claimed as verified unless it was exercised.
