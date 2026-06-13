# Hoshi Reader Mac Agent TODO

Last updated: 2026-06-13

## Maintenance Rules

- Keep this file short.
- Record only current state, next action, blockers, and durable validation entry points.
- Put user-visible shipped changes in `docs/CHANGELOG.md`.
- Put long-term design direction in `docs/ARCHITECTURE_REFACTORING.md`.

## Current State

- Release: `v0.5.0` is the current GitHub release tag and DMG release line.
- Reader: vertical pagination fixes are in place; Reader navigation structure remains a high-risk area.
- Reader regression: the deterministic fixture/Lab/scenario capture pipeline, geometry metrics, popup/Sasayaki automation, baseline update/compare commands, and threshold reporting exist. Capture-only JS work is gated away from normal Reader restore, scenario settings and bookmark sidecars are restored after runs, invalid thresholds are rejected, and baseline differences return a failing status. Stable baseline governance and CI artifact integration still need work.
- Mac native migration: inventory, Mac-only cleanup, low-risk capability boundaries, AppKit bridges, native target/shell, and major shared feature reuse are complete for the current scope. `Hoshi Reader Native` reuses bookshelf metadata, dictionary lookup/rendering, Settings, in-tab Reader, popup lookup, statistics, highlights, and Sasayaki. The active phase is interactive validation, real-account/hardware integration checks, Reader regression hardening, and then high-risk WebView edge replacement.
- Upstream: `upstream/develop` is the source for behavior review, not direct file replacement.
- Agent docs: repository rules now require migration state changes to update the smallest relevant source-of-truth document in the same task and normally in the same Conventional Commit.

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
