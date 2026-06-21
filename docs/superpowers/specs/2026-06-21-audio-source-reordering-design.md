# Audio Source Reordering Design

## Goal

Make the Audio settings source list support the same native macOS drag-and-drop ordering as the Dictionary settings list. The order controls audio lookup priority and must persist across launches.

## Interaction

- Show a reorder handle at the left edge of every audio source row.
- Allow dragging from anywhere on the row, not only from the handle.
- Highlight the current destination row while dragging.
- Move the source to the dropped row using the same destination-offset semantics as dictionary ordering.
- Keep toggles, deletion rules, and source editing behavior unchanged.

Default, local, and custom audio sources all participate in ordering. Enabling local audio inserts its source at the top only when it is newly added. Once present, the user's chosen position survives settings updates and app relaunches.

## Data Flow

`AudioView` writes reordered values directly to `UserConfig.audioSources`. Its existing `didSet` encoder persists the full ordered array in `UserDefaults`. Local-source synchronization removes legacy duplicate URLs but preserves the existing local source's current index and enabled state; it inserts the canonical local source only when missing and enabled.

Drag payloads use an audio-specific prefix so unrelated text or dictionary drops cannot reorder audio sources.

## Failure Handling

Invalid payloads, missing source IDs, and drops onto the same row are ignored without modifying or rewriting the configuration.

## Verification

- Unit-test audio drag payload parsing and forward/backward destination offsets.
- Contract-test the left handle, whole-row drag target, destination highlight, and persisted array move.
- Test local-source synchronization preserves its reordered position across relaunch-style normalization.
- Run the focused settings tests, Light build verification, and launch the exact built app.
