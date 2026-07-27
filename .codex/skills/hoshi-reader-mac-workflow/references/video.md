# Video

Load this reference only for the Video library, playback, subtitles, remote media, windows, mining, or full-screen behavior.

## Required Context

- Read the current Video state in `docs/TODO.md` and the `Video Learning` section of `docs/ARCHITECTURE_REFACTORING.md`.
- Inspect `PlaybackEngine` and the nearest existing player/library boundary before changing UI state or media lifecycle.
- Treat current code and focused Video contracts as the detailed source for behavior they express; do not revive older per-Video Profile or build-variant designs from historical documents.

## Invariants

- SwiftUI and ordinary UI code operate through `PlaybackEngine`; libmpv C/Objective-C++ details remain inside the playback boundary.
- Video uses one AppKit-owned, non-restoring player window. Replacing or closing media must persist the intended state, cancel stale work, release playback resources, and balance security-scoped access.
- The library and collections are non-destructive indexes. Do not move, rename, rewrite, or delete user media or subtitle sidecars.
- Niratan-owned subtitle cues remain authoritative for interactive lookup, transcript, and mining. Do not render duplicate mpv and Niratan primary subtitles or create an unmatched invisible hit surface.
- Video lookup, nested Popup, word audio, duplicate checking, and Anki reuse shared services. Video-only media travels through `MiningContext.video`.
- YouTubeKit uses its pinned local method backed by system JavaScriptCore. Preserve its resource bundle; do not enable the hosted fallback or restore helper executables such as yt-dlp or Deno.

## Full-Screen UI Checks

- System traffic lights and player chrome are transient. Move the pointer to reveal the required control, immediately obtain fresh UI state, and click only the control from that snapshot.
- Wait for each AppKit full-screen transition before querying or acting again. Never reuse stale element identifiers or coordinates.
- Full-screen lifecycle code must not introduce persistent frame/aspect mutations or detach the render surface during AppKit snapshot resizing.

## Verification

- Select the affected `script/test_video_*` contracts, then run the full-feature build and open the exact player App with suitable disposable media.
- If shared Reader, Popup, audio, shortcuts, Anki, Profile, project, or packaging code changes, load and verify those references too.
- Do not claim subtitle, external network, account, hardware, HDR, or full-screen behavior that was not manually exercised.
