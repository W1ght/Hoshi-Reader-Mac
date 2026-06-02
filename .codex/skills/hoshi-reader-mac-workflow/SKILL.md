---
name: hoshi-reader-mac-workflow
description: Use when working in the Hoshi Reader Mac repository on Reader, WKWebView, dictionary/popup rendering, AnkiConnect, local audio, Sasayaki, Google Drive sync, upstream merges, localization, or release tasks. Enforces Mac-first behavior, high-risk validation, and release discipline.
---

# Hoshi Reader Mac Workflow

Use this skill before making code changes in the Hoshi Reader Mac repository.

## First Checks

1. Read `AGENTS.md`.
2. Check `git status --short --branch`.
3. Identify the affected area: Reader/WebView, Popup/Dictionary, AnkiConnect, local audio, Sasayaki, Google Drive sync, Settings/i18n, upstream sync, or Release.
4. Prefer existing project patterns over new abstractions.
5. Do not revert unrelated user or agent changes.

## Source Of Truth

- Mac user-visible behavior is the first source of truth.
- `upstream/develop` is a behavior reference, not an implementation authority.
- Do not overwrite Mac Catalyst adaptations with iOS code.

## High-Risk Workflows

### Reader / WKWebView / JS / CSS

- Read the nearest Swift, JS, and CSS injection code before editing.
- Treat pagination, safe area, top/bottom chrome, focus mode, and full screen as coupled.
- Validate vertical and horizontal writing, normal and full-screen windows, chapter boundaries, image pages, lookup popups, and Sasayaki highlight restoration.
- Check `docs/READER_REGRESSION_TESTING.md` for the Reader fixture, lab, and screenshot plan. If Reader visual validation is unavailable, say which scenarios were not covered.

### Popup / Dictionary

- Keep popup and dictionary page rendering aligned.
- Do not add popup-only CSS hacks unless the dictionary page path is checked.
- Preserve dictionary media behavior for hoshidicts/Yomitan data.

### AnkiConnect

- Mac mining uses AnkiConnect, not AnkiMobile callbacks.
- Preserve deck/model/field mappings during refresh.
- Verify connected, duplicate, and failure toast behavior when touching card creation.

### Local Audio / Sasayaki

- Word audio and local audio are dictionary pronunciation paths.
- Sasayaki is whole-book audio.
- Do not create fallbacks between these audio sources.

### Google Drive Sync

- Protect user reading progress and sidecar metadata.
- Treat unchanged numeric progress plus changed timestamp/day as a real sync case until proven otherwise.
- Keep OAuth/token callbacks actor-safe and UI state-refreshing.

### Localization

- For new visible settings, buttons, alerts, toasts, and release-visible labels, check `Localizable.xcstrings`.
- At minimum avoid broken Chinese and English user-visible text.

## Release Discipline

- Never release without explicit user approval.
- Release from `main`.
- Version comes from `MARKETING_VERSION`.
- Tags use `v*.*.*`.
- DMG and `.sha256` are the release artifacts.
- Release notes describe user-visible changes, not internal churn.

## Verification

Default verification:

```bash
./script/build_and_run.sh --verify
```

Explicit target verification:

```bash
./script/build_and_run_catalyst.sh --verify
./script/build_and_run_native.sh --verify
```

Unsigned compile fallback:

```bash
xcodebuild -quiet \
  -project 'Hoshi Reader.xcodeproj' \
  -scheme 'Hoshi Reader' \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

If hardware, account, Anki, Google Drive, or full UI validation is unavailable, state that limitation explicitly.
