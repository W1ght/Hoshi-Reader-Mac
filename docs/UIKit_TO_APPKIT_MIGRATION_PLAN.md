# UIKit To AppKit Migration Plan

This document replaces the earlier "rewrite settings UI" direction. The migration goal is not to duplicate SwiftUI screens. The goal is to make the current shared SwiftUI and service code run behind explicit platform boundaries, then introduce a native macOS target when the boundary is small enough.

## Current Reality

Hoshi Reader Mac is currently an iOS app target running as Mac Catalyst:

- The Xcode project has an iOS application target with `SUPPORTS_MACCATALYST = YES`.
- Shared app UI is mostly SwiftUI and should remain shared where it behaves well.
- Platform edges are UIKit-heavy: `UIApplication`, `UIWindowScene`, `UIViewRepresentable`, `UIViewControllerRepresentable`, `UIKey`, `UIPress`, `UIColor`, `UIImage`, `UIFont`, `AVAudioSession`, and Catalyst-only window chrome hooks.
- Reader, popup, and dictionary content are WebKit-heavy and high risk; they should not be the first native macOS rewrite.

## Direction

Prefer a layered migration:

1. Keep SwiftUI feature screens shared.
2. Extract UIKit/Catalyst dependencies into narrow platform adapters.
3. Add AppKit implementations for those adapters.
4. Only then add a native macOS target that reuses shared SwiftUI, models, services, and WebKit content.

Do not rewrite a screen just because it is part of the Mac app. Rewrite only when the capability gap is truly AppKit-specific: menus, responder chain, windows, panels, drag/drop, keyboard event capture, or `NSView`/`WKWebView` lifecycle.

## Phase 0: Platform Inventory

Purpose: know exactly where UIKit is acting as platform glue.

Inventory buckets:

- App lifecycle and windowing: `App/HoshiReader.swift`, `ReaderWindow`, window chrome sync helpers.
- Safe area and application state: `UIApplication` extensions and top/bottom safe area helpers.
- File and URL actions: `fileImporter`, `UIApplication.shared.open`, Google auth presentation anchor.
- Input: `UIKey`, `UIPress`, controller notifications, shortcut capture views.
- WebKit wrappers: `UIViewRepresentable` reader, scroll reader, popup, dictionary search field.
- Images/colors/fonts: `UIImage`, `UIColor`, `UIFont`, cover thumbnails, artwork, persisted colors.
- Audio/session behavior: `AVAudioSession`, now playing info, idle timer/background tasks.

Exit criteria:

- A short inventory exists for every UIKit platform dependency.
- Each dependency has a proposed shared protocol or platform-specific wrapper.

## Phase 1: Platform Adapter Layer

Purpose: make Mac Catalyst behavior explicit without changing user-facing UI.

Candidate adapters:

- `PlatformApplication`: open URL, active/resign notifications, idle timer, background task no-op/implementation.
- `PlatformWindow`: current window access, titlebar/toolbar chrome, fullscreen/focus mode hooks.
- `PlatformColorImage`: color archive/unarchive, image loading, symbol image generation.
- `PlatformKeyboard`: key event model independent of `UIKey`.
- `PlatformFilePanel`: import/export panel boundary, initially backed by SwiftUI `fileImporter`.
- `PlatformAudioSession`: word audio and Sasayaki session coordination without leaking `AVAudioSession` everywhere.

Rules:

- Adapters should be tiny and capability-based.
- Existing SwiftUI views call shared abstractions, not UIKit/AppKit directly.
- Catalyst implementations can remain UIKit-backed at first.

Exit criteria:

- New code touching platform behavior goes through adapters.
- Existing behavior is unchanged on Mac Catalyst.

## Phase 2: Low-Risk AppKit Bridges

Purpose: introduce AppKit only where SwiftUI/UIKit has a clear Mac gap.

Good first bridges:

- Keyboard shortcut capture: replace the UIKit `UIViewRepresentable` key capture with an `NSViewRepresentable` implementation for native macOS target readiness.
- Open/reveal behavior: use `NSWorkspace` behind `PlatformApplication` for opening URLs/files.
- Window chrome: move titlebar and toolbar operations behind `PlatformWindow`; AppKit implementation can use `NSWindow` directly later.
- File panels: where SwiftUI `fileImporter` is not enough, use `NSOpenPanel` behind `PlatformFilePanel`.

Avoid first:

- Reader pagination.
- Popup coordinate math.
- Full native dictionary rendering.
- Sasayaki playback session rewrites.

Exit criteria:

- At least one adapter has both Catalyst and AppKit-shaped implementations.
- No user-visible regression in the existing Catalyst app.

## Phase 3: Native macOS Target Spike

Purpose: prove that shared SwiftUI and services compile outside Catalyst.

Scope:

- Add a temporary native macOS app target, not a release target.
- Include shared `Core`, `Models`, and low-risk SwiftUI settings screens.
- Exclude Reader/WebView wrappers, popup wrappers, ShareExtension, and iOS-only lifecycle until adapters exist.
- Use compile errors to drive adapter extraction.

Exit criteria:

- A macOS target can compile a minimal shell with shared config and simple settings.
- Catalyst release target remains unaffected.

## Phase 4: Feature Migration Order

Recommended order:

1. App lifecycle/window/open URL helpers.
2. Keyboard shortcut capture and command routing.
3. File import/export and Finder reveal/open behavior.
4. Bookshelf shell interactions such as context menu, drag import, and manual sync refresh.
5. Anki/audio/Sasayaki management screens only where they need native panels or responder behavior.
6. Dictionary shell around shared WebKit entry rendering.
7. Popup chrome and coordinate bridges.
8. Reader chrome last; Reader content and pagination remain WebKit-backed until regression infrastructure is strong.

## Non-Goals For Early Phases

- Do not duplicate SwiftUI screens just to make them look more Mac-like.
- Do not move persistence paths.
- Do not change Google Drive sync semantics.
- Do not mix dictionary word audio, LocalFileServer audio, and Sasayaki audiobook audio.
- Do not rewrite Reader pagination, CSS, or JS as part of AppKit migration.

## Validation

Every phase must keep the current Catalyst app buildable:

```bash
xcodebuild -quiet \
  -project 'Hoshi Reader.xcodeproj' \
  -scheme 'Hoshi Reader' \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

If a native macOS target is added later, it must have its own explicit compile command and must not replace Catalyst release verification until it is the release target.
