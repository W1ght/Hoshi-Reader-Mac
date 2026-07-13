# Video Subtitle Relative Position Design

**Date:** 2026-07-14
**Status:** Approved
**Scope:** Niratan Video only

## Goal

Replace fixed-point subtitle vertical offsets with an IINA-style position relative to the fitted video picture. For every subtitle stack that fits in the picture, the control must have stable fully visible top and bottom endpoints on every window and display size, and the UI must not expose a numeric value.

## Reference Behavior

IINA exposes subtitle position through mpv `sub-pos`, whose meaning is relative to screen height rather than a fixed point offset. Niratan keeps its native interactive subtitle renderer for lookup, so it will reproduce the relative-position behavior inside the libmpv-reported video viewport rather than delegating subtitle rendering to mpv.

Niratan intentionally does not reproduce mpv's unsafe `100...150%` overflow range. mpv documents that values above 100 may cut off text subtitles. Niratan's two slider endpoints instead mean “fully visible at the picture top” and “fully visible at the picture bottom.”

References:

- [IINA subtitle position binding](https://github.com/iina/iina/blob/c5dccbc8554aafa01efda91cd3f28ae2c3c51a98/iina/MPVController.swift#L507-L514)
- [mpv `sub-pos` semantics and clipping warning](https://github.com/mpv-player/mpv/blob/02254b92dd237f03aa0a151c2a68778c4ea848f9/DOCS/man/options.rst#L2418-L2433)

## Position Semantics

- The persisted position is a normalized fraction in `0...1`.
- `0` places the complete subtitle stack against the top of the fitted video picture.
- `1` places the complete subtitle stack against the bottom of the fitted video picture.
- Intermediate values interpolate through the available travel after subtracting the measured subtitle-stack height:

  `originY = max(viewportHeight - subtitleHeight, 0) * position`

- Invalid persisted values fall back to the default and finite out-of-range values clamp to `0...1`.
- The default is `0.9`, preserving an IINA-like near-bottom presentation without forcing the subtitle to the absolute bottom.
- Subtitle position no longer depends on Floating or Compact Bottom control-bar clearance. Selecting the bottom endpoint may intentionally place subtitles behind visible controls; the user explicitly controls that position.
- When the subtitle stack is taller than the viewport, its origin stays at the top and the existing non-clipped overlay behavior remains; no position can make an oversized stack fully fit.

## Video Viewport Integration

`VideoPlayerScreen` continues to frame `SubtitleOverlayView` inside the fitted picture viewport established by the current task:

1. Prefer libmpv `osd-dimensions` and its `mt`/`mb`/`ml`/`mr` video margins.
2. Fall back to the effective media/override/rotation aspect ratio while mpv geometry is unavailable.
3. Perform normalized subtitle placement inside that local viewport.

The position therefore adapts automatically to window resizing, Retina backing scale, native full screen, letterboxing, pillarboxing, aspect override, rotation, and pushed study-sidebar width without display-specific constants.

## Layout Boundary

Introduce a small subtitle-position layout boundary with two responsibilities:

- A pure helper calculates vertical origin from viewport height, measured subtitle height, and normalized position.
- A SwiftUI layout measures the existing subtitle `VStack` and places it at the calculated origin while retaining the current horizontal padding, wrapping width, hit testing, selection, masking, and popup coordinate conversion.

The layout must respond naturally when cue count, wrapping, font, font size, edge allowance, viewport size, or full-screen state changes. It must not cache subtitle height in `UserDefaults` or add full-screen-specific branches.

`bottomClearance` is removed from `SubtitleOverlayView` and from the Video control-layout metrics if it has no remaining consumer.

## Settings and Inspector UI

Both Video Settings and the playback inspector use the same normalized binding and show:

- the existing “Vertical Position” label;
- a top-position SF Symbol;
- an unlabeled continuous slider;
- a bottom-position SF Symbol.

Neither surface renders the current fraction, percentage, point count, or any other numeric value. No new user-visible text is required.

## Persistence and Migration

Use a new defaults key, `videoSubtitleVerticalPositionFraction`, so released fixed-point values cannot be misread as normalized values. Keep the legacy `videoSubtitleVerticalPosition` key untouched for compatibility and rollback.

On first load without the new key:

- legacy `0` maps to the new `0.9` default;
- positive legacy values preserve the “move upward” direction and interpolate from `0.9` toward `0`, reaching the top at legacy `200`;
- negative legacy values preserve the “move downward” direction and interpolate from `0.9` toward `1`, reaching the bottom at legacy `-200`;
- values outside the released `-200...200` range clamp to the corresponding endpoint;
- missing or non-finite legacy data maps to `0.9`.

The migrated fraction is persisted under the new key. Appearance reset restores `0.9`.

## Non-Goals

- Delegating interactive text subtitle rendering to mpv.
- Supporting mpv's below-picture `100...150%` overflow range.
- Adding on-video drag positioning, which would conflict with lookup and native text selection.
- Changing subtitle timing, font sizing, edge rendering, mask behavior, popup behavior, mining, or control-bar placement.

## Verification

Automated coverage must include:

- pure placement at `0`, `0.5`, and `1` for multiple viewport and subtitle heights;
- clamping, invalid input, and subtitle-taller-than-viewport behavior;
- legacy migration for `-200`, negative intermediate, `0`, positive intermediate, `200`, out-of-range, missing, and non-finite values;
- one shared normalized binding in Settings and Inspector;
- absence of a numeric vertical-position label;
- removal of fixed-point multiplication and control-bar clearance from subtitle placement;
- preservation of the mpv fitted-viewport and `video-player` popup coordinate-space contracts.

Manual validation on the exact final Video build must cover:

- top, middle, default, and bottom positions in a normal window;
- the same positions after entering and leaving native full screen;
- a long wrapped subtitle at both endpoints;
- Floating and Compact Bottom layouts without subtitle movement when switching layouts;
- lookup selection and popup anchoring near the top and bottom endpoints.

Light and Video builds, native release contracts, Video variant contracts, related Video contract scripts, and `git diff --check` remain required before completion.
