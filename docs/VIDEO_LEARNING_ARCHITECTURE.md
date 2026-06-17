# Video Learning Architecture

## Product Variants

Hoshi ships one native macOS target through two schemes:

| Variant | Configuration | Compile condition | Artifact |
| --- | --- | --- | --- |
| Light | `Debug` / `Release` | none | `Hoshi-Reader-Mac-<version>.dmg` |
| Video | `Debug-Video` / `Release-Video` | `HOSHI_VIDEO` | `Hoshi-Reader-Mac-Video-<version>.dmg` |

Both variants use `de.manhhao.hoshi`, the same App name, and the same persistence paths. Light must not link, copy, or look up libmpv.

## Dependency Direction

```text
NativeMac sidebar
  -> Features/Video/VideoPlayerScreen
       -> PlaybackEngine <- MpvPlayerEngine -> libmpv
       -> SubtitleParser -> SubtitleCueStore -> SubtitleOverlayView
       -> VideoLookupCoordinator -> PopupPresentationCoordinator
                                  -> LookupEngine / PopupView / WordAudioPlayer
       -> VideoMiningCoordinator -> MiningContext.video
                                  -> existing AnkiManager / AnkiConnect
       -> VideoMiningHistoryStore -> fixed Mining History sidebar
```

Shared Reader, Dictionary, Popup, audio, and Anki services never import or require Video. Video supplies selection geometry and optional mining metadata to those services.

## Unified Keyboard Shortcut Plan

### Current Implementation Findings

The existing shortcut settings are centralized in one UI, but the model and runtime dispatch are not yet unified:

- `Features/Settings/KeyboardShortcutsView.swift` hard-codes Reading, Sasayaki, and Dictionary sections through a private action enum and a switch that writes individual `UserConfig` properties. It does not expose Global or Video groups, defaults, scope-aware conflicts, or conflict state.
- `Core/UserConfig.swift` stores Reader, Sasayaki, and Dictionary bindings as separate `UserDefaults` values. The shared value type is still named `ReaderKeyboardShortcut`, although non-Reader modules already use it.
- `Core/ReaderKeyboardShortcutAppKitBridge.swift` owns AppKit event conversion and matching. `Features/Settings/ShortcutKeyCaptureView.swift` provides the current recorder, while `NativeMac/NativeShortcutCaptureView.swift` and `NativeMac/NativeShortcutCaptureProbeView.swift` retain a second capture representation that should be removed after migration.
- `NativeMac/NativeReaderView.swift` mixes hidden SwiftUI `.keyboardShortcut` buttons with a local `NSEvent` monitor for Sasayaki.
- `Features/Video/VideoPlayerScreen.swift` currently hard-codes Command-O, Space, Left Arrow, and Right Arrow in hidden buttons.
- Dictionary previous/next bindings have settings and persistence, but no runtime consumer was found during the current repository search. Phase S0 must establish whether this is a missing native migration behavior or an obsolete configuration before changing it.
- Popup dismissal and nested-popup priority are not represented by a shared shortcut scope. This prevents a reliable rule such as “Escape closes the topmost popup before Reader or Video handles Escape.”

The long-term destination remains the existing `Settings > Advanced > Keyboard Shortcuts` surface. Video Settings must contain only video preferences and may provide a deep link such as `Open Keyboard Shortcuts > Video`; it must not own a second shortcut editor or store.

### Recommended Model

```text
Settings/KeyboardShortcutsView
  -> ShortcutRegistry
       -> GlobalShortcutActions
       -> ReaderShortcutActions
       -> DictionaryShortcutActions
       -> PopupShortcutActions
       -> SasayakiShortcutActions
       -> VideoShortcutActions [HOSHI_VIDEO registration only]
  -> ShortcutConflictChecker
  -> UserConfig.ShortcutConfiguration

App/window event bridge
  -> ShortcutManager
       -> active scope stack
            popup (highest contextual priority)
            focused surface: reader | dictionary | video
            sasayaki capability within reader
            global
       -> ShortcutHandler registered by the active feature
```

