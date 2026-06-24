# Native Reader Programmatic Navigation Statistics

## Context

`NativeReaderModel.saveBookmark(_:)` both persists the current position and flushes reading statistics. Programmatic navigation currently flushes the old position, mutates the Reader position, and then calls `saveBookmark(_:)` again. That second flush compares the new destination with the old statistics baseline, so chapter-list jumps, character/highlight jumps, history restoration, and internal EPUB links can count the jump distance as reading.

## Design

Separate bookmark persistence from reading checkpoints. User-driven page turns and continuous reading continue through `saveBookmark(_:)`, which persists the new progress and flushes statistics. Programmatic jumps instead flush the old position once, persist the destination without statistics, and reset the tracking baseline at the destination.

Known destinations such as chapter-list, character/highlight, and history positions reset the baseline immediately after the model changes position. Internal links follow the upstream split: same-chapter links restore or jump inside the existing WebView, while cross-chapter links load the destination chapter. Fragment jumps wait for WebView to report the resolved progress, then persist that progress without a statistics flush and reset the baseline.

Sequential next/previous chapter navigation remains ordinary reading. It switches to the adjacent chapter, persists the boundary position, and then flushes once so the final page interval is retained without a second programmatic-jump sample.

## Boundaries

- Do not change the `Statistics` storage format or synchronization behavior.
- Do not change normal paginated or continuous-scroll character accounting.
- Do not add user-visible UI or localization.
- Preserve navigation history, Sasayaki transition preparation, popup dismissal, and bookmark persistence.
- Same-chapter internal links must not reload the chapter.

## Verification

Extend the focused Reader source contract first and observe it fail. Require a persist-only bookmark path, programmatic-jump progress synchronization, baseline resets after known destinations, the same-chapter link branch, and removal of `saveBookmark` from programmatic restore paths. Then run the focused Reader regression contract, build and launch the exact Light app with `./script/build_and_run.sh --verify`, and manually validate the affected real-EPUB scenarios when safe test data is available.
