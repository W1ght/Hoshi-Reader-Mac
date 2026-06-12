# Hoshi Reader Mac Agent TODO

Last updated: 2026-06-11

## Maintenance Rules

- Keep this file short.
- Record only current state, next action, blockers, and durable validation entry points.
- Put user-visible shipped changes in `docs/CHANGELOG.md`.
- Put long-term design direction in `docs/ARCHITECTURE_REFACTORING.md`.

## Current State

- Release: `v0.5.0` is the current GitHub release tag and DMG release line.
- Reader: vertical pagination fixes are in place; Reader navigation structure remains a high-risk area.
- Reader regression: docs, fixture generator, capture harness, static Reader popup/Sasayaki checks, a gated Debug-only Lab entry, an opt-in Lab window smoke screenshot capture, Reader scenario matrix screenshot capture, deterministic chapter/progress positions, deterministic Sasayaki highlight / lookup popup / nested popup states, geometry sidecar JSON with desktop/window/Reader/SwiftUI popup/JavaScript metrics, screenshot baseline update/compare commands, and explicit pixel-diff threshold policy reporting exist. The lab can import/open deterministic fixture scenarios and applies temporary Reader setting overrides; stable baseline governance and CI artifact integration still need work.
- Mac native migration: the screen-rewrite attempt was discarded; this is a Mac-only product. `Hoshi Reader Native` now reuses local bookshelf metadata, dictionary lookup/rendering, settings pages, native in-tab Reader, popup lookup, statistics, highlight list, and Sasayaki playback paths. Native Settings and Reader chrome now have build/harness coverage; remaining confidence gaps are interactive visual checks and account/hardware-backed integrations.
- Upstream: `upstream/develop` is the source for behavior review, not direct file replacement.
- Agent docs: core handoff docs and local workflow skill are being established.

## Next Actions

- Decide which local screenshot baselines are stable enough to commit and wire baseline comparison artifacts into CI for Reader-affecting changes.
- Extend the Reader Regression Lab only for remaining interaction triggers not covered by the automated scenario matrix.
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
./script/build_and_run.sh --verify
./script/build_and_run_catalyst.sh --verify
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
