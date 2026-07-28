---
name: hoshi-reader-mac-workflow
description: Use for Niratan Mac implementation, debugging, validation, upstream sync, persistence, signing, packaging, or release work across Reader, Manga, Video, Popup, Anki, profiles, shortcuts, audio, and Google Drive. Routes each task to only the repository-specific guidance it needs.
---

# Niratan Mac Workflow

This skill is a router. Read only the references required by the current task; do not load unrelated module guidance.

## Start

1. Check `git status --short --branch` and preserve unrelated changes.
2. Inspect the nearest implementation, existing tests, and current truth-source section before deciding on a change.
3. Select every reference whose boundary the task actually touches.

## Reference Routing

- Reader, WKWebView, Popup, Dictionary, Sasayaki, word audio, or configurable shortcuts: `references/reader-popup.md`
- Manga, local archives, Mokuro, OCR, Suwayomi, or manga mining: `references/manga.md`
- Video, mpv, subtitles, remote media, playback windows, or video mining: `references/video.md`
- Profiles, AnkiConnect, Google Drive, tokens, sidecars, or persistent user state: `references/data-integrations.md`
- Xcode project, target membership, dependencies, build scripts, packaging, signing, or runtime identity: `references/project-build.md`
- Release, version, tag, GitHub Actions, DMG, checksum, or release notes: `references/release.md`
- Upstream fetch, comparison, port, or merge: `references/upstream.md` plus the affected module reference

General SwiftUI or localization work needs no extra reference unless it touches one of those boundaries. Apply the root UI invariant and keep user-visible strings in `Localizable.xcstrings`.

## Verification Contract

- Pure documentation changes: inspect the rendered structure as needed and run `git diff --check`; do not launch the App solely for documentation.
- Pure logic or contract changes: run the narrowest relevant test, then broaden only when the changed boundary requires it.
- Runnable App changes: run the affected checks, then `./script/build_and_run.sh --verify` and open the affected module unless the selected reference defines a safer exception.
- Accept UI evidence only from the absolute `.app` and executable reported by that build. A bundle id alone does not select the current build.
- Use disposable data for destructive-looking validation. If no safe fixture, account, hardware, or service is available, report the uncovered behavior instead of touching user data.
- Finish by stating what changed, what ran, and what remains unverified.
