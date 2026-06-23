# Mac Native Migration Inventory

This inventory records the current native macOS architecture and the remaining validation risks.

## Current Architecture

- One Xcode App target and scheme: `Hoshi Reader`.
- Product: `Hoshi Reader.app`.
- Bundle id: `moe.shishamo.hoshi`.
- App entry and native shell: `NativeMac/`.
- Native document and URL routing: Finder EPUB/Anki package opens plus `hoshi://search` and `hoshi://open`.
- Shared services and feature UI: `Core/`, `Features/`, `Models/`, and `Util/`.
- AppKit bridges: shortcut capture, shortcut event mapping and system hot-key registration, accessibility selected-text reading, a transient cross-app lookup panel, CSS editor text access, dictionary search field, Google OAuth presentation anchor, Reader window background, and native WKWebView hosting.
- Release artifact: native DMG with all code signatures removed, no notarization, plus SHA-256 checksum.

## Removed

- Mac Catalyst target, scheme behavior, build destination, and release product lookup.
- `App/` Catalyst entry helpers and `ShareExtension/`.
- UIKit branches and Catalyst-only platform conditions.
- Catalyst Reader shell, paginated/continuous Swift wrappers, fullscreen image wrapper, and Popup `UIViewRepresentable`.
- SwiftUI Introspect dependency used by the Catalyst CSS editor path.
- Catalyst build/run script and Catalyst assumptions in Reader validation.

The shared `reader.js`, `scrollreader.js`, selection, highlight, and popup assets remain because the native Reader uses them.

## Remaining Risk

| Area | Required evidence |
| --- | --- |
| Reader/WKWebView | Lightweight contracts cover bridge/static behavior only; visual layout, safe-area clipping, pagination, popup geometry, and Sasayaki highlight require actual EPUB validation against the exact `moe.shishamo.hoshi` build |
| Persistence upgrade | File-based Application Support layouts remain compatible and the Google Keychain service keeps its legacy name, but the prior replacement test predates the move to `moe.shishamo.hoshi`; legacy `de.manhhao.hoshi` UserDefaults and Google Drive fallback/folder metadata need an explicit non-destructive migration and isolated validation |
| Google Drive | Login, callback, refresh, logout, restart, and sync conflict behavior with a real account |
| AnkiConnect | Reconnect, fetch preservation, successful/duplicate/failed mining |
| Audio/controllers | Local word audio, Sasayaki controls, external audio behavior, supported controllers |
| Release | Native DMG contents, checksum, install/open instructions, and an explicit decision about future signing/notarization |
| Runtime identity | Local build/UI evidence must identify `moe.shishamo.hoshi` and match the running executable to the exact DerivedData `.app`; old same-name installs are not valid evidence |

## Gates

- `./script/build_and_run.sh --verify` is the default build gate and must reject a wrong `CFBundleIdentifier` or a same-name process outside the resolved build product.
- `./script/verify_native_release_contract.sh` prevents the retired target and release assumptions from returning.
- `./script/verify_native_upgrade_contract.sh` protects the stable product identity, storage locations, sidecar names, and non-destructive Google Drive token migration.
- `./script/audit_native_upgrade_data.sh` performs a read-only count/JSON/defaults/Keychain presence audit without printing user content or credentials.
- Reader-affecting work uses concern-specific unit/static checks where applicable, followed by the relevant actual-EPUB matrix in `docs/READER_REGRESSION_TESTING.md`.
- The aggregate Reader harness and Reader-specific CI workflow are retired; no generated fixture, screenshot, or static contract result is accepted as Reader visual evidence.
- UI, account, and hardware behavior must not be claimed as verified unless it was exercised against the exact expected app identity.
