# Niratan Mac Agent Development Guide

This guide is the durable handoff layer for agents working on Niratan Mac. It complements `AGENTS.md`; if there is a conflict, follow the more specific Mac-user-visible rule.

## Product Boundary

Niratan Mac is a native macOS reading and language-learning app. The protected user path is:

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
- Treat `moe.shishamo.hoshi` as the only active bundle id. UI automation must target the exact DerivedData `.app` or this unique bundle id; a same-name process/window or `/Applications/Niratan.app` may be an obsolete build and is not verification evidence.

## High-Risk Areas

### Reader, WKWebView, JS, CSS

Treat Reader changes as high risk. Review these files before modifying reading behavior:

- `NativeMac/NativeReaderView.swift`
- `Features/Reader/ReaderWebView/reader.js`
- `Features/Reader/ScrollReaderWebView/scrollreader.js`

Validate vertical and horizontal writing, normal and full-screen windows, chapter boundaries, long text pages, image pages, lookup popups, and Sasayaki highlight restoration.

### Video Full-Screen UI Automation

Video full-screen checks must target the exact DerivedData `Niratan.app` produced by `./script/build_and_run.sh --video --verify`, not an installed app with the same display name. Open a real video, click the video surface to make the player key, then drive every transition from a fresh Computer Use state snapshot.

The bottom OSC and the macOS traffic lights can both auto-hide. To click them reliably, first move the pointer inside the video surface or to the top-left titlebar/top screen edge, wait for the chrome to appear, immediately call `get_app_state`, and click the full-screen/green button returned by that same snapshot. If the tool or model round trip takes long enough that the control disappears, reveal it again and re-query instead of clicking an old element id or coordinate. Use one transition per snapshot, then wait and re-query after AppKit finishes moving into or out of the full-screen Space.

Regression coverage for Video full screen should include entering and exiting through the bottom full-screen button, the green traffic light when visible, `f`, and `Esc`, followed by a check that no new `Niratan-*.ips` crash report was written.

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

The command must print a verified `moe.shishamo.hoshi` build path and a PID whose executable belongs to that same app bundle before UI inspection begins.

When multiple Codex sessions test at the same time, give each session a stable instance id so the build product, pre-launch cleanup, process verification, and log streaming stay scoped to one app bundle:

```bash
./script/build_and_run.sh --video --instance codex-video-a --verify
./script/build_and_run.sh --instance codex-reader-b --verify
```

Use the exact `.app` path printed by that command for Computer Use. The bundle id and user data directory are still shared, so two sessions must not concurrently mutate the same book sidecar or Sasayaki playback file unless the test explicitly covers data races.

For unsigned native macOS compile checks:

```bash
xcodebuild -quiet \
  -project 'Niratan.xcodeproj' \
  -scheme 'Niratan' \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

Signing/profile failures are not code regressions unless the task is signing, notarization, or release packaging.
