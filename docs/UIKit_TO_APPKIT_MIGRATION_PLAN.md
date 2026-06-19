# UIKit To AppKit Migration Plan

Hoshi Reader Mac now has one native macOS target named `Hoshi Reader`. Existing Catalyst releases remain historical artifacts, but Catalyst is no longer present as source, target, build path, or release path.

## Completed

- The native App owns the existing product name and bundle id `moe.shishamo.hoshi`.
- `NativeMac/` provides the App entry, sidebar/detail navigation, Reader, windows, menus, focus, and AppKit hosting.
- Shared SwiftUI screens, models, storage, dictionary, AnkiConnect, sync, local audio, and Sasayaki services remain in their existing feature boundaries.
- UIKit branches, Catalyst Reader/Popup wrappers, ShareExtension coupling, Catalyst scheme membership, and Catalyst build scripts are removed.
- `script/build_and_run.sh` and `script/build_and_run_native.sh` build the same native target, reject a product whose bundle id is not `moe.shishamo.hoshi`, and verify the running executable belongs to the resolved build product.
- `script/package_mac.sh` and `.github/workflows/release-mac.yml` remove all code signatures and build an unnotarized native DMG and checksum.
- Retired Reader fixtures, Regression Lab, metrics, and screenshot harness were removed; Reader visual claims now require actual EPUB validation against `Hoshi Reader`.
- The native startup path preserves existing Google Drive credentials, and `script/verify_native_upgrade_contract.sh` locks the stable product and persistence contract.
- `script/audit_native_upgrade_data.sh` verifies existing books, dictionaries, sidecars, Anki JSON, defaults, and token presence without modifying or exposing user data.
- Finder document opens and the `hoshi://search` / `hoshi://open` URL scheme route through the native sidebar to the reused bookshelf and dictionary features.
- Reader-affecting pull requests build the native App and run lightweight Reader contracts; screenshots and visual correctness remain actual-data/manual evidence.
- An earlier isolated `v0.5.0` Catalyst-to-native replacement validated the shared file layout, but it used the former `de.manhhao.hoshi` identity. It is historical evidence, not proof that the current `moe.shishamo.hoshi` defaults domain inherits legacy preferences.

## Remaining Hardening

1. Validate remaining Settings, Bookshelf, and Dictionary appearance across window sizes.
2. Validate Google Drive auth/token lifecycle with a real account.
3. Validate AnkiConnect recovery, controllers, and external/local audio with available hardware and services.
4. Add signing and notarization only after the release policy changes; they are not part of the current unsigned pipeline.
5. Re-run native UI checks that previously used an ambiguous app name; only the exact DerivedData product with bundle id `moe.shishamo.hoshi` counts as evidence.
6. Add and isolate-test a known-key-only migration from the legacy `de.manhhao.hoshi` defaults domain without overwriting current values or clearing Google credentials.

## Rules

- Do not reintroduce UIKit or a Catalyst compatibility target.
- Use AppKit only for macOS capabilities that SwiftUI does not cover cleanly.
- Preserve user data compatibility even though binary/platform compatibility was removed.
- Reader, popup, sync, Anki, and Sasayaki changes require focused validation before completion claims.
- GUI automation must target the exact built `.app` path or `moe.shishamo.hoshi`, never only the display/process name `Hoshi Reader`.

## Validation

```bash
./script/build_and_run.sh --verify
./script/verify_native_release_contract.sh
./script/verify_native_upgrade_contract.sh
./script/audit_native_upgrade_data.sh
./script/verify_reader_harness.sh
```
