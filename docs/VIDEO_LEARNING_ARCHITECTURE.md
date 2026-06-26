# Video Learning Architecture

## Product Variants

Hoshi ships one native macOS target through two schemes:

| Variant | Configuration | Compile condition | Artifact |
| --- | --- | --- | --- |
| Light | `Debug` / `Release` | none | `Hoshi-Reader-Mac-<version>.dmg` |
| Video | `Debug-Video` / `Release-Video` | `HOSHI_VIDEO` | `Hoshi-Reader-Mac-Video-<version>.dmg` |

Both variants use `moe.shishamo.hoshi`, the same App name, and the same persistence paths. Light must not link, copy, or look up libmpv.

## Dependency Direction

```text
NativeMac sidebar -> VideoWindowCoordinator -> dedicated Video Window
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

Video remembers its own explicit Profile ID. The main and dedicated Video scene roots activate Profile services only while their respective `NSWindow` is key: Video applies its selected language, dictionary display/order and Anki mappings, while the main window restores the active Book or Global context when focus returns. `VideoPlayerScreen` only persists the selector choice and passes the resolved Profile through shared Popup and mining coordinators rather than activating shared services or adding Video-only lookup or Anki clients.

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

The sole editing destination is the native `Settings > Shortcuts & Controls > Keyboard Shortcuts` surface. Video Settings contains only video preferences and does not duplicate the shortcut inventory, navigation entry, recorder, or store.

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

Video declarations cover play/pause, seek backward/forward, previous/next episode, playback speed, mute/volume, subtitle previous/next seek, subtitle show/hide, subtitle track cycling, subtitle timing, transcript, loop controls, rotation, toggle full screen, and exit full screen/focus mode. Open File may remain a Global action whose handler is supplied by Video when Video is the active destination. Mining-specific shortcuts are deferred.

### Settings Design

`KeyboardShortcutsView` becomes a registry-driven grouped list with these sections:

1. Global
2. Reader
3. Dictionary / Popup
4. Sasayaki
5. Video, present only in the Video variant

Each row shows the action title, current binding, default binding, conflict or shadowing state, and reset affordance. Video actions remain a category within this unified screen rather than becoming a separate settings page.

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
| S2 | `Features/Settings/AdvancedView.swift`, `NativeMac/NativeReuseViews.swift` | Keep Video separate from Reader and keep shortcut editing under the shared Shortcuts & Controls group in every settings route. | Duplicate or inconsistent settings entry points. | Navigate from every existing Settings route. |
| S2 | `Localizable.xcstrings` | Localize categories, actions, defaults, conflict state, and deep-link text. | Light references Video-only UI strings incorrectly. | Chinese/English Light and Video UI checks. |
| S3 | `Core/Shortcuts/ShortcutManager.swift`, `Core/Shortcuts/ShortcutHandler.swift`, `NativeMac/HoshiNativeMacApp.swift` or the native root scene | Install one event path and inject active scope/handler lifecycle. | Duplicate monitors, stale scopes, or swallowed text input. | Dispatch ordering, focus, IME, window switching, and deallocation tests. |
| S3 | `NativeMac/NativeReaderView.swift` and the confirmed Dictionary runtime entry | Replace hidden buttons/local monitors incrementally with registered handlers. | Reader paging or Sasayaki fires twice; currently missing Dictionary behavior is guessed incorrectly. | Focused shortcut tests plus the actual-EPUB Reader/Dictionary shortcut matrix. |
| S4 | `Features/Popup/PopupPresentationCoordinator.swift`, `Features/Popup/PopupView.swift` | Publish popup-stack scope and handle topmost dismissal/nested actions. | Escape closes the Reader/Video surface behind a popup. | Popup and nested-popup priority tests in Reader and Video. |
| S5 | `Features/Video/VideoPlayerScreen.swift` | Register playback handlers and remove hard-coded key bindings. | Full-screen/focus lifecycle leaves a stale Video scope. | Windowed/full-screen playback and cross-surface isolation tests. |
| S6 | `NativeMac/NativeShortcutCaptureView.swift`, `NativeMac/NativeShortcutCaptureProbeView.swift`, legacy shortcut members in `Core/UserConfig.swift` | Remove duplicate/probe paths only after production migration is stable. | Premature deletion removes a native validation path or downgrade compatibility. | Full Light/Video build and migration regression suite. |

### Shortcut Validation

Automated validation should extend, rather than replace, the current build and focused contract commands:

```bash
swift script/test_reader_keyboard_shortcut_labels.swift
swift script/test_shortcut_registry.swift
swift script/test_shortcut_scope_resolution.swift
swift script/test_shortcut_conflicts.swift
swift script/test_shortcut_config_migration.swift
./script/build_and_run.sh --verify
./script/build_and_run.sh --video --verify
./script/verify_video_variant_contract.sh
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

