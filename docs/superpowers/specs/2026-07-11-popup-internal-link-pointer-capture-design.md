# Popup Internal Link Pointer Capture Fix

## Problem

Normal pointer clicks on structured dictionary links such as `?query=サラダオイル&wildcards=off` do not trigger the link handler after the popup selection-preservation behavior began capturing the pointer on the entries container. Accessibility link activation still works, confirming that lookup, redirect rendering, and history restoration are intact.

## Root Cause

`popup.js` calls `setPointerCapture` on the entries container for every eligible `pointerdown`. WebKit consequently retargets the rest of the pointer sequence to that container. A normal click that starts on a structured-content anchor can therefore bypass the anchor's `onclick` handler, while programmatic or accessibility activation continues to work.

## Design

Keep the current pointer-capture behavior for ordinary dictionary content so dragging a text selection outside the popup continues to preserve the selection. Do not capture the pointer when the original pointer target is an interactive element, including links, buttons, summaries, form controls, or their descendants.

The existing internal-link path remains unchanged after activation:

1. Parse the `query` parameter from the structured-content link.
2. Ask the shared Swift lookup callback for destination entries.
3. Redirect the existing popup content when results exist.
4. Push the previous snapshot onto the existing history stack.
5. Enable the existing back/forward action-bar controls.

This behavior applies to both Popup and Dictionary surfaces because both use the shared `popup.js` renderer.

Popup action-bar visibility follows two inputs: the user's persistent action-bar preference and the current popup's redirect history. When the preference is off, the bar stays hidden initially but appears after the first successful internal redirect and remains present while backward or forward history exists. When the preference is on, it is always visible.

When Sasayaki controls are present, Back, Forward, Sasayaki playback controls, and Close share a single row. The buttons use plain styling with fixed transparent hit frames so no individual button background is visible while click targets remain comfortably sized.

## Alternatives Rejected

- Delaying pointer capture until movement crosses a threshold would touch the selection gesture state machine more broadly and risks regressing drag-outside selection.
- Manually invoking link behavior from the container's `pointerup` handler would duplicate browser activation semantics and could mishandle keyboard or accessibility activation.
- Replacing the current popup with a separate navigation implementation would duplicate the existing redirect and history stack.

## Testing

Add a focused regression contract that verifies interactive pointer targets are excluded from pointer capture while ordinary content still uses capture and releases it on completion or cancellation. Run the popup contract suite and the shared Reader/Popup regression suite.

Build and launch the exact Light app. Manually verify a normal mouse click on the `サラダ` entry's `サラダオイル` cross-reference redirects to the destination and that the existing back/forward controls restore both entries. Also verify ordinary text can still be dragged outside the popup without losing the selection. If the actual Reader popup cannot be exercised without modifying user book state, report that limitation explicitly.

## Scope

The shared popup pointer gesture boundary, Popup action-bar composition, and their regression tests change. No lookup semantics, dictionary data, navigation history format, settings, persistence, or localization changes are required.
