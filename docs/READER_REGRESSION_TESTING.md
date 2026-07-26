# Reader Regression Testing

Reader visual correctness is validated with real EPUB data in the exact native macOS build. Generated fixtures, a Debug Regression Lab, automated screenshots, and pixel baselines were removed because they did not reproduce real-book edge clipping and could alter the Reader state being measured.

## Focused Regression Checks

There is no aggregate Reader harness or Reader-specific CI workflow. Run only the focused check that matches the code being changed, then complete the relevant actual-EPUB matrix below. For shortcut, popup, Sasayaki, or viewport-bridge changes, the narrow checks are:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Features/Reader/ReaderWebView/ReaderViewportGeometry.swift script/test_reader_popup_sasayaki_regressions.swift -o /tmp/test_reader_popup_sasayaki_regressions && /tmp/test_reader_popup_sasayaki_regressions
swift script/test_sasayaki_playback_lifecycle.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Features/Reader/ReaderStatisticsPersistencePolicy.swift script/test_reader_statistics_persistence.swift -o /tmp/test_reader_statistics_persistence && /tmp/test_reader_statistics_persistence
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-clang-module-cache SWIFT_MODULECACHE_PATH=/tmp/hoshi-swift-module-cache xcrun swiftc -parse-as-library Models/Book.swift Util/ReaderCharacterNormalizer.swift Features/Reader/Gallery/ReaderImageGalleryIndex.swift Features/Reader/ReaderChapterIndex.swift script/test_reader_chapter_index.swift -o /tmp/test_reader_chapter_index && /tmp/test_reader_chapter_index
swift script/test_reader_chapter_index_contract.swift
swift script/test_sasayaki_sync_contract.swift
swift script/test_reader_lyrics_mode_contract.swift
swift script/test_manga_library_contract.swift
xcrun swiftc -parse-as-library Util/ReaderCharacterNormalizer.swift Models/Book.swift Features/Reader/Gallery/ReaderImageGalleryIndex.swift script/test_reader_gallery_index.swift -o /tmp/test_reader_gallery_index && /tmp/test_reader_gallery_index
swift script/test_reader_gallery_contract.swift
xcrun swiftc -parse-as-library Features/Reader/Lyrics/ReaderLyricsSelectionResolver.swift script/test_reader_lyrics_selection_resolver.swift -o /tmp/test_reader_lyrics_selection_resolver && /tmp/test_reader_lyrics_selection_resolver
xcrun swiftc -parse-as-library Features/Reader/Lyrics/ReaderLyricsShiftHoverLookupState.swift script/test_reader_lyrics_shift_hover_lookup.swift -o /tmp/test_reader_lyrics_shift_hover_lookup && /tmp/test_reader_lyrics_shift_hover_lookup
xcrun swiftc -parse-as-library Features/Reader/Lyrics/ReaderLyricsLayoutMetrics.swift script/test_reader_lyrics_layout_metrics.swift -o /tmp/test_reader_lyrics_layout_metrics && /tmp/test_reader_lyrics_layout_metrics
```

For shortcut changes, run only the matching `script/test_shortcut_*.swift` check for the registry, scope, migration, or dispatch boundary being changed.

These checks prevent specific code regressions; they are not a Reader acceptance gate and cannot establish visual correctness.

For persistence bugs where the final sidecar JSON appears stale, missing, or
partially updated, first follow the chain-level logging checklist in
`docs/READER_PERSISTENCE_DEBUGGING.md`.

## Actual-Data Validation

Use `./script/build_and_run.sh --verify` and accept evidence only when it reports bundle id `moe.shishamo.hoshi` and a running executable inside that exact DerivedData `.app`.

For Reader layout changes, exercise real EPUBs that cover:

- horizontal and vertical writing, including single-column and two-column horizontal paginated pages plus EPUB chapters whose publisher CSS adds nested multi-column containers;
- paginated and continuous modes;
- normal, resized narrow/wide, and full-screen windows;
- chapter start, middle, and end, including dense or zero-margin text;
- zero Reader padding, where text must use the complete available viewport, plus a nonzero user-selected padding value;
- cover, image-heavy, and SVG content, including consecutive zero-character image spine items and the text-to-image / image-to-text chapter boundaries around them;
- click lookup, Shift-hover lookup after resting the pointer, continuous lookup while moving with Shift held, repeated lookups that move the active selection highlight, nested lookup, popup dismissal, and return to reading; repeat the Shift-hover and nested lookup path while a native text field has an active Japanese/Chinese IME composition, and confirm the lookup WebViews do not steal the field's first-responder ownership or crash during popup replacement;
- native text selection and highlights: drag across text without opening click lookup, Copy from the standard context menu, create each highlight color, delete a highlight, and reopen the book to confirm persistence;
- Reader statistics lifecycle: open and close the same book in separate Reader windows several times, confirm exactly one `reader.statistics.start` and one periodic update stream per window, advance a normal page, press Esc to close immediately, confirm the main App remains running, and confirm the final `statistics.json` total retains the page-turn delta instead of being replaced by a stale close-time model;
- Reader window frame persistence: resize a normal Reader window, close and reopen it at least three times, then resize it again, quit and relaunch Niratan, and reopen a book; confirm every cycle restores the last windowed frame, the saved frame never becomes a collapsed teardown size, full-screen exit does not replace that frame, and the statistics total remains unchanged except for real active reading time;
- chapter-list, highlight, character-count, and internal-link jumps: include an EPUB whose TOC defines multiple fragment chapters in one XHTML file; confirm every row shows its distinct character position, the active row follows the current fragment chapter, and Statistics time-to-finish reaches zero at the next TOC fragment rather than the end of the XHTML file. Restore the prior position with the backward progress control, return with the forward control, confirm the jump distance does not change session/today/all-time character totals, confirm ordinary page turns and adjacent chapter-boundary reading still advance statistics, confirm manual page turns or continuous scrolling invalidate the stale forward destination, and cover both same-chapter and cross-chapter targets in paginated and continuous modes;
- statistics tracking across Reader and Statistics-sheet key-window changes: with tracking running, open Statistics and confirm session/today/all-time values plus the start/stop control update live; switch from the sheet to another Niratan window and another app, wait long enough to distinguish each interval, then return and confirm inactive time is excluded; close the sheet and repeat with tracking manually stopped to confirm focus gain does not start it; Appearance, Go To, and Sasayaki sheets must not keep statistics active;
- shared context mining from a root Reader lookup and a nested glossary lookup: add and roll back both preceding and following cards, confirm chapter/glossary boundaries, verify target-word preview highlighting, and confirm direct Add to Anki remains unchanged;
- Sasayaki play/pause, cue navigation, highlight, and highlight restoration; verify the Resources / Chapters / Settings segments, embedded artwork/title/artist (including the direct M4B `ilst` fallback) with EPUB-cover fallback, SRT selection/matching and immediate Reader highlight availability, an MP3 without chapter markers, an M4B with `chpl` or native chapter markers, current-chapter highlighting, chapter seeking, and the chapter-aware default tab without changing the Reader bookmark. From the first cue of a chapter, use previous-cue navigation into a prior text chapter separated by or containing image-only/failed-image content; confirm the Reader restores the actual cue instead of progress zero, does not stall while preparing image promises, keeps punctuation highlighted across DOM text nodes, and leaves session/today/all-time character totals unchanged for the programmatic jump. Pause and resume in the same chapter and confirm only resume reveals the active cue. Confirm local-book context menus no longer contain the duplicate Match action.
- Lyrics Mode for Sasayaki SRT matches: confirm the entry appears only after audio and match data are available, playback controls work, click lookup opens the shared popup and pauses/resumes by the Sasayaki rule, manual cue/15-second seeks do not count jumped text as reading, natural cue advancement increments statistics, Esc exits to the novel view, and the novel position lands on the active cue, including a cross-chapter cue.
- Image Gallery: in image-heavy and image-free EPUBs, confirm the Reader menu opens a near-window-width adaptive thumbnail grid or the localized empty state; verify reading-order deduplication, unread images remain blurred until their character position is reached, the first thumbnail click opens a still-blurred large preview, a second click on that preview reveals it for the current gallery session, normal/resized/full-screen presentation, thumbnail selection retains the grid and scroll position, previous/next buttons and unmodified Left/Right keys change only the preview image without auto-revealing unread art, Esc/close returns to the gallery and then the unchanged Reader position, and lookup/Sasayaki state is not interrupted.
- previous/next shortcuts at the first page, penultimate page, final partial page, WebKit-clamped final two-column page, image-only page, and the true chapter boundary; one physical left/right key press must produce exactly one page-navigation request even when WKWebView is first responder.
- with an English Profile selected explicitly in `Settings > Profiles`, open an English EPUB and confirm book opening/window focus does not change the global Profile; verify phrase scanning at the configured scan length, apostrophes/hyphens, IPA display, approximate-word progress and reverse jump conversion;
- switch explicitly to a Japanese Profile in Settings, then open a Japanese EPUB and confirm lookup language, vertical pagination, furigana and pitch rendering use that global Profile without leaked English state; reopening either Reader window must not change the selection.

For Manga lookup or zoom changes, use a disposable manga source rather than changing the user's existing library or progress. In single-page, double-page, and continuous layouts, cover the 50%–200% slider endpoints and an arbitrary typed value, confirm the wide slider moves without relaying out pages until release, invalid/out-of-range input clamping, persistence after reopening, keyboard focus and submission in both glass numeric fields, Mokuro and cached Google OCR text, horizontal and vertical blocks, hover reveal, lookup from multiple characters in one block, Popup placement near the visible page after zooming and scrolling, nested lookup, blank-area/Escape dismissal, and Manga image mining. In both paged layouts at 100% and above 100%, confirm discrete mouse-wheel input crosses one threshold to turn exactly one page, rapid events respect the cooldown, precise two-finger trackpad scrolling pans without turning a page, and Command/Control-scroll zooms around the pointer while keeping the toolbar percentage synchronized. Resize the window and repeat in full screen; in continuous layout, verify regions stay aligned on pages with different aspect ratios, enlarged pages pan horizontally without breaking vertical progress, and scrolling to a distant lazily loaded page loads its text without restarting completed OCR.

For Manga scan-page processing, use a disposable source containing portrait pages, a true wide scan with different left/right content, asymmetric white borders, an off-white/noisy scan edge, and Mokuro or cached OCR regions on both halves. Confirm enabling Split Wide Pages leaves portrait pages untouched, reads the right half first in RTL and the left half first in LTR, exposes both halves as separate positions in single-page and continuous navigation, and places them as one correctly ordered pair in double-page mode. Confirm Crop White Borders removes only the contiguous outer scan border without clipping panels or an intentionally white page, and that both choices persist after reopening. On every derived half, verify hover, Popup anchoring, copy/save/share, custom cover, mining image and source-page progress; closing on either half must reopen at the matching source page without changing any source-file hash. No rotation or independent split-order control should appear.

For Manga secondary-button changes, verify a held right-button drag pans horizontally and vertically without opening a menu, while a stationary secondary click opens the page menu. In single-page, both sides of a double-page spread, and continuous layout, confirm copy produces the pointed page image, Save As writes a readable full-resolution PNG, Share opens the system service picker, and Set as Manga Cover immediately refreshes the library card and survives a source refresh/relaunch without changing any source-file hash.

In continuous layout, also confirm Command/Control-scroll over several different lazy pages changes the same toolbar percentage from 50% through 200%, preserves ordinary two-finger vertical/horizontal scrolling without modifiers, keeps the active page near the viewport, and does not detach OCR hit regions after the page stack relayout.

For Manga library-loading changes, relaunch with an existing nonempty disposable catalog while another sidebar section is selected, then switch to Manga immediately and repeatedly. Confirm neither the “No Manga” import state nor empty-state toolbar flashes before the existing cards, and repeat after a genuine empty catalog to confirm the import state appears only after the first snapshot completes.

For viewport and clipping work, inspect both text edges plus top and bottom chrome. The Reader WebView may extend into the top safe area so the titlebar band is not wasted, but it must stay out of the leading/trailing rounded-corner safe areas; fixed visual insets, side masks, leading/trailing safe-area extension, and chrome-derived body padding are not valid substitutes for correct pagination. Record the writing mode, reading mode, Reader padding, approximate window state, chapter position, and whether the book supplies its own margins. A screenshot may be attached as evidence, but it is not a versioned pixel baseline.

## Data Safety

- Do not import, replace, rename, or delete books in the user's library merely to run validation without explicit approval.
- Do not rewrite bookmarks, Reader settings, sidecars, or progress for automation. If a setting must change manually, restore it before handing back the workspace.
- Do not copy book text, titles, paths, or other private content into tracked artifacts. Describe test data only as narrowly as needed.
- If appropriate real EPUB data or an interactive UI pass is unavailable, state exactly which matrix entries remain unverified.
- Back up and restore the active Profile index/settings before changing the global Profile for validation. Do not edit legacy per-book, Video or language-default Profile fields to drive a test; they are compatibility data and must remain untouched.

## Completion Evidence

A Reader change is complete only when the native App builds and launches with the expected identity and the relevant actual-data matrix has been checked. Focused test success alone must never be reported as proof that clipping, pagination, popup geometry, or visual styling is fixed.