- Local mpv media open, including common video containers and audio-only formats such as `m4b`, with play/pause, seek, duration/progress and keyboard controls. The Video surface also accepts dropped media and SRT/VTT files; dropped media opens through the same `model.open` path as picker imports, and dropped subtitles use the same primary subtitle path as inspector/top-control imports.
- Unified shortcut registry, versioned binding migration, scope-aware conflict display, Popup-first dispatch, and grouped Global/Reader/Dictionary-Popup/Sasayaki/Video settings.
- Same-folder naturally sorted episode queue, previous/next episode controls, episode selection, configurable EOF auto-advance, and optional per-file playback-state restore. The existing preference stores position together with the selected embedded track identity, external subtitle path, automatically matched sidecar, or explicit subtitles-off state. Embedded restoration resolves stable FFmpeg index metadata before mpv's transient track ID; missing sources fall back to normal sidecar discovery without blocking media playback.
- Playback speed, volume/mute, subtitle timing adjustment, and libmpv video/audio/subtitle track selection.
- Video preferences live in their own Settings group and include auto-play next, per-file playback-state memory, Mining History retention, subtitle font/size and mask defaults, and the shared seek interval used by Video shortcuts. Shortcut browsing and editing remain exclusively in the unified Keyboard Shortcuts page under Shortcuts & Controls.
- A visible full-screen control, double-clicking the video canvas, and the unified full-screen shortcut share native macOS window full-screen behavior. Single-clicking the video canvas toggles play/pause without adding another control-bar button.
- External subtitle timing follows the same delay as mpv; selecting an external subtitle disables the embedded subtitle track to prevent duplicate rendering. When a local media file has an mpv-style same-name `.srt`/`.vtt` sidecar, Hoshi also parses that sidecar into its own transcript/lookup overlay so seeking to an arbitrary time can immediately show nearby subtitle rows instead of waiting for mpv's current-line snapshots.
- External subtitle import is resilient to large files and non-ASCII paths: Hoshi prepares subtitle cue stores and transcript rows off the main actor, mpv `sub-add` retries with a `file://` URL if raw filesystem loading fails, and mpv import failure does not prevent Hoshi's overlay/transcript path from using the parsed subtitle.
- Embedded and mpv-loaded external text subtitle tracks are mapped from mpv's `sub` track metadata, fully extracted with the bundled FFmpeg libraries when selected, and rendered through the interactive Hoshi overlay. This gives the transcript the whole selected track immediately instead of only cues encountered during playback. Image-based subtitles expose an unsupported text-list state rather than mixing stale transcript rows from another track.
- Subtitle appearance controls set Hoshi-owned text subtitle font, size, text color and lookup-highlight background color. Defaults follow asbplayer text subtitle semantics: empty font family means system default, subtitle size starts at 36 px, text is white and lookup highlighting uses the macOS selection color. Subtitle mask controls can blur or make Hoshi-owned text subtitles transparent until pointer hover. The controls live in both Video Settings and the inspector's Subtitles tab, persist in `UserConfig`, update the AppKit subtitle view live, and do not create a separate mpv subtitle renderer or rectangular blur overlay.
- Native macOS media presentation with a floating Liquid Glass control surface on macOS 26+, material fallback on older supported systems, and restrained custom chrome intended to remain visually compatible with macOS 27.
- Windowed playback fills only the unused letterbox region with a downsampled current-frame ambience, refreshed in memory at most every three seconds and masked outside the sharp video rectangle. Full screen removes this ambience and returns to pure black; the existing mpv video-only screenshot path remains isolated from window chrome, subtitles and the ambient layer.
- Video UI follows a Hoshi learning-player direction rather than a general-purpose player skin: the playback OSC is a compact IINA-like two-row Liquid Glass surface with only playback core controls, can be dragged within the video surface, and is revealed by pointer movement over the video and hidden automatically after a short idle delay, pointer exit, or app deactivation.
- Video uses one dedicated, non-restoring player `Window`. Selecting Video in the main sidebar first presents the shared media picker; a successful request creates or focuses that window, and later requests replace its media after saving state. The window hides the system toolbar, retains the existing drag strip and floating history/open affordances, and owns the complete mpv lifecycle. Closing it saves state, shuts down mpv and does not continue playback in the background.
- Speed, timing, media tracks, external subtitles, episode selection and playback options live in a right-side IINA-inspired Liquid Glass inspector with `Episodes`, `Video`, `Audio` and `Subtitles` sections. Its subtitle action opens the fixed study sidebar directly on Transcript; chapter navigation lives only in that study sidebar. Mining History and Open Video are first-class actions in the widened bottom playback bar rather than top-left overlays, leaving the native traffic lights unobstructed. The inspector overlays the trailing edge of the video surface and may cover the picture like IINA; it must not take side-by-side layout space or resize the media canvas. Inspector tabs and multi-choice controls should reuse the same glass segmented/pill language as native Settings controls instead of plain bordered controls. IINA is only a UX reference; Hoshi does not copy IINA source, assets, or app architecture.
- Player shutdown and security-scoped URL cleanup occur when the dedicated Video window closes. Reopening creates a new player session and restores per-file state; multiple simultaneous Video windows are intentionally unsupported. The singleton scene has a principal window-manager role so both the green traffic light and the shared full-screen action can enter native macOS full screen. A window-scoped chrome controller targets that exact window and hides its title/traffic lights whenever the bottom controls complete their two-second idle hide, restoring both on pointer activity. A main-window open request remains pending until `MpvRenderView` confirms that libmpv attached to its OpenGL surface, then loads and consumes the request exactly once; inspector, picker and drop replacements continue through the same already-ready player path.
- SRT/VTT parsing, overlapping cue lookup and Hoshi-owned subtitle overlay.
- Subtitle click lookup plus configurable Shift-hover lookup reuse the same point-to-character selection and shared Popup path. Native AppKit drag selection remains available for `⌘C` and contextual Copy, while lookup matches use an independent temporary highlight that lasts until the Popup stack closes. Holding Shift while moving across subtitle text continuously performs debounced lookups using the Dictionary setting `Mac Hover Delay`; nested popup lookup, pause/resume coordination and existing local word audio remain unchanged.
- Popup entries keep direct Anki add and add a shared native sentence-context selector used by Reader and Video. The selector starts at the lookup sentence, stacks contiguous preview cards, and independently adds or rolls back preceding and following sentences. Timed Video selections expand `{video-subtitle}` and `{video-audio-clip}` to the selected cue range while the screenshot remains the lookup frame; nested glossary context has no timing and therefore retains the original Video media range.
- Existing AnkiConnect mining with video file, timestamp, cue, adjacent-cue handlebars, mpvacious-style current-frame screenshot and subtitle-time-range audio capture. Local/generated media prefers direct writes into Anki's `collection.media` directory with `[sound:filename]` and `<img src="filename">` field markup; remote word audio remains on the existing AnkiConnect/base64 attachment path. Mining History is independent of this result path: it saves the current visible subtitle first and later returns the user to the shared lookup/Popup mining flow.
- Video card setup uses the normal Anki field mapping UI with explicit novel/anime note-type defaults instead of the retired heuristic field-name helper. The built-in `Japanese Video` Profile fills missing supported fields with the anime defaults; manual restore remains available. Anime defaults map `MiscInfo`/`miscInfo` to `{video-file-name} ({video-timestamp})`, matching the mpvacious-style source-plus-time context. Add to Anki checks configuration and duplicates before preparing media. `{video-screenshot}` is prepared only when mapped, while `{video-audio-clip}` uses an isolated bundled-libmpv encoder over the delayed, padded subtitle range only when mapped. If Anki's media directory is available, Video mining returns deterministic source-path-SHA filenames immediately and schedules screenshot/audio generation in the background, so media failures only log and may leave missing media on the new card. If the media directory is unavailable, Hoshi falls back to the previous AnkiConnect attachment path and a failed required mapped audio clip still stops card creation before `addNote`.
- A fixed right-side study sidebar switches between Mining History, Transcript and Chapters with a native glass segmented control and pushes the video surface instead of covering the picture. All three tabs use the same independently spaced, fully clickable Liquid Glass cards, with hover feedback and current-cue/chapter selection; the sidebar adds a bright semantic tint in light appearance so video content does not leave it gray. Mining History lists chronological subtitle captures in contiguous source sections with card jump plus direct copy/delete and confirmed clear actions; Transcript seeks by subtitle time; Chapters highlights the current marker and seeks through the existing playback engine. The configurable history limit defaults to 25, and zero disables and clears history.
- Chapter navigation, audio timing, file loop, A-B study loop, aspect-ratio override and 90-degree rotation.
- A synchronized transcript tab whose rows seek playback with subtitle-delay correction. Transcript rows are rendered through a moving time-neighborhood window so large subtitle files load near the current playback position first, then extend when the user scrolls to the window edge or playback advances into the next chunk. Large external subtitle imports and selected embedded text tracks prepare their timeline store and transcript off the main actor, and the SwiftUI list watches a lightweight transcript change token instead of comparing the full row array. Track switches clear old rows immediately; stale extraction results are ignored.
- The transcript panel owns its scrolling surface. It must not be nested inside another inspector `ScrollView`, because an unbounded parent proposal causes SwiftUI to materialize too many rows and reintroduces large-subtitle stalls.
- Opening media loads the selected file immediately and scans same-folder playlist entries asynchronously. Slow folders, cloud-backed Documents contents, or large sibling directories must not block first playback.
- On-demand libmpv frame capture and bundled-libmpv AAC/M4A audio-clip export for mapped Video media fields. Video subtitle mining checks duplicate/configuration state first, then captures only the media requested by field mappings. Direct-media mode is optimistic and does not block note creation on background media failure; fallback attachment mode still treats a missing mapped audio clip as a pre-submit failure.
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
./script/verify_video_variant_contract.sh
xcodebuild -project 'Hoshi Reader.xcodeproj' -scheme 'Hoshi Reader' -configuration Release -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
xcodebuild -project 'Hoshi Reader.xcodeproj' -scheme 'Hoshi Reader Video' -configuration Release-Video -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
./script/verify_native_release_contract.sh
```

Before release, manually test playback lifecycle, subtitle timing/click geometry, popup nesting, local word audio, and Anki success/duplicate/failure on a machine without Homebrew libmpv. Shared Reader changes require the relevant actual-EPUB matrix rather than an aggregate Reader harness.

Current real-UI subtitle smoke coverage: `/Users/wight/Documents/Dear Jane -  銀河修理員 Galactic Repairman (Official Music Video) - Dear Jane (1080p, h264, youtube).mp4` with `/Users/wight/Documents/[住野よる] また、同じ夢を見ていた.srt` imports successfully, shows both Hoshi and mpv subtitle tracks, renders subtitle text, and opens the Transcript side of the study sidebar without the previous full-file layout stall.

## Visual Contract

- Treat the video page as a Hoshi learning surface, not a general-purpose player skin.
- Hide the system window toolbar on the Video page. Keep window management discoverable with a small floating glass sidebar toggle and a transparent drag strip instead of a full top toolbar.
- Keep a compact draggable floating glass OSC over the video. The visible controls include the active Video Profile selector, previous/play-next, timeline, volume, mining, inspector and full screen. The Profile selector belongs in this bottom OSC rather than the top-right overlay. Subtitle overlay defaults must reserve enough bottom clearance for the OSC so captions are not covered before the user drags it away.
- Collect non-core controls in the right-side inspector: episode list, video track/options, audio track/timing, and subtitle track/external subtitle/timing/mask. The inspector should be a trailing overlay over the video, not a split view/sidebar that shrinks the video. Do not move those controls back into a bottom `More` popover unless a separate UI decision reverses this layout.
- Mining History, Transcript and Chapters share the deliberate exception to the inspector overlay rule: they switch inside one fixed trailing study sidebar outside the video `ZStack`, so it shrinks the video surface instead of covering the picture or subtitle lookup overlay.
- The inspector itself should read as Liquid Glass at every layer: a glass outer panel, glass section cards, Settings-style glass segmented controls for mutually exclusive choices, and glass pill action buttons. Avoid ordinary bordered buttons or system segmented controls that visually flatten the panel.
- Playback chrome may auto-hide after mouse idle, pointer exit, or app deactivation, but pointer movement inside the video must reveal it again; users may drag the compact OSC within the video bounds; single-click remains play/pause and double-click remains native fullscreen.
- Windowed letterbox space may use a restrained current-frame Liquid Glass ambience, but it must never cover the sharp video rectangle. Full screen always disables that ambience and uses pure black letterboxing.
- Subtitle text remains on a transparent overlay without a glass, material, black, or opaque background frame; lookup popups continue to use the shared Hoshi popup presentation. Subtitle appearance is limited to text font/size, and subtitle masking is limited to blur/opacity effects on the text row that must reveal on pointer hover.
- Secondary subtitles remain deferred; when implemented, they should be smaller and dimmer than primary subtitles without changing the primary subtitle lookup path.
- New custom glass elements must include a macOS 15 material fallback until the deployment target changes.
