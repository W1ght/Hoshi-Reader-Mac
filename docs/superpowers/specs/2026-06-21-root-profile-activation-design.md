# Root Profile Activation Design

## Goal

Make the native macOS root surface the single owner of runtime Profile activation so Global, Book, and Video contexts cannot overwrite each other through view appearance ordering.

## Ownership

`NativeMacRootView` derives the active `ProfileContext` from the visible product surface:

- An open Reader uses `.book(profileID:bookLanguage:)`.
- The active Video section uses `.video(profileID:)` with the persisted Video selection.
- Bookshelf, Dictionary, and Settings use `.global`.

A narrow `ProfileActivationCoordinator` resolves that context through `ProfileRepository` and applies the same resolved Profile ID to `ProfileSettingsStore`, `DictionaryManager`, and `AnkiManager`. Views may persist user selections, but they do not directly claim or restore shared Profile services.

## Lifecycle

The root activates the current context on initial appearance and whenever the selected section, open Reader book, global Profile, or Video Profile selection changes. Reader language prompting/backfill remains in the existing Reader preparation flow; activation occurs only for the final accepted book.

`VideoPlayerScreen` no longer activates a Profile in `onAppear`, `onChange(isActive:)`, or `onDisappear`. Selecting a Video Profile first closes the current Video popup stack, then persists the selection. The root observes that selection and activates it only while Video is the active section. Leaving Video restores the current Global Profile.

## Explicit Lookup Context

Video Popup and mining continue receiving the resolved Video `profileID`. Reader Popup and nested lookup continue carrying their resolved Book `profileID`. Root activation supplies the correct shared dictionary query and settings for the visible surface but does not replace explicit lookup/mining context propagation.

## Failure Handling

Unknown Profile IDs continue falling back through `ProfileResolver`. A failed Video Profile persistence operation remains a Video error. Profile activation is ignored when the resolved Profile no longer exists, matching the existing manager guards.

## Verification

- Unit-test root surface context selection for Global, Book, and Video.
- Add a contract proving `VideoPlayerScreen` no longer mutates the three shared Profile services.
- Add a transition regression for Global English → Japanese Video → Global English and for changing the selected Video Profile while Video is active.
- Run Profile and Video focused tests, `verify_video_variant_contract.sh`, Light `--verify`, and Video `--video --verify`.
- Leave the exact Video build running. Manual Popup/dictionary verification is required when suitable local Video and Profile data are available; otherwise report it as unverified.
