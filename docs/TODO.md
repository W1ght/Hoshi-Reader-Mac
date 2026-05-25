# Hoshi Reader Mac Agent TODO

Last updated: 2026-05-25

## Maintenance Rules

- Keep this file short.
- Record only current state, next action, blockers, and durable validation entry points.
- Put user-visible shipped changes in `docs/CHANGELOG.md`.
- Put long-term design direction in `docs/ARCHITECTURE_REFACTORING.md`.

## Current State

- Release: `v0.4.2` is the current GitHub release tag and DMG release line.
- Reader: vertical pagination fixes are in place; Reader navigation structure remains a high-risk area.
- Upstream: `upstream/develop` is the source for behavior review, not direct file replacement.
- Agent docs: core handoff docs and local workflow skill are being established.

## Next Actions

- Keep Reader root navigation stable before attempting another Reader chrome refactor.
- When syncing upstream, review Reader/WebView/Popup/Dictionary/Sync diffs before applying them.
- Keep release notes focused on user-visible changes.

## Blockers

- Manual UI validation still depends on a built Mac Catalyst app and available local test books.
- Hardware-specific checks, such as controllers or external audio setups, may need user confirmation.

## Validation Entry Points

```bash
./script/build_and_run.sh --verify
```

For release-specific work, also inspect:

```bash
gh run list --repo W1ght/Hoshi-Reader-Mac --workflow release-mac.yml --limit 5
```