| Abstraction | Responsibility |
| --- | --- |
| `KeyboardShortcutBinding` | Neutral replacement for `ReaderKeyboardShortcut`; Codable key and modifier representation plus AppKit/SwiftUI bridges. Preserve the current encoded form during migration. |
| `ShortcutAction` | Stable action ID and localized metadata: category, allowed scopes, default binding, title, help text, and priority policy. It is a descriptor, not one application-wide switch enum. |
| `ShortcutScope` | Runtime context such as Global, Reader, Dictionary, Popup, Sasayaki, or Video. It defines which actions can be active together. |
| `ShortcutCategory` | Settings grouping: Global, Reader, Dictionary / Popup, Sasayaki, and Video. Category is presentation metadata and must not be used as runtime scope. |
| `ShortcutRegistry` | Collects module-owned action descriptors, resolves current/default bindings, and provides one ordered catalog to Settings and runtime dispatch. It has no SwiftUI dependency. |
| `ShortcutConflictChecker` | Reports hard conflicts only when scopes can overlap and priority cannot resolve them. It may report popup shadowing as informational rather than invalid. |
| `ShortcutManager` | Owns the single app/window-level key event path, active scope stack, responder filtering, and priority resolution. It must not import Video or Reader UI. |
| `ShortcutHandler` | Contextual action closure registration owned by the active feature. Handlers appear and disappear with feature lifecycle and do not store bindings. |
| Module action catalogs | `ReaderShortcutActions`, `DictionaryShortcutActions`, `PopupShortcutActions`, `SasayakiShortcutActions`, and `VideoShortcutActions` declare their own actions and defaults without creating separate stores or event monitors. |

`ShortcutConfiguration` should be one versioned dictionary keyed by stable action IDs. On first load it imports the existing individual `UserDefaults` keys without overwriting customized values. Legacy keys remain readable for a compatibility window and are removed only after migration tests and downgrade behavior are decided.

### Scope and Priority Rules

- The same physical binding is valid in mutually exclusive scopes. For example, Left Arrow can mean previous page in Reader and seek backward five seconds in Video.
- Global actions overlap every primary surface and therefore conflict with an identical surface binding unless an explicit system or priority rule permits both.
- Popup is an overlay scope above Reader, Dictionary, and Video. Escape closes the topmost nested popup first; after the popup stack becomes empty, the underlying surface may handle Escape.
- Sasayaki runs inside Reader and can overlap Reader actions. Duplicate bindings between these scopes are conflicts unless their activation predicates are provably exclusive.
- Text fields, shortcut recording, marked-text input, and other editable responders take precedence over feature shortcuts. The manager must not consume ordinary typing or IME composition.
- Video full-screen and focus mode update active context but continue through the same manager. Video views must not add a separate event monitor.
- Light and Video share the manager, storage format, and action IDs. `VideoShortcutActions` is registered only under `HOSHI_VIDEO`, so Light does not show unusable Video rows while preserving any Video bindings already stored by the other variant.

Initial Video declarations should cover play/pause, seek backward, seek forward, toggle full screen, and exit full screen/focus mode. Open File may remain a Global action whose handler is supplied by Video when Video is the active destination. Advanced subtitle and mining shortcuts are deferred.

### Settings Design

`KeyboardShortcutsView` becomes a registry-driven grouped list with these sections:

1. Global
2. Reader
3. Dictionary / Popup
4. Sasayaki
5. Video, present only in the Video variant

Each row shows the action title, current binding, default binding, conflict or shadowing state, and reset affordance. The screen may accept an initial category/filter so future Video Settings can navigate directly to the Video section without creating another editor.

All new action names, category names, conflict descriptions, reset labels, and navigation text must be added to `Localizable.xcstrings` in Chinese and English.

### Staged Migration

