# Hoshi Reader Mac Agent Development Guide

This guide is the durable handoff layer for agents working on Hoshi Reader Mac. It complements `AGENTS.md`; if there is a conflict, follow the more specific Mac-user-visible rule.

## Product Boundary

Hoshi Reader Mac is a native macOS reading and language-learning app. The protected user path is:

```text
Import EPUB -> read -> look up words -> play dictionary/local audio -> create Anki cards -> sync progress and reading data
```

The repository is not a mechanical mirror of the iOS upstream. Upstream `upstream/develop` is a behavior reference. Mac user-visible behavior is the first source of truth.

## Non-Negotiable Rules

- Do not overwrite Mac-specific Reader, AnkiConnect, audio, shortcut, window, release, or sync behavior just to match iOS code.
- Do not release, tag, bump versions, or push release tags unless the user explicitly approves a release.
- Do not delete user data, dictionaries, books, Anki config, UserDefaults, Google tokens, or sidecar files to mask a bug.
- Do not mix audio sources: `WordAudioPlayer` and local audio are for dictionary terms; Sasayaki is whole-book audio.
- Do not ship new user-visible strings without considering `Localizable.xcstrings`.
- Do not claim UI behavior is fixed without either running the app or clearly stating what was not manually verified.

## High-Risk Areas

### Reader, WKWebView, JS, CSS

Treat Reader changes as high risk. Review these files before modifying reading behavior:

- `NativeMac/NativeReaderView.swift`
- `Features/Reader/ReaderWebView/reader.js`
- `Features/Reader/ScrollReaderWebView/scrollreader.js`

Validate vertical and horizontal writing, normal and full-screen windows, chapter boundaries, long text pages, image pages, lookup popups, and Sasayaki highlight restoration.

### Popup and Dictionary Rendering

Popup and dictionary pages should share rendering expectations. Do not add a style path that makes dictionary pages work while reader popups break. Treat custom CSS as native CSS; do not rewrite user CSS into a compatibility dialect.

### AnkiConnect

Mac card creation uses AnkiConnect. The default address is `http://127.0.0.1:8765`. Preserve deck, model, and field mappings when refreshing from Anki. Verify connected, duplicate, and failure cases when touching card creation.

### Google Drive Sync

Progress sync protects user reading state. Do not assume unchanged progress means nothing should be uploaded; timestamps, sidecars, and conflict resolution matter. OAuth and token callbacks must return to the correct actor and refresh UI state.

### Release

Release artifacts are DMG and checksum from `.github/workflows/release-mac.yml`. Tags are cut from `main`. Release notes should describe user-visible changes, not implementation churn.

## Documentation Map

- `docs/TODO.md`: short current state, next actions, blockers, validation entry points.
- `docs/CHANGELOG.md`: user-visible changes only.
- `docs/ARCHITECTURE_REFACTORING.md`: long-term architecture direction.
- `docs/UPSTREAM_SYNC_QUEUE.md`: upstream changes to evaluate and migrate.
- `.codex/skills/hoshi-reader-mac-workflow/SKILL.md`: concise agent workflow for recurring tasks.

## Verification Entry Points

Use the project script first:

```bash
./script/build_and_run.sh --verify
```

For unsigned native macOS compile checks:

```bash
xcodebuild -quiet \
  -project 'Hoshi Reader.xcodeproj' \
  -scheme 'Hoshi Reader' \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

Signing/profile failures are not code regressions unless the task is signing, notarization, or release packaging.
