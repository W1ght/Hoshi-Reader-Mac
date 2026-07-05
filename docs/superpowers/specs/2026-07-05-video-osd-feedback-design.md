# Video OSD Feedback Design

## Goal

Add a reusable, lightweight video on-screen display (OSD) so users can see the result of shortcut-driven and inspector-driven playback/subtitle adjustments without opening the inspector or guessing the current value.

## Approved Direction

The OSD appears in the top-left corner of the video surface. It should feel like a native player status overlay: white text with strong shadow, no visible card or glass background by default, and an optional blue meter line only when the value has a meaningful range.

Only one primary OSD is shown at a time. Repeated changes refresh the text/value and extend the fade-out instead of stacking multiple messages.

## Scope

Include the required user-visible changes only:

- Playback speed changes, including reset to 1.00x.
- Volume changes, mute, and unmute.
- Subtitle visibility changes.
- Subtitle track cycling or selection changes.
- Subtitle timing changes and reset.
- Audio timing changes and reset.

Do not add OSD events for ordinary play/pause, seek forward/backward, opening sidebars, opening the inspector, mining, or other actions that already have clear visual feedback or could create noisy high-frequency overlays.

## Component Design

Create a reusable Video OSD model and SwiftUI view inside the Video feature boundary.

The OSD event should carry:

- A localized title such as `Volume`, `Speed`, `Subtitle Delay`, or `Subtitle Track`.
- A formatted value such as `68`, `1.25x`, `+0.35s`, `On`, `Off`, or a track name.
- An optional detail string for secondary context such as an external subtitle filename.
- An optional meter value from 0 to 1 for ranged values such as volume.

`VideoPlayerScreen` owns the current OSD state and a fade task. It provides small helper methods for showing each approved event type. Existing controls, inspector callbacks, menu commands, and shortcut handlers call those helpers after the underlying model change succeeds.

## Formatting

- Speed: `1.25x`, `1.00x` for reset.
- Volume: integer percentage-like value without a percent sign unless the existing UI already uses `%`.
- Mute: `Muted` / `Unmuted`.
- Subtitle delay and audio delay: signed seconds with two decimals, e.g. `+0.35s`, `-0.50s`, `0.00s`.
- Subtitle visibility: `On` / `Off`.
- Subtitle track: selected track title or external subtitle filename when available; `Off` when subtitles are disabled.

All user-visible strings go through `Localizable.xcstrings` with Chinese and English coverage.

## Verification

Add focused contract coverage for:

- The reusable OSD view/state exists inside `Features/Video/`.
- Shortcut handlers for speed, volume, subtitle delay, audio delay, subtitle visibility, and subtitle track call OSD helpers.
- Inspector or control callbacks for the same required events also call OSD helpers.
- The OSD auto-dismiss task is cancelled/restarted rather than stacking messages.

Run the relevant Video contract tests plus Light and Video builds for this Video UI change.