| Phase | Scope | Exit criteria |
| --- | --- | --- |
| S0: behavior inventory | Record every existing binding and runtime consumer; determine the missing Dictionary handler behavior; add resolution, migration, and label tests before changing dispatch. | Existing Reader/Sasayaki behavior and customized binding persistence are captured by tests. |
| S1: neutral model and registry | Introduce the neutral binding type, stable action IDs, scopes, categories, versioned configuration, registry, and legacy-key import. Keep current runtime handlers active. | Existing users retain bindings; registry resolves current and default values identically in Light and Video. |
| S2: grouped Settings and Video declarations | Drive the unified settings page from the registry; add scope-aware conflict reporting and Video action declarations. Do not require all actions to use the new runtime manager yet. | Global/Reader/Dictionary-Popup/Sasayaki/Video grouping renders correctly; Video is absent from Light; no second Video shortcut page exists. |
| S3: shared runtime dispatch | Add one manager/event bridge and migrate Reader, Dictionary, and Sasayaki handlers module by module. Remove each old hidden button or monitor only after its replacement passes tests. | One key press produces one action; text editing and system shortcuts remain intact. |
| S4: popup priority | Connect `PopupPresentationCoordinator` stack state to the Popup scope and migrate Escape/nested-popup actions. | Escape closes nested popup, then parent popup, then reaches the underlying surface. |
| S5: Video runtime integration | Register Video handlers for playback, seeking, full screen, and focus mode; remove hard-coded Video keyboard buttons. | Configured Video bindings work in windowed/full-screen modes and do not fire in Reader or Light. |
| S6: cleanup | Remove duplicate native capture probes, obsolete per-feature monitors, legacy property switches, and legacy keys after the compatibility window. | Registry, manager, recorder, and configuration each have one production implementation. |

### File-Level Shortcut Plan

| Phase | Add or modify | Purpose | Risk | Verification |
| --- | --- | --- | --- | --- |
| S0-S1 | `Core/Shortcuts/KeyboardShortcutBinding.swift`, `Core/ReaderKeyboardShortcutAppKitBridge.swift` | Generalize the existing value and event bridge while preserving Codable data and key normalization. | Existing saved bindings or non-US keyboard layouts stop matching. | Label, Codable round-trip, AppKit event normalization tests. |
| S1 | `Core/Shortcuts/ShortcutAction.swift`, `ShortcutScope.swift`, `ShortcutRegistry.swift`, `ShortcutConflictChecker.swift` | Define stable descriptors, scope overlap, registration, default resolution, and conflict diagnostics. | Giant central enum recreates feature coupling; incorrect overlap rules reject valid reuse. | Registry uniqueness and scope-resolution tests. |
| S1 | `Core/UserConfig.swift` | Replace individual writes with versioned `ShortcutConfiguration` and one-time legacy import without deleting old values. | Customized shortcuts are reset or two variants overwrite each other. | Fresh install, customized legacy data, Light-to-Video-to-Light migration tests. |
| S1-S2 | `Features/Reader/ReaderShortcutActions.swift`, `Features/Dictionary/DictionaryShortcutActions.swift`, `Features/Popup/PopupShortcutActions.swift`, `Features/Sasayaki/SasayakiShortcutActions.swift` | Move action declarations and defaults to their owning modules. | Defaults drift from current behavior. | Snapshot/catalog tests against existing defaults. |
| S2 | `Features/Video/VideoShortcutActions.swift` | Declare initial Video actions under the Video compilation boundary; no separate storage or manager. | Video symbols leak into Light. | Light compile plus registry catalog comparison. |
| S2 | `Features/Settings/KeyboardShortcutsView.swift`, `Features/Settings/ShortcutKeyCaptureView.swift` | Render registry groups, current/default bindings, conflicts, reset, and optional category deep link. | Recorder captures Escape or consumes navigation unexpectedly. | Settings UI walkthrough, recorder cancel/rebind/reset tests. |
| S2 | `Features/Settings/AdvancedView.swift`, `NativeMac/NativeReuseViews.swift` | Keep all navigation routes pointed at the same unified settings destination. | Duplicate or inconsistent settings entry points. | Navigate from every existing Settings route. |
| S2 | `Localizable.xcstrings` | Localize categories, actions, defaults, conflict state, and deep-link text. | Light references Video-only UI strings incorrectly. | Chinese/English Light and Video UI checks. |
| S3 | `Core/Shortcuts/ShortcutManager.swift`, `Core/Shortcuts/ShortcutHandler.swift`, `NativeMac/HoshiNativeMacApp.swift` or the native root scene | Install one event path and inject active scope/handler lifecycle. | Duplicate monitors, stale scopes, or swallowed text input. | Dispatch ordering, focus, IME, window switching, and deallocation tests. |
| S3 | `NativeMac/NativeReaderView.swift` and the confirmed Dictionary runtime entry | Replace hidden buttons/local monitors incrementally with registered handlers. | Reader paging or Sasayaki fires twice; currently missing Dictionary behavior is guessed incorrectly. | Reader harness plus manual Reader/Dictionary shortcut matrix. |
| S4 | `Features/Popup/PopupPresentationCoordinator.swift`, `Features/Popup/PopupView.swift` | Publish popup-stack scope and handle topmost dismissal/nested actions. | Escape closes the Reader/Video surface behind a popup. | Popup and nested-popup priority tests in Reader and Video. |
| S5 | `Features/Video/VideoPlayerScreen.swift` | Register playback handlers and remove hard-coded key bindings. | Full-screen/focus lifecycle leaves a stale Video scope. | Windowed/full-screen playback and cross-surface isolation tests. |
| S6 | `NativeMac/NativeShortcutCaptureView.swift`, `NativeMac/NativeShortcutCaptureProbeView.swift`, legacy shortcut members in `Core/UserConfig.swift` | Remove duplicate/probe paths only after production migration is stable. | Premature deletion removes a native validation path or downgrade compatibility. | Full Light/Video build and migration regression suite. |

