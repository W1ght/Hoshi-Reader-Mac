# Video Subtitle and Controls Stability Design

**Date:** 2026-07-13
**Updated:** 2026-07-14

## Goal

Keep subtitle placement predictable relative to the visible video picture between windowed and native full-screen playback, keep Compact Bottom controls anchored to the player-surface bottom edge, simplify the play and speed buttons, and make the speed adjustment panel dismiss when the user clicks elsewhere on the video surface.

## Scope

This change applies only to the Video variant and reuses the existing playback actions, settings, shortcut handling, popup pipeline, and control layouts. It does not change playback semantics, subtitle timing, the study sidebar, lookup behavior, or the native full-screen window boundary.

## Subtitle Vertical Position (Superseded)

The fixed-point subtitle-position design in this section was superseded by [Video Subtitle Relative Position Design](2026-07-14-video-subtitle-relative-position-design.md). The final behavior uses an unlabeled top-to-bottom slider backed by a normalized `0...1` value inside the fitted video viewport, measures the complete subtitle stack, and keeps that stack visible at both endpoints when it fits. The legacy point key is retained as migration input only.

## Subtitle Viewport Alignment

- IINA delegates subtitle placement to mpv: `sub-pos` controls position, while its full-screen letterbox preference maps to mpv's `sub-use-margins` and `sub-ass-force-margins`. Niratan cannot delegate rendering because its subtitles must remain selectable for lookup, so it adopts the same geometry truth source instead.
- The libmpv bridge publishes `osd-dimensions` surface size and `mt`/`mb`/`ml`/`mr` video margins. A small pure geometry helper scales those actual rendering margins into the current SwiftUI video surface.
- While mpv geometry is temporarily unavailable, the helper falls back to the effective aspect ratio already used by window sizing: automatic media display dimensions, explicit aspect-ratio override, and 90°/270° rotation are all reflected before viewport fitting.
- `SubtitleOverlayView` is framed and bottom-aligned inside that fitted viewport. This keeps the vertical offset stable across top/bottom letterboxing and also keeps subtitle wrapping and centering inside the visible picture when left/right pillarboxing is present.
- Display size, backing scale, window resizing, study-sidebar resizing, aspect override, rotation, and native full-screen transitions update the viewport through mpv property changes and normal SwiftUI geometry changes. No monitor dimensions or screenshot-specific inset is stored.
- If both mpv render geometry and the effective video aspect ratio are temporarily unavailable or invalid while media loads, the helper safely falls back to the full video surface; the next valid playback snapshot recalculates the viewport.
- Lookup selection rectangles continue to resolve in the existing `video-player` coordinate space after viewport placement, so popup anchoring and mining context remain unchanged.
- The viewport calculation does not mutate `NSWindow`, install an AppKit aspect constraint, detach the mpv render view, or add work to native full-screen transition callbacks.

## Control Bar Placement

- Compact Bottom is always positioned at the bottom edge of the outer player surface with zero user drag offset. Letterbox space may therefore contain controls in full screen, while subtitles remain relative to the visible video picture.
- Switching from Floating to Compact Bottom clears any active or stored drag offset so an old Floating position cannot lift the compact bar into the video.
- Floating retains its existing global-coordinate drag behavior and edge clamping.
- Window resizing and native full-screen transitions continue to derive the Compact Bottom position from the current video-surface geometry; no window-frame mutation is introduced.

## Play and Speed Button Appearance

- The play/pause button no longer applies its own Liquid Glass circle.
- The speed button no longer draws a persistent rounded fill or stroke.
- Both buttons keep their existing hit targets, labels, accessibility metadata, foreground treatment, keyboard behavior, and lightweight pressed feedback.
- The Floating control bar keeps its single outer glass surface. Compact Bottom keeps its existing bottom scrim. No other control button styling changes.

## Speed Panel Dismissal

- Speed-panel visibility becomes player-surface presentation state rather than state known only inside `VideoControlsView`.
- Tapping the speed button toggles the panel.
- Interacting with the speed panel, its presets, slider, or custom field keeps the panel open.
- Clicking elsewhere on the video canvas closes the speed panel immediately.
- The existing canvas dismissal layer remains below the controls, so it does not intercept control or panel interaction.
- A canvas click may continue to dismiss existing transient video overlays according to their current behavior; no AppKit-wide event monitor is added.

## Validation

Automated validation will cover:

- the shared normalized relative-position policy, endpoint fitting, and legacy-value migration;
- aspect-fit viewport geometry for equal-aspect, top/bottom letterbox, left/right pillarbox, invalid-ratio fallback, explicit ratio overrides, rotation, and multiple display/container sizes;
- identical subtitle relative position inside the fitted picture in windowed and full-screen presentation;
- viewport-relative subtitle width and popup-coordinate-space preservation;
- zero Compact Bottom offset and retained Floating drag behavior;
- absence of the play-button glass effect and speed-button persistent fill/stroke;
- player-surface ownership of speed-panel visibility and canvas-click dismissal;
- existing Video interaction, Liquid Glass, settings, window, and full-screen contracts;
- Light and Video build/launch verification.

Manual Video validation will cover:

- subtitle placement at the top, default, and bottom slider positions in windowed and full-screen playback, confirming that the full stack remains visible at both endpoints when it fits and does not shift when full screen introduces black bars;
- subtitle alignment after resizing, changing aspect override, rotating, and showing the pushed study sidebar;
- Compact Bottom remaining attached to the bottom after switching from a dragged Floating layout, resizing, entering full screen, and exiting full screen;
- play and speed button appearance;
- opening the speed panel, using its controls, and closing it by clicking elsewhere on the video.

## Non-Goals

- Removing or redesigning the Floating layout.
- Persisting Floating control-bar drag position across launches.
- Changing the speed adjustment panel's contents or playback-speed limits.
- Allowing subtitle position beyond the visible fitted video picture.
- Coupling subtitle position to playback-control clearance.
- Moving Compact Bottom or Floating controls into the fitted video viewport.
- Adding crop, pan, or zoom modes. The `osd-dimensions` boundary already follows mpv's rendered area, but any future mode still requires explicit UI and interaction validation.
