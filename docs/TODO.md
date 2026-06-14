# Hoshi Reader Mac Agent TODO

Last updated: 2026-06-14

## Maintenance Rules

- Keep this file short.
- Record only current state, next action, blockers, and durable validation entry points.
- Put user-visible shipped changes in `docs/CHANGELOG.md`.
- Put long-term design direction in `docs/ARCHITECTURE_REFACTORING.md`.

## Current State

- Release: `v0.5.0` is the current Catalyst-based GitHub release. The next release line builds the single native macOS target, removes all code signatures, and publishes an unnotarized DMG with checksum.
- Reader: vertical pagination fixes are in place; Reader navigation structure remains a high-risk area.
- Reader regression: the deterministic fixture/Lab/scenario pipeline launches `Hoshi Reader`, restores temporary settings/bookmarks, writes Reader metrics, and drives popup/Sasayaki capture scenarios. Reader-affecting PRs now build the native App, run the harness, and upload the capture plan; stable versioned screenshot baselines are still pending.
- Mac native migration: target, app identity, UIKit/Catalyst branches, ShareExtension coupling, legacy Reader wrappers, build scripts, and DMG workflow have moved to the single native `Hoshi Reader` App.
- Native open routing: Finder document opens and `hoshi://search` / `hoshi://open` requests now route through the native sidebar into the existing bookshelf import and dictionary search surfaces.
- Interactive native check: the current Debug App was explicitly targeted with `hoshi://search?text=星`; it switched to Dictionary and rendered results. Use `build_and_run_native.sh --open-url` so historical installs with the same bundle id cannot intercept validation.
- AnkiConnect: the local API v6 endpoint and read-only deck/model metadata queries succeed; card creation success/duplicate/failure paths remain intentionally untested because they mutate the user's Anki collection.
- Upgrade compatibility: the native App no longer clears Google Drive credentials on startup; the automated contract now protects the bundle id, UserDefaults domain, Application Support paths, sidecar names, scoped Keychain service, and legacy Keychain migration.
- Upstream: `upstream/develop` is the source for behavior review, not direct file replacement.
- Agent docs: repository rules now require migration state changes to update the smallest relevant source-of-truth document in the same task and normally in the same Conventional Commit.

## Next Actions

- Run an end-to-end upgrade launch from the last Catalyst release against existing books, sidecars, bookmarks, dictionaries, Anki config, tokens, and UserDefaults; the static storage contract and a read-only local data audit are complete.
- Decide whether a future release should add Developer ID signing and notarization; the current approved pipeline intentionally remains unsigned.
- Decide which Native screenshot baselines are stable enough to commit before enabling screenshot/diff artifacts; CI currently uploads the deterministic capture plan without pretending hosted runners are a stable visual baseline.
- Validate Google Drive auth on native macOS with a real Google account and callback flow.
- Validate AnkiConnect card creation success, duplicate, and failure feedback with a disposable deck or explicit approval.
- Run interactive native visual validation for sidebar expand/collapse, Light/Dark/System switching, grouped card backgrounds, segmented picker behavior, Reader chrome/background, and popup layout.
- Keep Reader root navigation stable before attempting another Reader chrome refactor.
- When syncing upstream, review Reader/WebView/Popup/Dictionary/Sync diffs before applying them.
- Keep release notes focused on user-visible changes.

## Blockers

- Manual UI validation still depends on an interactive app session and available local test books.
- Google Drive auth validation requires a real account/client configuration and callback completion.
- Hardware-specific checks, such as controllers or external audio setups, may need user confirmation.

## Validation Entry Points

```bash
./script/build_and_run.sh --verify
./script/build_and_run_native.sh --open-url 'hoshi://search?text=星'
./script/verify_native_release_contract.sh
./script/verify_native_upgrade_contract.sh
./script/verify_reader_ci_contract.sh
./script/verify_reader_harness.sh
swiftc NativeMac/AppOpenURLRoute.swift script/test_app_open_url_route.swift -o /tmp/test_app_open_url_route && /tmp/test_app_open_url_route
python3 -m py_compile script/generate_reader_fixtures.py
bash -n script/capture_reader_regression.sh
swift script/test_color_hex_codec.swift
swift script/test_reader_keyboard_shortcut_labels.swift
swift script/test_css_editor_snippets.swift
```

For release-specific work, also inspect:

```bash
gh run list --repo W1ght/Hoshi-Reader-Mac --workflow release-mac.yml --limit 5
```
