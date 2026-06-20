# Anki Media Mining Fixes Design

## Goal

Make Reader and Video Anki media placeholders reliable while simplifying the Anki settings UI.

## Design

- Remove the Video-only anime-card helper section and preset. Video placeholders remain available in the normal field mapping picker.
- Resolve Reader `{book-cover}` from the active book model and pass it through the existing `MiningContext`/AnkiConnect picture path.
- Map Lapis `SentenceAudio` to `{sasayaki-audio}` when defaults fill an empty or missing field; preserve non-empty user mappings.
- Replace AVFoundation video-audio export with an independent bundled-libmpv encoding client. The exporter selects the active audio track, disables video/subtitles, mixes to mono, and writes 64 kbps AAC in an M4A container.
- Build the clip range from subtitle time plus subtitle delay, add 120 ms padding, and clamp it to the video duration.
- If `{video-audio-clip}` is mapped but export failed, abort Anki note creation and surface the failure instead of silently creating a card without audio.

## Validation

Use focused Swift/static contracts, export a clip from the reported MKV without touching Anki, then run Light and Video verification builds. Do not create a real Anki card without explicit permission.
