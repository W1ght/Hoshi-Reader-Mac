# Popup Duplicate Button Rendering Design

## Goal

Restore the v0.5.0-style `plus.square.on.square` appearance for disabled Add to Anki duplicate indicators in the native macOS popup while preserving the existing non-clickable behavior.

## Confirmed Root Cause

The current native macOS popup sets `window.hoshiUseInlineActionButtons = true`. Consequently, `syncButtonFrames()` removes the dormant AppKit `NSButton` overlays. The visible duplicate indicator is the handwritten SVG returned by `inlineButtonIcon()` in `Features/Popup/popup.js`, not the SF Symbol named by `PopupWebView.Coordinator.symbolName()`.

Live verification with the exact DerivedData Light app and an existing Anki duplicate for `星` confirmed that reducing the SVG stroke width only makes the approximation smaller and fainter. It cannot reproduce the optical proportions of the system `plus.square.on.square` symbol used by v0.5.0.

## Design

### System Symbol Renderer

Add a focused AppKit helper under `Features/Popup/` that:

- loads `NSImage(systemSymbolName: "plus.square.on.square")`;
- applies a 13-point medium symbol configuration, matching v0.5.0;
- renders the symbol as an alpha-bearing PNG on a transparent 28-by-28-point canvas at 3x pixel density;
- returns a `data:image/png;base64,...` URL;
- caches the result because the symbol geometry is static.

The PNG supplies only the system symbol's alpha shape. Popup CSS supplies the visible color through a mask, so custom popup themes and light/dark appearance continue to use the existing `currentColor` path.

### WebView Injection and Rendering

Pass the duplicate symbol data URL through the existing `callAsyncJavaScript` argument dictionary when the popup finishes navigation. Store it in `window.hoshiInlineButtonSymbols.duplicate` before `renderPopup()`.

For duplicate mining state, `inlineButtonIcon()` returns a mask span when the injected symbol is available. The span fills the existing 28-point button slot, while the 13-point system symbol remains centered inside its transparent canvas. If symbol generation fails, retain the existing duplicate SVG as a fallback.

The WebView button remains the interactive control. Preserve:

- native HTML `disabled` state;
- `data-enabled` state;
- click guard for disabled buttons;
- tooltip and accessibility label;
- existing disabled opacity and transparent background;
- popup scrolling, scaling, and layout behavior.

Do not re-enable the AppKit `NSButton` overlay path. Do not change audio, context-mining, or normal Add to Anki icons.

## Error Handling

Failure to load or encode the SF Symbol is non-fatal. The renderer returns `nil`, JavaScript receives no duplicate mask URL, and `inlineButtonIcon()` falls back to the current SVG. No user-facing error or localization change is required.

## Verification

1. Add an AppKit contract for a PNG data URL with an 84-by-84-pixel representation corresponding to a 28-point 3x canvas.
2. Update the popup source contract to require injection, mask rendering, fallback SVG, disabled state, and transparent background.
3. Demonstrate RED before adding the renderer and injection, then GREEN after the minimal implementation.
4. Run the neighboring mining-context popup contract and JavaScript syntax check.
5. Run `./script/build_and_run.sh --verify` and confirm bundle identifier `moe.shishamo.hoshi` plus the exact DerivedData executable path.
6. Open `hoshi://search?text=星` in that exact Light app and visually confirm the disabled duplicate symbol against the supplied v0.5.0 reference without pressing Add to Anki or modifying Anki data.

## Documentation and Localization

No user-visible text, persistence, migration status, or release behavior changes. `Localizable.xcstrings`, changelog, and migration truth-source documents do not require updates.
