# Hoshi Reader Mac Agent TODO

Last updated: 2026-06-13

## Maintenance Rules

- Keep this file short.
- Record only current state, next action, blockers, and durable validation entry points.
- Put user-visible shipped changes in `docs/CHANGELOG.md`.
- Put long-term design direction in `docs/ARCHITECTURE_REFACTORING.md`.

## Current State

- Release: `v0.5.0` is the current Catalyst-based GitHub release. The next release line must be native macOS; the existing release workflow still needs native archive/sign/notarize/DMG migration.
- Reader: vertical pagination fixes are in place; Reader navigation structure remains a high-risk area.
- Reader regression: the deterministic fixture/Lab/scenario pipeline currently launches the Catalyst app. Its fixture, metric, baseline, and comparison pieces are reusable, but app-driving and Reader instrumentation must move to Native before it can serve as the primary Reader gate.
- Mac native migration: `Hoshi Reader Native` is now the sole development and future release target. Catalyst compatibility is no longer required. The active work is native validation, real-account/hardware checks, porting Reader regression automation, then deleting Catalyst target code, UIKit bridges, scripts, and CI/release paths.
- Upstream: `upstream/develop` is the source for behavior review, not direct file replacement.
- Agent docs: repository rules now require migration state changes to update the smallest relevant source-of-truth document in the same task and normally in the same Conventional Commit.

## Next Actions

- Port the Reader Regression Lab launch, scenario automation, metrics, and screenshot capture from Catalyst to `Hoshi Reader Native`.
- Inventory Catalyst-only files, target memberships, scripts, tests, and CI/release assumptions into deletion slices.
- Remove Catalyst-only branches and bridges after the equivalent Native path is verified; do not preserve dual-platform abstractions without a current Native use.
- Replace the tag-triggered Catalyst DMG workflow with Native archive, signing, notarization, DMG, and checksum steps before the next release.
- Replace or retire `script/release_mac.sh` so it cannot accidentally publish the Catalyst target.
- Decide which Native screenshot baselines are stable enough to commit and wire comparison artifacts into CI for Reader-affecting changes.
- Validate Google Drive auth on native macOS with a real Google account and callback flow.
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
./script/build_and_run_native.sh --verify
./script/verify_reader_harness.sh
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
