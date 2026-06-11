# Reader Regression Testing

This document defines the Reader visual regression plan for Hoshi Reader Mac. It is a testing and validation design, not a Reader implementation log.

## Purpose

Reader rendering is the highest-risk Mac user-visible surface in this repository. The same EPUB can render differently when WKWebView state, window size, safe area, injected CSS, JavaScript pagination, user settings, or Mac Catalyst runtime behavior changes.

Mac Catalyst WebKit is not identical to iOS WebKit. Upstream iOS behavior is useful as a reference, but the Mac app must protect the desktop reading experience first: stable windows, full screen behavior, keyboard and pointer interactions, Anki lookup flow, and local audio/Sasayaki interactions.

Ordinary unit tests can catch data mistakes, but they do not prove that the reader still displays text correctly. Visual regression is critical because the core product value is stable reading. The failures that matter most are visible: top chrome covering text, bottom controls covering lookup targets, vertical pagination joining pages together, images breaking layout, popup coordinates drifting, and Sasayaki highlights failing to restore after chapter or focus changes.

The regression suite should make these cases repeatable before a release or any Reader/WKWebView/JS/CSS change:

- Top navigation, title, progress, and chrome do not cover text.
- Bottom buttons, progress, statistics, and chrome do not cover text or lookup targets.
- Chapter starts, chapter ends, and long chapter middle positions restore correctly.
- Vertical Japanese pagination does not overlap columns or mix pages.
- Continuous scrolling preserves progress and popup coordinates.
- Images and covers stay contained in the viewport.
- Ruby text remains legible and selectable.
- Weird EPUB CSS and custom user CSS do not defeat Reader constraints.
- Lookup popup open/close and nested popup lookup do not disturb Reader geometry.
- Sasayaki active cue highlight displays and restores without moving to the wrong page.

## Current Infrastructure State

- Main Reader entry: `Features/Reader/ReaderView/ReaderView.swift`, through `ReaderLoader` and `ReaderView`.
- Reader state/loading: `Features/Reader/ReaderView/ReaderViewModel.swift`.
- Paginated WKWebView path: `Features/Reader/ReaderWebView/ReaderWebView.swift` plus `Features/Reader/ReaderWebView/reader.js`.
- Continuous WKWebView path: `Features/Reader/ScrollReaderWebView/ScrollReaderWebView.swift` plus `Features/Reader/ScrollReaderWebView/scrollreader.js`.
- Shared selection and highlight scripts: `Features/Reader/ReaderWebView/selection.js` and `Features/Reader/Highlights/highlights.js`.
- Reader CSS is currently generated inside the Swift WebView wrappers, then injected into EPUB chapters at load time.
- Existing app validation entries are `./script/build_and_run_catalyst.sh --verify` and `./script/build_and_run_native.sh --verify`; they check build and launch, but they do not capture Reader screenshots or assert layout.
- `script/verify_reader_harness.sh` runs the non-visual Reader harness checks and creates a temporary capture plan in `/tmp`.
- Fixture EPUBs are generated deterministically by `script/generate_reader_fixtures.py`; generated EPUB binaries are not required to be committed.
- A Debug-only Reader Regression Lab exists near the Books tab/import flow. It reuses the existing importer and `ReaderLoader`, opens generated fixture scenarios, and snapshots/restores the user's Reader settings around temporary scenario overrides.
- Automatic app-driven screenshot capture, geometry JSON capture, UI test driving, and pixel-diff baselines do not exist yet.

## Coverage Matrix

| Area | Required Coverage |
| --- | --- |
| Layout mode | Horizontal + paginated, horizontal + continuous scroll, vertical + paginated, vertical + continuous scroll |
| Theme | Light, Dark, Sepia, E-ink |
| Window | Normal window, resized narrow/wide window, full screen |
| Reading position | Chapter start, chapter end, long chapter middle |
| EPUB content | Plain text, multi-image page, cover image page, Ruby-heavy text, custom CSS/weird CSS, internal links, mixed text/image content |
| Reader chrome | Top title/progress/chrome, bottom buttons/statistics/chrome, focus mode visible/hidden |
| Interaction | Lookup popup open/close, nested popup lookup, image tap/fullscreen image, internal link jump |
| Audio/highlight | Sasayaki active highlight display, reveal, clear, and restore |
| Geometry facts | Viewport size, safe area, page width/height, writing mode, layout mode, scroll/page offset |

