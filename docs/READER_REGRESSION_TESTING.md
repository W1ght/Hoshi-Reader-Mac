# Reader Regression Testing

Reader visual correctness is validated with real EPUB data in the exact native macOS build. Generated fixtures, a Debug Regression Lab, automated screenshots, and pixel baselines were removed because they did not reproduce real-book edge clipping and could alter the Reader state being measured.

## Automated Contract Checks

Run:

```bash
./script/verify_reader_harness.sh
```

This keeps lightweight checks for Reader viewport logic, popup/Sasayaki integration, shortcuts, URL routing, release/upgrade contracts, and the absence of retired visual-harness hooks. `.github/workflows/reader-contract.yml` builds the native App and runs the same checks. These checks do not prove visual layout correctness.

## Actual-Data Validation

Use `./script/build_and_run.sh --verify` and accept evidence only when it reports bundle id `moe.shishamo.hoshi` and a running executable inside that exact DerivedData `.app`.

For Reader layout changes, exercise real EPUBs that cover:

- horizontal and vertical writing;
- paginated and continuous modes;
- normal, resized narrow/wide, and full-screen windows;
- chapter start, middle, and end, including dense or zero-margin text;
- zero Reader padding, where text must use the complete available viewport, plus a nonzero user-selected padding value;
- cover, image-heavy, and SVG content;
- lookup, nested lookup, popup dismissal, and return to reading;
- Sasayaki play/pause, cue navigation, highlight, and highlight restoration.
- previous/next shortcuts at the first page, penultimate page, final partial page, and the true chapter boundary.

For viewport and clipping work, inspect both text edges plus top and bottom chrome. The Reader WebView may extend into the top safe area so the titlebar band is not wasted, but it must stay out of the leading/trailing rounded-corner safe areas; fixed visual insets, side masks, leading/trailing safe-area extension, and chrome-derived body padding are not valid substitutes for correct pagination. Record the writing mode, reading mode, Reader padding, approximate window state, chapter position, and whether the book supplies its own margins. A screenshot may be attached as evidence, but it is not a versioned pixel baseline.

## Data Safety

- Do not import, replace, rename, or delete books in the user's library merely to run validation without explicit approval.
- Do not rewrite bookmarks, Reader settings, sidecars, or progress for automation. If a setting must change manually, restore it before handing back the workspace.
- Do not copy book text, titles, paths, or other private content into tracked artifacts. Describe test data only as narrowly as needed.
- If appropriate real EPUB data or an interactive UI pass is unavailable, state exactly which matrix entries remain unverified.

## Completion Evidence

A Reader change is complete only when the lightweight contract passes, the native App builds and launches with the expected identity, and the relevant actual-data matrix has been checked. Automated contract success alone must never be reported as proof that clipping, pagination, popup geometry, or visual styling is fixed.
