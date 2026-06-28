# Reader Persistence Debugging

This note records the debugging pattern from the Sasayaki playback-position
incident and the follow-up Reader statistics investigation. Use it when a
Reader sidecar file appears to contain stale or missing state.

## Principle

Do not infer the failing layer from the final JSON file alone. Reader state can
be written more than once during one user action, especially around popup
dismissal, WebView callbacks, SwiftUI view disposal, AppKit window close, and
auto-sync scheduling.

Instrument the whole chain:

1. The user-visible trigger.
2. The model state recorded at that trigger.
3. The immediate persistence call.
4. The close/disappear/termination lifecycle boundary.
5. The disk write success or failure.

For local runs, start with:

```bash
/usr/bin/log stream --style compact --info --predicate 'process == "Hoshi Reader" AND subsystem == "moe.shishamo.hoshi" AND (category == "SasayakiPersistence" OR category == "ReaderPersistence" OR category == "ReaderStatistics")'
```

For shortcut delivery problems in debug builds, temporarily include
`ShortcutTrace` in the category predicate.

## Sasayaki Playback Position

Expected cue-jump chain:

1. `reader.sasayakiJumpShortcut`
2. `reader.sasayakiCueBookmark.sync.request`
3. `reader.sasayakiCueBookmark.sync`
4. `reader.bookmark.save.success`
5. `sasayaki.playCue.request`
6. `sasayaki.seek.request`
7. `sasayaki.persist.position`
8. `sasayaki.save.success`

The incident signature was:

1. The cue jump wrote the new `sasayaki_playback.json` position correctly.
2. Closing the Reader window delivered the global close notification to several
   old `NativeReaderView` / `NativeReaderModel` instances.
3. Those stale models still owned old `SasayakiPlayer` instances.
4. A stale close-time `teardown()` sampled or saved the old position and
   overwrote the newer sidecar.

The confirming logs were a newer `sasayaki.save.success position=<new>` followed
by close-time logs such as:

```text
reader.lifecycle.windowWillClose.received ...
reader.prepareForClose.start ... progress=<old>
sasayaki.teardown.start ... current=<old> pending=nil playing=false
sasayaki.save.success ... position=<old>
```

The fix has three guards:

- `ReaderWindowPresenter` posts the closing Reader request ID.
- `NativeReaderLifecycleRegistry` lets only the latest active model for that
  request handle the close.
- `SasayakiPlayer.flushPlayback()` does not let inactive stale players overwrite
  a newer persisted position when there is no pending seek.

When validating this class of bug, do not count repeated shortcut presses in one
open Reader window as a full regression test. Exercise separate windows:

1. Open the Reader window.
2. Click text to open lookup.
3. Trigger the Sasayaki cue jump.
4. Close only the Reader window.
5. Reopen the Reader and confirm the bookmark/highlight/playback position.
6. Repeat.

## Reader Statistics Showing Time But Zero Characters

The statistics sidecar can show nonzero `readingTime` with zero
`charactersRead` for several different reasons. Diagnose which layer failed
before changing accounting rules.

Relevant logs:

- `reader.statistics.start`: tracking began and recorded the baseline.
- `reader.statistics.pageTurn`: a manual page-turn boundary was observed.
- `reader.statistics.baseline`: the current raw-character baseline changed.
- `reader.statistics.flush`: a flush was requested.
- `reader.statistics.update`: time and character deltas before applying them.
- `reader.statistics.zeroCharacterPosition`: tracking is active while the
  current raw-character position resolves to zero.
- `reader.statistics.save.start/success/failure`: `statistics.json` write path.

The current character position is derived from `bookinfo.json`:

```text
currentTotal + Int(Double(chapterCount) * progress)
```

If `readingTime` increases but `charactersRead` stays at zero, check:

1. Is the current spine item a cover, title page, or other zero-character
   frontmatter chapter?
2. Does `bookinfo.json` contain an entry for the current spine item path?
3. Does the entry have `currentTotal == 0` and `chapterCount == 0`?
4. Did `reader.statistics.pageTurn` fire for the user action?
5. Did a later `reader.statistics.update` report `charDiff == 0` because
   `current == last == 0`?
6. Did `reader.statistics.save.success` write the same zero-character total?

Use a read-only sidecar inspection when needed:

```bash
python3 - <<'PY'
import json, os
root = os.environ["BOOK_ROOT"]
for name in ["bookinfo.json", "bookmark.json", "statistics.json"]:
    path = os.path.join(root, name)
    print("\n==", name, "==")
    with open(path) as f:
        data = json.load(f)
    if name == "bookinfo.json":
        print("characterCount:", data.get("characterCount"))
        for item in list(data.get("chapterInfo", {}).items())[:10]:
            print(item)
    else:
        print(data)
PY
```

Do not rewrite user bookmarks, Reader settings, sidecars, or books merely to
debug statistics. If a real-book UI pass is needed, use the exact DerivedData
app verified by `./script/build_and_run.sh --verify`, and record which Reader
settings or book position were touched.