Minimum screenshot set:

| ID | Scenario |
| --- | --- |
| 01 | Horizontal paginated, Light, normal window, chapter start |
| 02 | Horizontal continuous, Light, normal window, long chapter middle |
| 03 | Vertical paginated, Light, normal window, chapter start |
| 04 | Vertical continuous, Light, normal window, long chapter middle |
| 05 | Vertical paginated, full screen, top and bottom chrome visible |
| 06 | Long chapter end, vertical and horizontal |
| 07 | Ruby-heavy text with lookup popup open |
| 08 | Multi-image page |
| 09 | Cover image page |
| 10 | E-ink theme with popup open |

## Fixture EPUB Plan

Fixture source should live in `testdata/reader-fixtures-src/`. Generated EPUBs should be written to `testdata/reader-fixtures/` by `script/generate_reader_fixtures.py`.

Do not casually commit large binary EPUB files. Small generated EPUBs can be committed later if they remain deterministic and reviewable; otherwise, commit the source and generator only.

| Fixture | Purpose | Key Chapters/Pages | Expected Result |
| --- | --- | --- | --- |
| `plain-horizontal.epub` | Baseline horizontal reading | Chapter 1 start, middle, end | Text is not covered by top or bottom chrome; pagination and progress are stable |
| `plain-vertical.epub` | Baseline Japanese vertical writing | Chapter 1 start, middle, end | Columns do not overlap; page turns move in the expected direction |
| `long-chapter.epub` | Stress progress restore and chapter middle | Middle and final pages | No blank page at restore; end position does not jump to next chapter too early |
| `chapter-boundary.epub` | Chapter start/end transitions | Last page of chapter 1, first page of chapter 2 | Next/previous chapter navigation is exact and does not flash blank content |
| `ruby-heavy.epub` | Ruby rendering and selection | Dense ruby paragraph and lookup target | Ruby is legible; selection and popup rectangles align with base text |
| `multi-image.epub` | Image containment | Several large images and captions | Images are contained; text continues after images without layout explosion |
| `cover-image.epub` | Cover sizing and SVG/image handling | Cover page | Cover does not stretch or overflow; fullscreen image path still works |
| `weird-css.epub` | Hostile EPUB CSS and custom CSS constraints | Tables, pre/code, large margins, unusual writing CSS | Reader constraints keep content readable without magic padding fixes |
| `internal-links.epub` | Fragment and file link jumps | TOC links, anchors, backward link | Internal jumps restore progress and stay in the correct spine item |
| `mixed-content.epub` | Realistic mixed Japanese content | Text, ruby, inline images, block images, links | Layout remains stable across combined stressors |

## Debug-Only Reader Regression Lab

Target entry name: `Reader Regression Lab`.

This must be Debug-only and must not affect Release UI. It should be enabled by a launch argument such as `--reader-regression-lab` or a clearly named debug UserDefaults key such as `HoshiReaderDebugShowReaderRegressionLab`. Release builds should not show the entry even if the key exists.

Current implementation status:

- A Debug-only Books toolbar entry exists when running on Mac Catalyst with `--reader-regression-lab` or `HoshiReaderDebugShowReaderRegressionLab`.
- The lab lists fixture and screenshot scenarios, checks generated fixture presence, imports the selected scenario fixture, applies temporary Reader settings, opens Reader, and restores the previous settings when Reader closes.
- `script/capture_reader_regression.sh` generates fixtures, creates a run directory, writes a screenshot manifest, and points to `./script/build_and_run_catalyst.sh --reader-regression-lab`.
- `script/verify_reader_harness.sh` runs the current non-visual Reader harness checks: fixture generator syntax, capture harness syntax, temporary capture plan creation, and static/behavior checks for popup geometry, Sasayaki highlight/shortcuts, native Reader settings reuse, and deterministic lab wiring.
- The lab does not yet jump to exact chapter positions, trigger known lookup/nested lookup states, synthesize Sasayaki highlight states, capture Reader geometry from inside Reader, or drive screenshots automatically.

Recommended next implementation:

- Add Reader-side hooks for deterministic chapter-position jumps and known lookup/nested lookup targets.
- Display a compact geometry panel that can be copied into bug reports and written next to screenshots.
- Add app-driving screenshot capture on top of the lab scenarios.
- Keep lab UI strings Debug-only, or add localization keys if they become visible outside internal builds.