### Shortcut Validation

Automated validation should extend, rather than replace, the current build and harness commands:

```bash
swift script/test_reader_keyboard_shortcut_labels.swift
swift script/test_shortcut_registry.swift
swift script/test_shortcut_scope_resolution.swift
swift script/test_shortcut_conflicts.swift
swift script/test_shortcut_config_migration.swift
./script/build_and_run.sh --verify
./script/build_and_run.sh --video --verify
./script/verify_reader_harness.sh
./script/verify_video_harness.sh
```

The new focused scripts are planned names and must be added only with the phase that implements the corresponding abstraction.

Manual acceptance matrix:

- Rebind, clear, reset, cancel recording with Escape, restart the App, and switch Light/Video variants without losing values.
- Confirm Left Arrow can be assigned to Reader previous page and Video seek backward without a conflict.
- Confirm a Global binding conflicting with an active surface action is reported.
- Confirm Sasayaki/Reader overlapping bindings are reported according to their simultaneous activation.
- With a nested popup open in Reader and Video, press Escape repeatedly and verify topmost popup, parent popup, then surface behavior.
- Verify shortcuts do not fire while editing Settings text fields, using the shortcut recorder, or composing Chinese/Japanese text.
- Verify Reader page turn, Dictionary navigation once its intended native behavior is confirmed, Sasayaki controls, Video playback/seek, full screen, focus mode, window switching, and App relaunch.
- Verify Light contains no Video settings group, code path, or libmpv dependency; Video uses the same stored configuration and unified manager.

### Shortcut Migration Risks

| Risk | Mitigation |
| --- | --- |
| Legacy values are overwritten | Import individual keys once into a versioned configuration, preserve customized values, and test upgrade plus variant switching. |
| Old and new handlers both fire | Migrate one action family at a time and remove its old hidden button/monitor in the same verified change. |
| Scope model treats all duplicates as conflicts | Model simultaneous scope overlap separately from UI category; test Reader/Video reuse and Reader/Sasayaki overlap explicitly. |
| Popup Escape reaches the underlying surface | Drive Popup scope from the coordinator's actual stack and resolve it before Reader/Dictionary/Video. |
| Event monitor consumes typing or IME input | Respect first responder, marked text, recorder state, and system-reserved command handling before feature dispatch. |
| Full-screen or navigation leaves stale handlers | Use lifecycle-bound handler tokens and scope ownership; test screen switches, window close, and player teardown. |
| Keyboard layout normalization changes behavior | Retain the existing AppKit mapping initially and add non-US layout/event regression coverage before broadening it. |
| Dictionary migration invents behavior | Locate or define the intended native navigation contract in S0 before wiring its persisted actions. |
| Video contaminates Light | Keep only Video action registration under `HOSHI_VIDEO`; shared shortcut types, storage, manager, and Settings rendering remain Video-independent. |

## Implemented Scope

