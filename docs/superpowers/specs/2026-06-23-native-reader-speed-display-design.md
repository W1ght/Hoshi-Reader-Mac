# Native Reader Speed Display Design

## Problem

The native Reader calculates session statistics and preserves the `Show Reading Speed` and `Show Reading Time` settings, but its chrome never reads those settings. Both options therefore have no visible effect after the Catalyst-to-native migration.

## Design

Restore a native `statisticsString` derived from `NativeReaderModel.sessionStatistics`. Gate it behind Statistics and the existing per-field switches, convert raw character rates through the active book Profile, and format elapsed time with the existing system duration style.

Render the statistics string in the bottom information capsule. When progress is also configured at the bottom, show both lines in the same restrained capsule. Focus mode continues to hide informational chrome.

## Verification

- Extend the Reader migration contract to require both settings, session statistic values, Profile-aware speed conversion, and bottom-chrome rendering.
- Confirm the contract fails before implementation and passes afterward.
- Run the bookshelf contract, focused Reader/Popup/Sasayaki regression contract, and exact Light build/launch verification.
- Do not alter user statistics or Reader settings for automated UI validation.
