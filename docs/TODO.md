# Hoshi Reader Mac Agent TODO

Last updated: 2026-06-01

## Maintenance Rules

- Keep this file short.
- Record only current state, next action, blockers, and durable validation entry points.
- Put user-visible shipped changes in `docs/CHANGELOG.md`.
- Put long-term design direction in `docs/ARCHITECTURE_REFACTORING.md`.

## Current State

- Release: `v0.5.0` is the current GitHub release tag and DMG release line.
- Reader: vertical pagination fixes are in place; Reader navigation structure remains a high-risk area.
- Reader regression: docs, fixture generator, capture skeleton, and a gated Debug-only Lab entry exist; automatic screenshot capture does not exist yet.
- Mac native migration: the screen-rewrite attempt was discarded; the current direction is UIKit/Catalyst adapter extraction before any AppKit target work.
- Upstream: `upstream/develop` is the source for behavior review, not direct file replacement.
- Agent docs: core handoff docs and local workflow skill are being established.

## Next Actions

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
python3 -m py_compile script/generate_reader_fixtures.py
bash -n script/capture_reader_regression.sh
```

For release-specific work, also inspect:

```bash
gh run list --repo W1ght/Hoshi-Reader-Mac --workflow release-mac.yml --limit 5
```
- Start UIKit/AppKit migration with a platform dependency inventory and adapter layer, not by duplicating SwiftUI screens.