- Local mpv media open, including common video containers and audio-only formats such as `m4b`, with play/pause, seek, duration/progress and keyboard controls.
- Unified shortcut registry, versioned binding migration, scope-aware conflict display, Popup-first dispatch, and grouped Global/Reader/Dictionary-Popup/Sasayaki/Video settings.
- Same-folder naturally sorted episode queue, previous/next episode controls, episode selection, configurable EOF auto-advance, and optional per-file playback position restore.
- Playback speed, volume/mute, subtitle timing adjustment, and libmpv video/audio/subtitle track selection.
- Video preferences live in the existing Settings surface and include auto-play next, playback-position memory, and the shared seek interval used by Video shortcuts. Shortcut editing remains exclusively in the unified Keyboard Shortcuts page.
- A visible full-screen control and the unified full-screen shortcut share native macOS window full-screen behavior.
- External subtitle timing follows the same delay as mpv; selecting an external subtitle disables the embedded subtitle track to prevent duplicate rendering. When a local media file has an mpv-style same-name `.srt`/`.vtt` sidecar, Hoshi also parses that sidecar into its own transcript/lookup overlay so seeking to an arbitrary time can immediately show nearby subtitle rows instead of waiting for mpv's current-line snapshots.
- External subtitle import is resilient to large files and non-ASCII paths: Hoshi prepares subtitle cue stores and transcript rows off the main actor, mpv `sub-add` retries with a `file://` URL if raw filesystem loading fails, and mpv import failure does not prevent Hoshi's overlay/transcript path from using the parsed subtitle.
- Embedded text subtitle tracks are mapped from mpv's `sub` track type into Hoshi cues and rendered through the interactive overlay. Image-based subtitles remain rendered by mpv.
- Subtitle mask controls can blur or make Hoshi-owned text subtitles transparent until pointer hover. The controls live in both Video Settings and the inspector's Subtitles tab, persist in `UserConfig`, and do not create a separate mpv subtitle renderer or rectangular blur overlay.
- Native macOS media presentation with a floating Liquid Glass control surface on macOS 26+, material fallback on older supported systems, and restrained custom chrome intended to remain visually compatible with macOS 27.
- Video UI follows a Hoshi learning-player direction rather than a general-purpose player skin: the bottom OSC is a fixed, single-row Liquid Glass pill with only playback core controls always visible.
- The Video section hides the system window toolbar so playback is not pushed down by top chrome. A compact floating glass group in the video surface owns the sidebar toggle and the minimal open-video affordance; subtitle loading and advanced controls live in the inspector.
- Speed, timing, chapters, media tracks, external subtitles, episode selection, playback options and transcript access live in a right-side IINA-inspired Liquid Glass inspector with `Episodes`, `Video`, `Audio`, `Subtitles` and `Transcript` sections. The inspector overlays the trailing edge of the video surface and may cover the picture like IINA; it must not take side-by-side layout space or resize the media canvas. Inspector tabs and multi-choice controls should reuse the same glass segmented/pill language as native Settings controls instead of plain bordered controls. IINA is only a UX reference; Hoshi does not copy IINA source, assets, or app architecture.
- Player shutdown and security-scoped URL cleanup when leaving the screen.
- SRT/VTT parsing, overlapping cue lookup and Hoshi-owned subtitle overlay.
- Subtitle click lookup, nested popup lookup, pause/resume coordination and existing local word audio.
- Existing AnkiConnect mining with video file, timestamp, cue, adjacent-cue handlebars, and a bounded Video mining history that records trigger-time pending rows and updates them to added, duplicate, or failed after AnkiConnect returns.
- A fixed right-side Mining History sidebar lists recent video mining attempts by media file, supports jump-to-subtitle, copy, delete, and clear actions, and pushes the video surface instead of covering the picture.
- Chapter navigation, audio timing, file loop, A-B study loop, aspect-ratio override and 90-degree rotation.
- A synchronized transcript panel whose rows seek playback. Transcript rows are rendered through a moving time-neighborhood window so large subtitle files load near the current playback position first, then extend when the user scrolls to the window edge or playback advances into the next chunk. Large external subtitle imports prepare their timeline store and transcript off the main actor, and the SwiftUI list watches a lightweight transcript change token instead of comparing the full row array. Embedded/mpv rolling subtitle snapshots are merged and deduplicated before entering the transcript so empty intervals or repeated active cues do not collapse the list to one row.
- The transcript panel owns its scrolling surface. It must not be nested inside another inspector `ScrollView`, because an unbounded parent proposal causes SwiftUI to materialize too many rows and reintroduces large-subtitle stalls.
- Opening media loads the selected file immediately and scans same-folder playlist entries asynchronously. Slow folders, cloud-backed Documents contents, or large sibling directories must not block first playback.
- On-demand libmpv frame capture and AVFoundation audio-clip export for existing AnkiConnect media fields.
- Light/Video package and release contracts.

