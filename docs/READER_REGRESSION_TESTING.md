# Reader Regression Testing

Reader visual correctness is validated with real EPUB data in the exact native macOS build. Generated fixtures, a Debug Regression Lab, automated screenshots, and pixel baselines were removed because they did not reproduce real-book edge clipping and could alter the Reader state being measured.

## Focused Regression Checks

There is no aggregate Reader harness or Reader-specific CI workflow. Run only the focused check that matches the code being changed, then complete the relevant actual-EPUB matrix below. For shortcut, popup, Sasayaki, or viewport-bridge changes, the narrow checks are:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Features/Reader/ReaderWebView/ReaderViewportGeometry.swift script/test_reader_popup_sasayaki_regressions.swift -o /tmp/test_reader_popup_sasayaki_regressions && /tmp/test_reader_popup_sasayaki_regressions
swift script/test_sasayaki_playback_lifecycle.swift
swift script/test_sasayaki_sync_contract.swift
```

For shortcut changes, run only the matching `script/test_shortcut_*.swift` check for the registry, scope, migration, or dispatch boundary being changed.

These checks prevent specific code regressions; they are not a Reader acceptance gate and cannot establish visual correctness.

For persistence bugs where the final sidecar JSON appears stale, missing, or
partially updated, first follow the chain-level logging checklist in
`docs/READER_PERSISTENCE_DEBUGGING.md`.

## Actual-Data Validation

Use `./script/build_and_run.sh --verify` and accept evidence only when it reports bundle id `moe.shishamo.hoshi` and a running executable inside that exact DerivedData `.app`.

For Reader layout changes, exercise real EPUBs that cover:

- horizontal and vertical writing;
- paginated and continuous modes;
- normal, resized narrow/wide, and full-screen windows;
- chapter start, middle, and end, including dense or zero-margin text;
- zero Reader padding, where text must use the complete available viewport, plus a nonzero user-selected padding value;
- cover, image-heavy, and SVG content;
- click lookup, Shift-hover lookup after resting the pointer, continuous lookup while moving with Shift held, nested lookup, popup dismissal, and return to reading;
- native text selection and highlights: drag across text without opening click lookup, Copy from the standard context menu, create each highlight color, delete a highlight, and reopen the book to confirm persistence;
- chapter-list, highlight, character-count, and internal-link jumps: restore the prior position with the backward progress control, return with the forward control, confirm the jump distance does not change session/today/all-time character totals, confirm ordinary page turns and adjacent chapter-boundary reading still advance statistics, confirm manual page turns or continuous scrolling invalidate the stale forward destination, and cover both same-chapter and cross-chapter targets in paginated and continuous modes;
- shared context mining from a root Reader lookup and a nested glossary lookup: add and roll back both preceding and following cards, confirm chapter/glossary boundaries, verify target-word preview highlighting, and confirm direct Add to Anki remains unchanged;
- Sasayaki play/pause, cue navigation, highlight, and highlight restoration.
- previous/next shortcuts at the first page, penultimate page, final partial page, and the true chapter boundary; one physical left/right key press must produce exactly one page-navigation request even when WKWebView is first responder.
- an English EPUB with language metadata: automatic English Profile selection, phrase scanning at the configured scan length, apostrophes/hyphens, IPA display, approximate-word progress and reverse jump conversion;
- a Japanese EPUB immediately after English validation to confirm lookup language, vertical pagination, furigana and pitch rendering return to the Japanese Profile without leaked state.

For viewport and clipping work, inspect both text edges plus top and bottom chrome. The Reader WebView may extend into the top safe area so the titlebar band is not wasted, but it must stay out of the leading/trailing rounded-corner safe areas; fixed visual insets, side masks, leading/trailing safe-area extension, and chrome-derived body padding are not valid substitutes for correct pagination. Record the writing mode, reading mode, Reader padding, approximate window state, chapter position, and whether the book supplies its own margins. A screenshot may be attached as evidence, but it is not a versioned pixel baseline.

## Data Safety

- Do not import, replace, rename, or delete books in the user's library merely to run validation without explicit approval.
- Do not rewrite bookmarks, Reader settings, sidecars, or progress for automation. If a setting must change manually, restore it before handing back the workspace.
- Do not copy book text, titles, paths, or other private content into tracked artifacts. Describe test data only as narrowly as needed.
- If appropriate real EPUB data or an interactive UI pass is unavailable, state exactly which matrix entries remain unverified.
- Back up and restore the active Profile index/settings before changing a Profile for validation. Do not leave a test-only per-book Profile override in book metadata.

## Completion Evidence

A Reader change is complete only when the native App builds and launches with the expected identity and the relevant actual-data matrix has been checked. Focused test success alone must never be reported as proof that clipping, pagination, popup geometry, or visual styling is fixed.
