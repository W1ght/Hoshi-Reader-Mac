# Video Controls Polish Design

## Goal

Refine the two Video control layouts after visual review. `Compact Bottom` should use white controls throughout, while `Floating` should keep its original glass color language but take up less space.

## User-Facing Behavior

- `Floating` remains a gray Liquid Glass floating control bar with the existing primary/secondary label treatment and blue progress track.
- `Floating` becomes more compact:
  - bar width is reduced from the previous 760pt feel to about 690pt
  - row height, icon frames, spacing, and padding are slightly tightened
  - the control still reads as the same existing floating style rather than a new white-bottom style
- `Compact Bottom` keeps the full-width bottom rail and transparent scrim, but all control icons and text are white.
- Disabled compact-bottom buttons should remain visible but use reduced white opacity.
- The speed button and profile menu should follow the active layout: floating keeps existing color; compact bottom uses white.

## Architecture

- Keep one `VideoControlsView`, but add layout-aware sizing and button style inputs instead of duplicating action logic.
- Store compact floating dimensions as explicit constants near existing control sizing constants.
- Extend the existing button styles with a color treatment parameter so layout selection controls foreground and pressed-state opacity without introducing separate button components.
- Keep `VideoPlayerScreen`, playback engine, subtitles, popup lookup, and settings persistence unchanged unless a layout metric needs a matching adjustment.

## Validation

- Extend `script/test_video_player_interactions_contract.swift` to assert:
  - floating width uses the compact 690pt constant
  - compact-bottom controls apply white foreground styling
  - floating controls do not use the compact-bottom white style
- Extend `script/test_video_liquid_glass_contract.swift` to assert the compact floating sizing and existing floating glass surface are preserved.
- Run focused Video contract tests.
- Build and launch both Light and Video variants with exact DerivedData app verification.
- Sample Video process CPU/RSS after launch to check for idle churn.

## Out of Scope

- Changing the persisted layout setting.
- Adding another layout mode.
- Reworking playback actions, popup behavior, subtitles, shortcuts, mining, or mpv playback.
