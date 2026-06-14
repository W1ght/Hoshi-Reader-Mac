# UIKit To AppKit Migration Plan

Hoshi Reader Mac now has one native macOS target named `Hoshi Reader`. Existing Catalyst releases remain historical artifacts, but Catalyst is no longer present as source, target, build path, or release path.

## Completed

- The native App owns the existing product name and bundle id `de.manhhao.hoshi`.
- `NativeMac/` provides the App entry, sidebar/detail navigation, Reader, windows, menus, focus, and AppKit hosting.
- Shared SwiftUI screens, models, storage, dictionary, AnkiConnect, sync, local audio, and Sasayaki services remain in their existing feature boundaries.
- UIKit branches, Catalyst Reader/Popup wrappers, ShareExtension coupling, Catalyst scheme membership, and Catalyst build scripts are removed.
- `script/build_and_run.sh` and `script/build_and_run_native.sh` build the same native target.
- `script/package_mac.sh` and `.github/workflows/release-mac.yml` remove all code signatures and build an unnotarized native DMG and checksum.
- Reader fixtures, Regression Lab, metrics, and screenshot harness run against `Hoshi Reader`.
- The native startup path preserves existing Google Drive credentials, and `script/verify_native_upgrade_contract.sh` locks the stable product and persistence contract.
- `script/audit_native_upgrade_data.sh` verifies existing books, dictionaries, sidecars, Anki JSON, defaults, and token presence without modifying or exposing user data.
- Finder document opens and the `hoshi://search` / `hoshi://open` URL scheme route through the native sidebar to the reused bookshelf and dictionary features.
- Reader-affecting pull requests build the native App, run the harness, and publish a deterministic capture-plan artifact.
- All 10 native Reader scenarios have local screenshots and metrics, including a real full-screen vertical/Sasayaki-highlight case, SVG cover containment, popup, nested popup, image, chapter-end, paginated, and continuous layouts.
- `testdata/reader-baselines/macos-27.0-webkit-22625/` is the first committed local baseline, with bounded tolerance for macOS material and font rasterization noise.
- An unsigned `v0.5.0` Catalyst App was launched from an isolated install path and replaced in place by the unsigned native App. Stable bundle identity, fixture book data, bookmark/sidecars, dictionary config, Anki mappings, UserDefaults, and an arbitrary Application Support marker survived.

## Remaining Hardening

1. Validate remaining Settings, Bookshelf, and Dictionary appearance across window sizes.
2. Validate Google Drive auth/token lifecycle with a real account.
3. Validate AnkiConnect recovery, controllers, and external/local audio with available hardware and services.
4. Decide whether hosted CI is visually stable enough to publish screenshot/diff artifacts from the committed local baseline.
5. Add signing and notarization only after the release policy changes; they are not part of the current unsigned pipeline.

## Rules

- Do not reintroduce UIKit or a Catalyst compatibility target.
- Use AppKit only for macOS capabilities that SwiftUI does not cover cleanly.
- Preserve user data compatibility even though binary/platform compatibility was removed.
- Reader, popup, sync, Anki, and Sasayaki changes require focused validation before completion claims.

## Validation

```bash
./script/build_and_run.sh --verify
./script/verify_native_release_contract.sh
./script/verify_native_upgrade_contract.sh
./script/audit_native_upgrade_data.sh
./script/verify_reader_ci_contract.sh
./script/verify_reader_harness.sh
```
