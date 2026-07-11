# Video Subtitle Edge Style Design

## Goal

Improve Video subtitle readability on visually busy footage without turning subtitle appearance into an advanced styling panel. Replace the current shadow-only control with one edge-style choice and one shared strength control, while keeping subtitles transparent by default and preserving existing user preferences.

## User-Facing Behavior

Video subtitle appearance exposes two edge controls in both the full Video Settings page and the in-player Inspector:

- **Edge Style**:
  - **Off**: no shadow or outline.
  - **Soft Shadow**: a darker, zero-offset black glyph halo inspired by asbplayer's subtitle treatment.
  - **Clear Outline**: a crisp black outline around each glyph without a soft halo.
  - **High Contrast**: a stronger black glyph outline for the busiest footage.
- **Edge Strength**: one `0...100%` slider controlling the selected style. It changes shadow blur radius or outline width according to the active style.

New installations default to **High Contrast** at **50%** strength. The renderer derives concrete metrics from normalized strength `s` and font size `f` using this reference recipe:

- `scale = clamp(f / 36, 0.5, 2)`
- shadow radius `= min(8, 6 * s * scale)` points
- clear-outline width `= min(4, 2.5 * s * scale)` points
- high-contrast outline width `= min(2.5, 1.5 * clear-outline width)` points

Soft Shadow uses one native black, zero-offset TextKit glyph shadow at the calculated radius. Clear Outline draws only the calculated outline. High Contrast draws the stronger capped outline without combining it with the shadow. At the default 36pt size and 50% strength, Soft Shadow uses a 3pt halo, Clear Outline uses a 1.25pt outline, and High Contrast uses a 1.875pt outline. A zero strength suppresses all edge rendering regardless of the selected non-Off style.

Edge colors remain fixed black. The existing subtitle color, font, size, weight, background, vertical position, mask, and lookup highlight controls remain unchanged. No advanced disclosure or separate shadow/outline color controls are added.

## Appearance and Interaction

The edge effect belongs to the glyphs, not the subtitle row. It must remain evenly distributed around the text with no downward offset and must not create a rectangle, glass surface, material, or background card.

The styles have distinct intent:

- **Soft Shadow** prioritizes a natural video-subtitle look. Increasing strength makes the zero-offset halo wider.
- **Clear Outline** prioritizes maximum edge separation on detailed footage. Increasing strength widens the glyph outline without blurring it.
- **High Contrast** is the default readability recipe. It uses a stronger outline than Clear Outline and caps it at 2.5pt to preserve the white glyph fill.

Changing either control updates the currently visible subtitle immediately. The same values appear in Video Settings and the Inspector because both surfaces bind to the shared `UserConfig` state.

## Configuration and Migration

Add a persisted `VideoSubtitleEdgeStyle` value and normalized edge-strength value to `UserConfig`. The style is a stable string-backed enum with `off`, `softShadow`, `clearOutline`, and `highContrast` cases. Strength is stored as a clamped `Double` in `0...1`; the UI presents it as `0...100%`.

Migration is evaluated only when the new edge-style keys are absent:

- If the legacy `videoSubtitleShadowRadius` key exists, migrate to **Soft Shadow** with `strength = clamp(legacyRadius / 10, 0, 1)`. This preserves the intent of users who previously adjusted Shadow.
- If the legacy key does not exist, use the new **High Contrast**, `0.5` default.

The legacy shadow value remains available as a compatibility projection during this change rather than being destructively deleted. Light builds continue to ignore all Video-only appearance behavior, and switching between Light and Video configurations does not rewrite the new values.

## Rendering Boundary

Keep style selection and persistence in `UserConfig`, style-to-rendering recipe conversion in the Video subtitle presentation layer, and glyph rendering inside the existing AppKit-backed interactive subtitle view. `PlaybackEngine`, libmpv, subtitle parsing, cue timing, lookup coordination, mining, and transcript rendering remain unchanged.

The shadow and outline recipes use native TextKit attributed-string glyph effects on the existing interactive `NSTextView`. They must not be implemented by chaining view-level shadows, repeating sibling text layers, or manually redrawing one layout manager, because those approaches can recursively darken the glyph fill or create black compositing blocks. Keeping one text view preserves CJK and Latin glyph contours without altering hit testing or selection ranges.

Lookup highlights remain visually above the edge treatment. Native text selection, click lookup, Shift-hover lookup, subtitle masking, and popup geometry must continue to use the original text layout and UTF-16 offsets.

## Localization

Add localized Chinese and English strings for:

- Edge Style / 边缘样式
- Edge Strength / 边缘强度
- Off / 关闭
- Soft Shadow / 柔和阴影
- Clear Outline / 清晰描边
- High Contrast / 高对比度

Reuse the same localized strings in Video Settings and the Inspector.

## Error Handling and Fallback

Invalid persisted style values fall back to **High Contrast**. Non-finite or out-of-range strength values clamp to the supported range. If native edge attributes cannot be applied for a particular font, the subtitle must remain filled; subtitle display and playback must never fail because of an appearance effect.

## Verification

Automated contracts and focused tests must cover:

- new defaults and clamping;
- legacy shadow migration;
- all four style cases;
- both settings surfaces binding to the same state;
- absence of separate edge-color controls;
- preservation of transparent subtitle backgrounds;
- Light source and bundle isolation.

Visual validation must use the exact Video build and cover:

- light, dark, high-detail, and rapidly changing footage;
- 12pt, default 36pt, and 72pt subtitles;
- CJK, Latin, punctuation, and mixed-script text;
- one-line and wrapped multi-line cues;
- native text selection, click lookup, Shift-hover lookup, and lookup highlight;
- subtitle blur/opacity masks;
- windowed and native full-screen playback.

Light must also build and launch through the exact DerivedData path after the shared configuration change.

## Non-Goals

- User-selectable shadow or outline colors.
- Separate controls for shadow offset, blur radius, opacity, or outline width.
- Subtitle background cards, glass, or material.
- ASS/SSA style import or preservation.
- Changes to subtitle parsing, timing, placement, transcript appearance, lookup behavior, mining, or mpv subtitle rendering.

## Success Criteria

- Default subtitles remain legible across busy light and dark footage without an opaque background.
- The in-player Inspector adds only one style selector and one strength slider.
- Users can choose a darker soft shadow, a crisp outline, a stronger high-contrast outline, or no edge effect.
- Existing customized shadow users retain a visually comparable soft-shadow setting after migration.
- Subtitle selection, lookup, masking, layout, playback, and Light/Video boundaries remain unchanged.
