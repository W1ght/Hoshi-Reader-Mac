# Native Reader Navigation History Restoration

## Context

The native macOS Reader supports jumps from the chapter list, highlight list, and internal EPUB links, but the native migration omitted the previous Reader's navigation-history state and progress controls. A jump therefore overwrites the bookmark without offering a way to return to the prior reading position.

## Design

Add an in-memory navigation history to `NativeReaderModel`. A position contains the spine index and chapter-relative progress. Before a chapter-list, character/highlight, or resolved internal-link jump, append the current position to the back history and clear the forward history.

Expose the last back and forward positions as book-relative display counts. The Reader bottom controls show a backward return button beside the left-side controls and a forward return button beside the right-side controls. Each button displays the destination in the active Profile's character/word display units and uses the existing return-arrow SF Symbols.

Navigating through history moves the current position onto the opposite stack and uses the existing native navigation paths so bookmark persistence, statistics flushing, Sasayaki transitions, popup dismissal, chapter loading, and same-chapter WebView restoration remain consistent.

Manual page turns and continuous scrolling clear forward history after the user starts reading from a returned position. They do not create new back-history entries. Programmatic history navigation must not clear the opposite stack while it restores its destination.

## Boundaries

- History remains session-only and is not written to book sidecars or `UserDefaults`.
- Invalid or unavailable spine/book-info entries do not produce a displayed target.
- Ordinary next/previous page or chapter navigation is not recorded as a jump.
- Existing Reader data paths, bookmark formats, and Profile behavior remain unchanged.
- No new user-visible text is required; the controls use SF Symbols and numeric destinations.

## Verification

Extend the focused Reader regression contract first and confirm it fails before implementation. Cover position recording for character/chapter/internal-link jumps, back/forward stack movement, forward-history clearing on manual navigation, destination display conversion, and both native controls.

Then run the focused Reader regression contract and `./script/build_and_run.sh --verify`. In an exact DerivedData build with a real EPUB, manually check chapter, highlight, and internal-link jumps; backward and forward restoration; same-chapter and cross-chapter destinations; paginated and continuous modes; and bookmark/progress persistence after closing the Reader.