## Deferred Scope

Secondary/bilingual subtitle import, embedded secondary-subtitle extraction, full ASS layout fidelity, viewing statistics and sync remain future work.

### mpv Capability Alignment

| Priority | Capability | Status |
| --- | --- | --- |
| P0 | Open/play/pause/seek, fullscreen, speed, volume/mute, same-folder episodes | Implemented |
| P0 | Video/audio/subtitle track selection and subtitle delay | Implemented |
| P0 | External SRT/VTT and embedded text subtitle lookup overlay | Implemented |
| P1 | Chapter list and chapter seek | Implemented |
| P1 | Audio delay control | Implemented |
| P1 | Loop file and A-B loop for study repetition | Implemented |
| P1 | Screenshot and audio-clip mining | Implemented; audio export depends on AVFoundation container support |
| P2 | Aspect ratio, rotation and basic video presentation controls | Implemented |
| P2 | Transcript panel | Implemented |
| P2 | Mining history sidebar | Implemented |
| P2 | Secondary/bilingual subtitle tracks | Deferred until primary subtitle import, transcript navigation, lookup and mining are fully validated |
| P3 | Shader profiles, video equalizer, deinterlace and advanced filter graphs | Intentionally deferred; these are general-player features rather than Hoshi learning essentials |

## Validation

```bash
./script/build_and_run.sh --video
./script/build_and_run.sh --video --verify
./script/verify_video_harness.sh
xcodebuild -project 'Hoshi Reader.xcodeproj' -scheme 'Hoshi Reader' -configuration Release -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
xcodebuild -project 'Hoshi Reader.xcodeproj' -scheme 'Hoshi Reader Video' -configuration Release-Video -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
./script/verify_native_release_contract.sh
./script/verify_reader_harness.sh
```

Before release, manually test playback lifecycle, subtitle timing/click geometry, popup nesting, local word audio, and Anki success/duplicate/failure on a machine without Homebrew libmpv.

Current real-UI subtitle smoke coverage: `/Users/wight/Documents/Dear Jane -  銀河修理員 Galactic Repairman (Official Music Video) - Dear Jane (1080p, h264, youtube).mp4` with `/Users/wight/Documents/[住野よる] また、同じ夢を見ていた.srt` imports successfully, shows both Hoshi and mpv subtitle tracks, renders subtitle text, and opens the transcript tab without the previous full-file layout stall.

## Visual Contract

- Treat the video page as a Hoshi learning surface, not a general-purpose player skin.
- Hide the system window toolbar on the Video page. Keep window management discoverable with a small floating glass sidebar toggle and a transparent drag strip instead of a full top toolbar.
- Keep a fixed single-row floating glass OSC over the video. Only previous/play-next, timeline, volume, inspector toggle, and full screen stay visible.
- Collect non-core controls in the right-side inspector: episode list, video track/options, audio track/timing, subtitle track/external subtitle/timing/mask, and transcript. The inspector should be a trailing overlay over the video, not a split view/sidebar that shrinks the video. Do not move those controls back into a bottom `More` popover unless a separate UI decision reverses this layout.
- Mining History is the deliberate exception to the inspector overlay rule: it is a fixed trailing sidebar outside the video `ZStack`, so it shrinks the video surface instead of covering the picture or subtitle lookup overlay.
- The inspector itself should read as Liquid Glass at every layer: a glass outer panel, glass section cards, Settings-style glass segmented controls for mutually exclusive choices, and glass pill action buttons. Avoid ordinary bordered buttons or system segmented controls that visually flatten the panel.
- Do not add auto-hide or mouse-idle fade behavior until a separate interaction design pass covers it.
- Subtitle text remains on a transparent overlay without a glass, material, black, or opaque background frame; lookup popups continue to use the shared Hoshi popup presentation. Subtitle masking is limited to blur/opacity effects on the text row and must reveal on pointer hover.
- Secondary subtitles remain deferred; when implemented, they should be smaller and dimmer than primary subtitles without changing the primary subtitle lookup path.
- New custom glass elements must include a macOS 15 material fallback until the deployment target changes.
