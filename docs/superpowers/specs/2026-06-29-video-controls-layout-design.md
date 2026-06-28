# Video Controls Layout Design

## Goal

Add a second low-obstruction Video playback control layout while keeping the current floating Liquid Glass control bar as the default. Users who prefer a YouTube-like bottom rail can opt in from Video settings without changing existing playback behavior for current users.

## User-Facing Behavior

- The existing floating glass bar remains the default layout.
- `Settings > Video > Playback` gains a localized `Control Bar Layout` segmented control.
- The setting has two choices:
  - `Floating`: the current draggable floating glass controls.
  - `Compact Bottom`: a YouTube-like low-obstruction bottom rail.
- Switching the setting updates the Video player immediately and persists in `UserDefaults`.
- Existing users keep the floating layout because the default decode value is `Floating`.

## Compact Bottom Layout

- The timeline becomes a thin progress rail near the bottom edge of the video canvas.
- Playback, previous, next, volume, speed, mining history, open video, profile, mine subtitle, inspector, and full-screen controls remain available in one compact row.
- The rail uses a restrained bottom gradient/scrim and small interactive controls rather than a large rectangular glass panel.
- The layout still auto-hides with pointer inactivity and reveals on pointer movement, matching current playback chrome behavior.
- Timeline hover and scrubbing still show the preview bubble above the progress rail.
- Speed controls can reuse the existing speed popover content, repositioned above the compact speed button.

## Architecture

- Add a Video-only `VideoControlBarLayout` enum in `UserConfig` with `floating` and `compactBottom` cases.
- Add `UserConfig.videoControlBarLayout` under `#if HOSHI_VIDEO`, stored as the raw string key `videoControlBarLayout`.
- Pass the selected layout from `VideoPlayerScreen` into `VideoControlsView`.
- Split `VideoControlsView` internally into two layout bodies that share the same action closures and state:
  - existing floating layout for `floating`
  - compact rail layout for `compactBottom`
- Keep playback engine, mpv rendering, subtitle parsing, popup lookup, mining, shortcuts, and menu commands unchanged.

## Subtitle and Overlay Clearance

- Floating layout keeps the current subtitle bottom clearance.
- Compact Bottom uses a smaller subtitle bottom clearance so subtitles can sit closer to their natural position.
- Popup `bottomInset`, timeline preview placement, and volume-scroll excluded rects should derive from the active control layout frame rather than assuming the old floating size everywhere.
- Full-screen behavior remains native macOS behavior: pointer movement reveals controls; controls and system chrome may auto-hide independently.

## Localization

Add Chinese and English entries to `Localizable.xcstrings` for all new visible strings:

- `Control Bar Layout`
- `Floating`
- `Compact Bottom`

If helper text is added under the setting, it must also be localized.

## Validation

- Add a lightweight Swift contract test for `VideoControlBarLayout` default decode and raw-value persistence.
- Build Light to ensure the setting and layout enum do not leak outside `HOSHI_VIDEO`.
- Build and launch Video with the exact built app path.
- Manually verify both layouts in normal and full-screen windows:
  - playback, pause, previous, next
  - seek and hover timeline preview
  - volume and mute
  - speed popover
  - mining history, profile menu, mine current subtitle, inspector, full screen
  - subtitle clearance with subtitles visible
  - auto-hide and reveal on pointer movement

## Out of Scope

- Removing or redesigning the existing floating layout.
- Adding a third hybrid layout in this pass.
- Changing Video shortcuts, playback engine behavior, mpv options, subtitle styling settings, or mining data format.
- Adding iOS, Catalyst, or non-native macOS support.
