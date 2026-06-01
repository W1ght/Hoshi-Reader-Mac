# UIKit To AppKit Migration Plan

This document replaces the earlier "rewrite settings UI" direction. Hoshi Reader Mac is a Mac-only product, so the migration goal is not to preserve iOS compatibility. The goal is to keep reusable SwiftUI, model, and service code while steadily replacing UIKit/Catalyst platform dependencies with Mac-specific implementations.

## Current Reality

Hoshi Reader Mac is currently implemented as an iOS app target running as Mac Catalyst:

- The Xcode project has an iOS application target with `SUPPORTS_MACCATALYST = YES`.
- Even though the current target is technically Catalyst, the repository no longer needs to optimize for iPhone/iPad runtime behavior.
- SwiftUI feature screens should remain SwiftUI where they behave well on Mac.
- Platform edges are UIKit-heavy: `UIApplication`, `UIWindowScene`, `UIViewRepresentable`, `UIViewControllerRepresentable`, `UIKey`, `UIPress`, `UIColor`, `UIImage`, `UIFont`, `AVAudioSession`, and Catalyst-only window chrome hooks.
- Reader, popup, and dictionary content are WebKit-heavy and high risk; they should not be the first native macOS rewrite.

## Direction

Prefer a Mac-only layered migration:

1. Keep SwiftUI feature screens unless they have a real Mac behavior gap.
2. Remove iOS-only branches that no longer serve the Mac product.
3. Isolate UIKit/Catalyst dependencies by capability, but do not design them as cross-platform abstractions.
4. Replace each isolated capability with a Mac-specific implementation.
5. Add a native macOS target only after enough UIKit/Catalyst coupling has been removed.

Do not rewrite a screen just because it is part of the Mac app. Rewrite only when the capability gap is truly Mac-specific: menus, responder chain, windows, panels, drag/drop, keyboard event capture, or `NSView`/`WKWebView` lifecycle.

## Phase 0: Platform Inventory

Purpose: know exactly where UIKit is still acting as Mac implementation glue.

Current inventory lives in `docs/MAC_NATIVE_MIGRATION_INVENTORY.md`.

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
- Each dependency is classified as either remove, keep-for-Catalyst-now, or replace-with-AppKit-later.

## Phase 1: Remove iOS-Only Branches

Purpose: reduce conditional logic and make the current Catalyst app explicitly Mac-only before introducing AppKit.

Good first targets:

- Settings paths that still branch for iOS AnkiMobile behavior while Mac always uses AnkiConnect.
- Mac-only UI decisions that currently sit behind generic `AppPlatform.usesDesktopLayout` checks.
- Documentation and naming that implies iOS parity is required.

Rules:

- Do not change persistence paths or user data.
- Do not remove code that is still needed by the current Catalyst runtime.
- Keep behavior identical for Mac users.

Exit criteria:

- Mac-only behavior is easier to read and no longer carries iOS alternatives in the first migrated areas.
- Existing Catalyst app behavior is unchanged.

## Phase 2: Mac Capability Boundaries

Purpose: isolate UIKit/Catalyst dependencies by Mac capability before replacing them.

Candidate boundaries:

- Open external URL / reveal file.
- Current window and titlebar chrome.
- Keyboard event capture and command routing.
- File import/export panels.
- Color/image/font persistence and conversion.
- Audio session / now playing / idle timer behavior.

Rules:

- Keep boundaries tiny and concrete.
- Prefer direct Mac-only names over platform-neutral abstractions.
- Do not introduce an iOS implementation branch.
- Existing SwiftUI screens should call these boundaries only when they actually need platform behavior.

Exit criteria:

- New code touching these capabilities has one obvious Mac-owned entry point.
- Existing Catalyst app behavior is unchanged.

## Phase 3: Low-Risk AppKit Bridges

Purpose: introduce AppKit only where UIKit/Catalyst has a clear Mac gap.

Good first bridges:

- Keyboard shortcut capture: replace the UIKit `UIViewRepresentable` key capture with an `NSViewRepresentable` implementation when a native macOS target exists.
- Open/reveal behavior: use `NSWorkspace` for URL/file operations once the code is compiled in a native macOS target.
- Window chrome: move titlebar and toolbar operations toward `NSWindow` once the Catalyst-only titlebar hooks are no longer the only option.
- File panels: where SwiftUI `fileImporter` is not enough, use `NSOpenPanel`.

Avoid first:

- Reader pagination.
- Popup coordinate math.
- Full native dictionary rendering.
- Sasayaki playback session rewrites.

Exit criteria:

- At least one adapter has both Catalyst and AppKit-shaped implementations.
- No user-visible regression in the existing Catalyst app.

## Phase 4: Native macOS Target Spike

Purpose: prove that shared SwiftUI and services compile outside Catalyst.

Scope:

- Add a temporary native macOS app target, not a release target.
- Include shared `Core`, `Models`, and low-risk SwiftUI settings screens.
- Exclude Reader/WebView wrappers, popup wrappers, ShareExtension, and iOS-only lifecycle until adapters exist.
- Use compile errors to drive adapter extraction.

Exit criteria:

- A macOS target can compile a minimal shell with shared config and simple settings.
- Catalyst release target remains unaffected until native macOS becomes the release target.

## Phase 5: Feature Migration Order

Recommended order:

1. Remove iOS-only AnkiMobile branches from Mac-facing configuration.
2. Keyboard shortcut capture and command routing.
3. File import/export and Finder reveal/open behavior.
4. App lifecycle/window/open URL helpers.
5. Bookshelf shell interactions such as context menu, drag import, and manual sync refresh.
6. Anki/audio/Sasayaki management screens only where they need native panels or responder behavior.
7. Dictionary shell around shared WebKit entry rendering.
8. Popup chrome and coordinate bridges.
9. Reader chrome last; Reader content and pagination remain WebKit-backed until regression infrastructure is strong.

## Non-Goals For Early Phases

- Do not duplicate SwiftUI screens just to make them look more Mac-like.
- Do not keep iOS compatibility branches merely for theoretical reuse.
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
