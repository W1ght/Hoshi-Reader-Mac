# Popup Two-Column Layout Design

## Goal

Align the native macOS lookup popup with upstream commit `ed25036c` by adding the optional two-column masonry layout and refreshed glossary-card styling without regressing Mac-specific popup behavior.

## Scope

- Add a persisted `twoColumnLayout` user setting, disabled by default to preserve existing layouts after upgrade.
- Expose the setting in Dictionary Settings with localized Chinese and English labels and guidance.
- Increase the popup height slider maximum from 500 to 800, matching the upstream layout's intended large/full-width use.
- Render multiple dictionary glossary sections in a two-column masonry layout when enabled.
- Keep a single dictionary glossary section full width.
- Apply the upstream glossary-card border, padding, radius, and shadow treatment while preserving the native Mac popup's scale variables.

The lookup engine, result ordering, dictionary media, nested lookup, card mining, audio, profile selection/resolution, and popup placement are outside this change.

## Architecture

`UserConfig` remains the runtime source of truth for the preference. The preference is included in `DictionaryProfileSettings`; decoding older profile files treats a missing value as `false`. Both `PopupView.buildContent` and `DictionarySearchView.buildPopupPayload` serialize the current value into the popup document as `window.twoColumnLayout`, alongside the existing collapse and compact-glossary settings.

`popup.js` owns layout behavior because glossary sections are created incrementally in the WebView. Each entry receives a `.glossary-sections` container. A container with one dictionary gets `.single-section`; containers with multiple dictionaries use two-column masonry when the setting is enabled.

The upstream implementation is retained:

- Use native CSS masonry when WebKit reports support for `display: grid-lanes`.
- Otherwise use a `ResizeObserver` plus an animation-frame scheduler to place cards into the currently shorter column.
- Recalculate layout after resize and glossary expansion/collapse.
- Resynchronize native/inline action button frames after masonry changes so existing Mac hit targets remain correct.

`popup.css` owns the glossary-card appearance. New dimensions must use the existing popup scale variables or `calc(... * var(--popup-scale))` so popup scaling remains correct.

## User Interface

Dictionary Settings gains a `Two-Column Layout` toggle in the existing Behaviour card. Its help text explains that the layout is best suited to full-width or larger popups. Both strings receive Chinese and English localizations.

The preference defaults to off. Enabling it affects Reader, Dictionary, Quick Lookup, and Video lookup surfaces because they share `PopupWebView` and the same renderer; their existing payload builders only pass the preference into that shared path. No surface-specific layout implementation is introduced.

When enabled:

- Two or more dictionary groups form balanced columns.
- One dictionary group remains full width.
- Collapsing or expanding a group reflows the columns.
- Resizing the popup recomputes widths and positions.
- Back/forward navigation and incrementally loaded entries preserve the layout.

## Compatibility

The implementation must preserve:

- Existing AppKit/WKWebView integration and inline/native action buttons.
- Popup scale behavior and system-symbol rendering.
- Dictionary custom CSS as native CSS, applied after base popup styles.
- Collapse modes, first-dictionary expansion, compact glossaries, pitch accents, dictionary selection, keyboard entry navigation, nested lookup, media, audio, and Anki mining.
- Current profile and UserDefaults data. The new key is additive and defaults to `false` when absent.

No UIKit, Catalyst target, platform abstraction, or Video-only popup path is added.

## Testing

Implementation follows test-first development:

1. Add a focused source contract that asserts persistence, default-off behavior, settings exposure, content injection, glossary grouping, single-section handling, masonry fallback, resize/toggle scheduling, and scaled card styling.
2. Run the new contract before production edits and confirm it fails because the two-column feature is absent.
3. Implement the minimal upstream-aligned change and make the contract pass.
4. Run JavaScript syntax validation and existing popup, mining, shortcut, and dictionary contracts affected by the shared renderer.
5. Run `./script/build_and_run.sh --verify` and confirm the exact built Light app identity and executable path.
6. Manually verify Dictionary and Reader popups with the setting off and on, covering normal and full-width popup sizes, one and multiple dictionaries, collapsed groups, resize reflow, nested lookup, custom CSS, images, action buttons, and back/forward navigation.

If actual EPUB or suitable multi-dictionary data is unavailable, the final report must name those unverified visual scenarios rather than treating contract tests as UI proof.

## Documentation

Update `docs/CHANGELOG.md` because the toggle and refreshed glossary presentation are user-visible. Update other migration truth-source documents only if implementation changes their current state or validation guidance.
