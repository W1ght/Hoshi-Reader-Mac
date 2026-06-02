# Hoshi Reader Mac Agent TODO

Last updated: 2026-06-02

## Maintenance Rules

- Keep this file short.
- Record only current state, next action, blockers, and durable validation entry points.
- Put user-visible shipped changes in `docs/CHANGELOG.md`.
- Put long-term design direction in `docs/ARCHITECTURE_REFACTORING.md`.

## Current State

- Release: `v0.5.0` is the current GitHub release tag and DMG release line.
- Reader: vertical pagination fixes are in place; Reader navigation structure remains a high-risk area.
- Reader regression: docs, fixture generator, capture skeleton, and a gated Debug-only Lab entry exist; automatic screenshot capture does not exist yet.
- Mac native migration: the screen-rewrite attempt was discarded; this is a Mac-only product. A minimal isolated `Hoshi Reader Native` macOS target now exists under `NativeMac/`, including local bookshelf metadata, dictionary lookup, a reused `StatisticsSettingsView`, and an AppKit shortcut-capture probe. Existing Catalyst behavior remains the shipping app while narrow bridges are migrated one at a time. Remaining UIKit/Catalyst inventory is tracked in `docs/MAC_NATIVE_MIGRATION_INVENTORY.md`.
- Upstream: `upstream/develop` is the source for behavior review, not direct file replacement.
- Agent docs: core handoff docs and local workflow skill are being established.

## Next Actions

- Use `docs/MAC_NATIVE_MIGRATION_INVENTORY.md` to choose the next low-risk migration slice.
- Next low-risk candidate: reuse another existing SwiftUI settings page in the native shell, then map the native shortcut-capture probe into `ReaderKeyboardShortcut` after manual key/Escape validation. Keep Reader, popup rendering, import, sync, and Anki mining deferred.
- Add deterministic fixture opening and temporary Reader setting overrides to the Debug-only Reader Regression Lab.
- Wire screenshot capture to the lab after fixture import/opening is deterministic.
- Keep Reader root navigation stable before attempting another Reader chrome refactor.
- When syncing upstream, review Reader/WebView/Popup/Dictionary/Sync diffs before applying them.
- Keep release notes focused on user-visible changes.

## Blockers

- Manual UI validation still depends on a built Mac Catalyst app and available local test books.
- Hardware-specific checks, such as controllers or external audio setups, may need user confirmation.

## Validation Entry Points

```bash
./script/build_and_run.sh --verify
./script/build_and_run_catalyst.sh --verify
./script/build_and_run_native.sh --verify
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