Required lab controls:

- Import/open a fixture EPUB.
- Jump to a specific fixture chapter.
- Jump to chapter start, middle, or end.
- Toggle horizontal/vertical writing.
- Toggle paginated/continuous mode.
- Toggle Light, Dark, Sepia, and E-ink themes.
- Toggle top chrome.
- Toggle bottom progress/statistics chrome.
- Open a lookup popup for a known test word.
- Open a nested lookup popup.
- Apply/show/clear a Sasayaki highlight test state.
- Show viewport width/height, safe area, page width, page height, writing mode, layout mode, current scroll/page offset, and current Reader progress.

Non-goals for the first lab:

- Do not add a second Reader implementation.
- Do not patch layout with lab-only magic numbers.
- Do not persist fixture-specific settings into the user's real reading settings.
- Do not make Release builds depend on test fixtures.

## Screenshot Regression Plan

Script target: `script/capture_reader_regression.sh`.

First version goal: create a stable run directory and a manifest of screenshots to capture. It should not claim automated screenshot validation until the Debug-only lab and app-driving mechanism exist.

Output layout:

```text
artifacts/reader-regression/<timestamp>/
  README.md
  manifest.txt
  screenshots/
```

Planned screenshot names:

```text
01-horizontal-paginated-light.png
02-horizontal-continuous-light.png
03-vertical-paginated-light.png
04-vertical-continuous-light.png
05-vertical-fullscreen.png
06-long-chapter-end.png
07-ruby-popup.png
08-multi-image-page.png
09-cover-page.png
10-eink-popup.png
```

Future automation steps:

- Launch the Debug app with `--reader-regression-lab`.
- Open each fixture scenario; the lab imports the fixture and applies deterministic settings.
- Capture window screenshots using a stable app/window selector.
- Save geometry JSON next to each screenshot.
- Compare against `testdata/reader-baselines/<macos-or-webkit-version>/`.
- Use a pixel diff with a documented threshold.
- Upload screenshot and diff artifacts in CI for Reader-affecting pull requests.
- Require manual screenshot review before release when Reader/WKWebView/JS/CSS changed.

## Manual Release Checklist

```text
Open Reader Regression Lab.
Open plain-horizontal.
Switch to paginated.
Confirm top chrome does not cover text.
Confirm bottom chrome does not cover text.
Switch to continuous.
Confirm scrolling and progress are normal.
Open plain-vertical.
Confirm vertical paginated column width is normal.
Jump to the end of long-chapter.
Confirm chapter boundary does not show blank content or jump to the wrong chapter.
Open ruby-heavy.
Confirm ruby is not clipped and lookup popup coordinates are correct.
Open multi-image.
Confirm images do not overflow or explode layout.
Open cover-image.
Confirm cover is contained and image tap behavior is sane.
Open weird-css.
Confirm EPUB CSS does not cause top or bottom occlusion.
Open internal-links.
Confirm fragment jumps land in the correct spine item and progress updates.
Open a lookup popup and then a nested popup.
Confirm closing popups returns focus and geometry to Reader.
Enable a Sasayaki highlight test state.
Confirm highlight appears, reveals, clears, and restores after returning to Reader.
Enter full screen.
Repeat horizontal paginated, vertical paginated, ruby popup, multi-image, and chapter-end checks.
Exit full screen.
Confirm Reader remains responsive and returns to the same book position.
```

## When Reader Code Changes

For changes touching `Features/Reader/ReaderView/ReaderView.swift`, `Features/Reader/ReaderWebView/ReaderWebView.swift`, `Features/Reader/ScrollReaderWebView/ScrollReaderWebView.swift`, `reader.js`, `scrollreader.js`, selection/highlight scripts, or injected Reader CSS:

1. Build or run the app using the normal Mac Catalyst verification path.
2. Run `./script/verify_reader_harness.sh`.
3. Generate or refresh Reader fixtures if fixture source changed.
4. Capture the planned screenshot set, or state exactly why visual capture was unavailable.
5. Inspect top/bottom chrome, popup position, vertical pagination, images, and chapter boundaries manually.
6. Do not call a Reader visual fix complete unless screenshots or manual UI validation covered the affected scenario.
