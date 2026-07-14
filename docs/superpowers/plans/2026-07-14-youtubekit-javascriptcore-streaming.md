# YouTubeKit + JavaScriptCore Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Niratan Video's bundled `yt-dlp` and Deno extraction path with pinned YouTubeKit local extraction backed by system JavaScriptCore while preserving remote playback, publisher subtitles, quality selection, library/history, and mining.

**Architecture:** Transplant only the provider-independent remote-media work from the existing `codex/remote-video-sources` worktree, then implement a YouTube-only resolver. YouTubeKit resolves media streams locally; Niratan parses `ytInitialPlayerResponse` for manual caption tracks and duration; existing libmpv, subtitle overlay, history, and mining boundaries remain authoritative.

**Tech Stack:** Swift 6, SwiftUI/Observation, Objective-C++ libmpv bridge, JavaScriptCore, YouTubeKit 0.4.8 at revision `65be95dbb1dbd749499e0638871568c823822276`, macOS 26, Xcode Swift Package integration.

## Global Constraints

- Native macOS is the only target; do not add another app or platform target.
- Preserve every pre-existing waveform and Reader change in this detached worktree.
- Video-only implementation remains under `HOSHI_VIDEO`; Light must remain free of Video extraction assets.
- YouTubeKit must use `methods: [.local]`; never use its hosted remote fallback.
- Accept YouTube URLs only. Generic remote-site extraction is removed with `yt-dlp`.
- Exclude every caption track whose `kind` is `asr`.
- Persist only durable YouTube identity and metadata, never signed media/caption URLs or request headers.
- Do not commit, push, tag, or release without explicit user authorization.

---

### Task 1: Provider-Independent Remote Media Foundation

**Files:**
- Create: `Features/Video/Remote/RemoteVideoSource.swift`
- Create: `Features/Video/Remote/RemoteVideoResolver.swift`
- Create: `Features/Video/Remote/RemotePlaybackSession.swift`
- Create: `Features/Video/Remote/RemoteSubtitleLoader.swift`
- Modify: `Features/Video/VideoLibraryStore.swift`
- Modify: `Features/Video/VideoPlaybackHistoryStore.swift`
- Modify: `Features/Video/VideoLibraryViewModel.swift`
- Test: `script/test_video_remote_identity.swift`
- Test: `script/test_video_remote_playback_session.swift`

**Interfaces:**
- Produces `VideoMediaIdentity`, `RemoteVideoIdentity`, `RemoteVideoStream`, `RemoteVideoQualityOption`, `ResolvedRemoteVideoSource`, `RemoteVideoResolving`, and `RemotePlaybackSession`.
- Keeps URL overloads in `VideoPlaybackHistoryStore` for existing local callers.

- [ ] **Step 1: Write failing durable-identity tests**

Create `script/test_video_remote_identity.swift` with assertions for this public shape:

```swift
let identity = VideoMediaIdentity.remote(providerID: "youtube", remoteID: "yrL6Qny0E5M")
expect(identity.persistenceKey, "remote://youtube/yrL6Qny0E5M", "stable key")
expect(identity.localURL, nil, "remote media has no file URL")

let legacyJSON = #"{"providerID":"ytdlp","remoteID":"yrL6Qny0E5M","originalURL":"https:\/\/www.youtube.com\/watch?v=yrL6Qny0E5M","title":"Reference"}"#
let migrated = try JSONDecoder().decode(RemoteVideoIdentity.self, from: Data(legacyJSON.utf8))
expect(migrated.providerID, "youtube", "legacy test catalog provider migration")
```

Encode a `RemoteVideoIdentity` and require that the JSON contains neither `googlevideo.com` nor `httpHeaders`.

- [ ] **Step 2: Verify RED**

Run:

```bash
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Models/Subtitle.swift Features/Video/Remote/RemoteVideoSource.swift script/test_video_remote_identity.swift -o /tmp/hoshi-test-video-remote-identity
```

Expected: compilation fails because `Features/Video/Remote/RemoteVideoSource.swift` does not exist.

- [ ] **Step 3: Transplant and adapt the remote foundation**

Bring the four provider-independent files from `/Users/wight/.config/superpowers/worktrees/Hoshi-Reader/remote-video-sources` into this worktree using `apply_patch`. Adapt the provider declaration to:

```swift
nonisolated enum RemoteVideoProvider: String, Hashable, Sendable {
    case youtube

    var id: String { rawValue }
    var displayName: String { "YouTube" }
}
```

In `RemoteVideoIdentity.init(from:)`, normalize legacy `providerID == "ytdlp"` to `youtube` only when `originalURL` or `canonicalURL` passes `YouTubeURLParser.isYouTubeURL`. Keep unknown provider strings unchanged.

Three-way merge the store/history/view-model changes against `3ba5a695` so current waveform edits remain intact. Remote items must bypass file-existence, security-scope, byte-size, local-thumbnail, and Reveal in Finder paths.

- [ ] **Step 4: Write and run session tests**

Transplant `script/test_video_remote_playback_session.swift`, replace fixture provider values with `youtube`, and cover:

```text
fresh source -> no resolver call
expired source -> one forced refresh
external audio failure -> one refresh, then one progressive fallback
stale generation -> ignored
quality refresh -> same height when still available
```

Compile the identity and session tests with their exact production sources and require both executables to exit 0.

- [ ] **Step 5: Run local regressions**

Run:

```bash
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Features/Video/Playback/PlaybackEngine.swift Features/Video/Remote/RemoteVideoSource.swift Features/Video/VideoPlaybackHistoryStore.swift script/test_video_playback_history.swift -o /tmp/hoshi-test-video-playback-history && /tmp/hoshi-test-video-playback-history
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Models/Subtitle.swift Features/Video/Subtitles/SubtitleCueStore.swift Features/Video/Playback/PlaybackEngine.swift Features/Video/Remote/RemoteVideoSource.swift Features/Video/VideoPlaylist.swift Features/Video/VideoInspectorState.swift Features/Video/VideoPlaybackHistoryStore.swift Features/Video/VideoPlayerViewModel.swift script/test_video_playback_model.swift -o /tmp/hoshi-test-video-playback-model && /tmp/hoshi-test-video-playback-model
swift script/test_video_library_contract.swift
git diff --check
```

---

### Task 2: Pure YouTube URL, Stream Selection, and Caption Parsing

**Files:**
- Create: `Features/Video/Remote/YouTubeURLParser.swift`
- Create: `Features/Video/Remote/YouTubeMediaModels.swift`
- Create: `Features/Video/Remote/YouTubeStreamSelector.swift`
- Create: `Features/Video/Remote/YouTubeInitialPlayerResponseParser.swift`
- Test: `script/test_video_youtube_stream_selector.swift`
- Test: `script/test_video_youtube_caption_parser.swift`

**Interfaces:**
- Produces `YouTubeURLParser.videoID(from:)`, `YouTubeMediaStreamDescriptor`, `YouTubeResolvedPageMetadata`, `YouTubeStreamSelector.select(from:)`, and `YouTubeInitialPlayerResponseParser.parse(html:)`.
- These files import Foundation only so their tests do not require the Swift Package.

- [ ] **Step 1: Write failing URL and stream-selection tests**

Cover watch, `youtu.be`, shorts, embed, and nocookie URLs, and reject `example.com`, `youtube.com.evil.test`, missing IDs, and non-HTTP schemes.

Build stream fixtures containing progressive 360p, video-only 144/360/720/1080/1440, M4A audio, and WebM audio. Require:

```swift
expect(selection.qualityOptions.map(\.height), [1080, 720, 360, 144], "distinct capped qualities")
expect(selection.audioStream?.formatID, "140", "highest suitable audio")
expect(selection.muxedFallbackStream?.height, 360, "progressive recovery")
expect(selection.qualityOptions.first?.playbackStream.height, 1080, "initial quality")
```

- [ ] **Step 2: Verify stream-selection RED**

Compile the test with the three planned source files. Expected: missing-file or missing-symbol failure.

- [ ] **Step 3: Implement the pure selectors**

Use this descriptor boundary:

```swift
nonisolated struct YouTubeMediaStreamDescriptor: Equatable, Sendable {
    let url: URL
    let formatID: String
    let height: Int?
    let hasVideo: Bool
    let hasAudio: Bool
    let bitrate: Int
    let fileExtension: String
    let prefersNativeCodec: Bool
}
```

Filter video heights to `1...1080`, group by height, choose native-preferred then higher bitrate, prefer M4A audio then higher bitrate, and retain the best progressive stream as fallback.

- [ ] **Step 4: Write failing caption parser fixtures**

Fixture 1 assigns `var ytInitialPlayerResponse = {...};` and contains Japanese manual, Japanese `kind: "asr"`, English manual, and nested braces inside a quoted caption name. Fixture 2 embeds `"ytInitialPlayerResponse": {...}`. Require manual languages `ja` and `en`, exclusion of ASR, `fmt=vtt` on each URL, and decoded `lengthSeconds`.

Malformed, missing-marker, and missing-caption fixtures must return empty captions without crashing; malformed JSON returns a typed parser error.

- [ ] **Step 5: Implement and verify caption parsing GREEN**

Implement quote/escape-aware balanced-brace extraction and decode only:

```swift
videoDetails.lengthSeconds
captions.playerCaptionsTracklistRenderer.captionTracks[]
```

Map `baseUrl`, `vssId`, `languageCode`, `name.simpleText`, and `kind`. Append or replace `fmt=vtt` with `URLComponents`. Run both focused tests and `git diff --check`.

---

### Task 3: Pin and Integrate YouTubeKit Local Extraction

**Files:**
- Modify: `Niratan.xcodeproj/project.pbxproj`
- Create: `Features/Video/Remote/YouTubeKitMediaLoader.swift`
- Create: `Features/Video/Remote/YouTubePageMetadataLoader.swift`
- Create: `Features/Video/Remote/YouTubeKitRemoteVideoResolver.swift`
- Modify: `Features/Video/Remote/RemoteVideoResolver.swift`
- Test: `script/test_video_youtubekit_contract.swift`
- Test: `script/test_video_youtube_remote_resolver.swift`

**Interfaces:**
- `YouTubeMediaLoading.load(url:) async throws -> YouTubeLoadedMedia`
- `YouTubePageMetadataLoading.load(videoID:) async throws -> YouTubeResolvedPageMetadata`
- Default resolver dependencies use `YouTubeKitMediaLoader` and `YouTubePageMetadataLoader`; tests inject closures.

- [ ] **Step 1: Write failing package and local-method contract**

Require the project file to contain the repository URL, exact revision, `YouTubeKit` product dependency, and a Video source containing exactly:

```swift
let youtube = YouTube(url: url, methods: [.local])
```

Reject `.remote`, `remote-production.youtubekit.dev`, `Process(`, `YTDLP`, and helper paths throughout production sources and build scripts.

- [ ] **Step 2: Verify contract RED**

Run `swift script/test_video_youtubekit_contract.swift`; expected failure is the absent package reference and loader.

- [ ] **Step 3: Add the pinned Swift Package**

Add `XCRemoteSwiftPackageReference` with revision `65be95dbb1dbd749499e0638871568c823822276`, add the `YouTubeKit` product to the target's package products and frameworks phase, and retain the existing EPUBKit/CHoshiDicts references.

- [ ] **Step 4: Implement the loader and resolver through injected boundaries**

Use `@preconcurrency import YouTubeKit`. Convert each public `Stream` to the Niratan descriptor using `itag.itag`, `videoResolution`, track flags, bitrate, file extension, and native-playability. Load streams and metadata once from the same `YouTube` object.

Run media and page metadata loading concurrently. A page/caption error yields empty captions and nil duration; a media error maps typed `YouTubeKitError` into `RemoteVideoResolverError`. Set `expiresAt` conservatively to five hours after resolution and use canonical URL `https://www.youtube.com/watch?v=<id>`.

- [ ] **Step 5: Verify resolver RED/GREEN and live extraction**

The injected resolver test must first fail before implementation, then pass for quality, metadata, caption preference, unavailable-content mapping, and cancellation. Build the Video configuration to prove the package import. Run a time-sensitive live probe against `yrL6Qny0E5M` and record stream counts/qualities without turning them into deterministic fixtures.

---

### Task 4: Remote Playback, Quality, Subtitle, and Mining Integration

**Files:**
- Modify: `Features/Video/Playback/HSMpvClient.h`
- Modify: `Features/Video/Playback/HSMpvClient.mm`
- Modify: `Features/Video/Playback/MpvPlayerEngine.swift`
- Modify: `Features/Video/Playback/PlaybackEngine.swift`
- Modify: `Features/Video/Playback/VideoAudioClipExporter.swift`
- Modify: `Features/Video/VideoPlayerViewModel.swift`
- Modify: `Features/Video/VideoPlayerScreen.swift`
- Modify: `Features/Video/VideoInspectorView.swift`
- Modify: `Features/Video/VideoMiningCoordinator.swift`
- Modify: `Features/Video/VideoWindowCoordinator.swift`
- Test: `script/test_video_remote_playback_session.swift`
- Test: `script/test_video_remote_subtitle_loader.swift`
- Test: `script/test_video_playback_model.swift`
- Test: `script/test_video_remote_source_contract.swift`

**Interfaces:**
- Playback loads a primary video URL plus optional external-audio URL and per-component headers.
- View model owns one remote session, one subtitle loader, and generation tokens.
- Mining receives actual resolved media URLs, never a synthetic remote file URL.

- [ ] **Step 1: Add/merge failing integration assertions**

Three-way merge provider-independent tests from `codex/remote-video-sources` against current waveform tests. Require component-specific headers, external-audio attachment state, one refresh, muxed fallback, stale subtitle discard, playback-time preservation across quality changes, and real remote mining URLs.

- [ ] **Step 2: Verify RED**

Run the focused remote session/subtitle tests and the existing playback model command. Expected failures must point to missing component-aware playback and remote view-model APIs.

- [ ] **Step 3: Merge the playback boundary**

Bring the existing remote source worktree's component-aware libmpv bridge changes into current files using a three-way merge against `3ba5a695`. Preserve waveform protocol methods and Objective-C++ waveform generator wiring. Do not bring process execution or helper code.

- [ ] **Step 4: Merge view-model/UI/mining behavior**

Preserve the existing action/state/shortcut pipeline. Add link/open-link loading, remote library/history identity, YouTube-only quality controls, publisher subtitle loading, and remote mining context. Ensure waveform alignment remains local-file-only unless its existing analysis boundary explicitly supports the resolved stream; do not pass a synthetic URL into waveform generation.

- [ ] **Step 5: Verify focused and regression tests GREEN**

Run:

```bash
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Models/Subtitle.swift Features/Video/Playback/PlaybackEngine.swift Features/Video/Remote/RemoteVideoSource.swift Features/Video/Remote/RemoteVideoResolver.swift Features/Video/Remote/RemotePlaybackSession.swift script/test_video_remote_playback_session.swift -o /tmp/hoshi-test-video-remote-playback-session && /tmp/hoshi-test-video-remote-playback-session
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Models/Subtitle.swift Features/Video/Remote/RemoteVideoSource.swift Features/Video/Remote/RemoteSubtitleLoader.swift script/test_video_remote_subtitle_loader.swift -o /tmp/hoshi-test-video-remote-subtitle-loader && /tmp/hoshi-test-video-remote-subtitle-loader
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Models/Subtitle.swift Features/Video/Subtitles/SubtitleCueStore.swift Features/Video/Playback/PlaybackEngine.swift Features/Video/Remote/RemoteVideoSource.swift Features/Video/VideoPlaylist.swift Features/Video/VideoInspectorState.swift Features/Video/VideoPlaybackHistoryStore.swift Features/Video/VideoPlayerViewModel.swift script/test_video_playback_model.swift -o /tmp/hoshi-test-video-playback-model && /tmp/hoshi-test-video-playback-model
swift script/test_video_remote_source_contract.swift
swift script/test_video_library_contract.swift
swift script/test_video_waveform_models.swift
swift script/test_video_waveform_alignment_contract.swift
git diff --check
rg -n 'URL\(fileURLWithPath:.*remote|remote.*URL\(fileURLWithPath:' Features/Video
```

The final `rg` command must return no matches.

---

### Task 5: Library Entry Points, Localization, and Documentation

**Files:**
- Modify: `Features/Video/VideoLibraryView.swift`
- Modify: `NativeMac/NativeMacDetailView.swift`
- Modify: `NativeMac/NativeMacRootView.swift`
- Modify: `NativeMac/VideoWindowPresenter.swift`
- Modify: `Models/Anki.swift`
- Modify: `Localizable.xcstrings`
- Modify: `docs/TODO.md`
- Modify: `docs/VIDEO_LEARNING_ARCHITECTURE.md`
- Modify: `docs/CHANGELOG.md`
- Test: `script/test_video_library_view_model.swift`
- Test: `script/test_video_library_contract.swift`
- Test: `script/test_video_youtubekit_contract.swift`

- [ ] **Step 1: Add failing user-flow contracts**

Require Add Link/Open Link entry points, cancellable resolving state, YouTube-only quality visibility, no Reveal in Finder for remote rows, and Chinese/English localized strings for unsupported, unavailable, sign-in/age, region, stream, audio, and subtitle errors.

- [ ] **Step 2: Merge the provider-independent UI and persistence changes**

Three-way merge against the base commit, preserving current module-switching and waveform UI changes. Replace generic `Remote Video` and helper/runtime copy with YouTube/JavaScriptCore-appropriate localized text.

- [ ] **Step 3: Update source-of-truth documentation**

Document the pinned MIT dependency, local-only extraction, manual-caption rule, no helper/runtime packaging, remaining unofficial-API risk, and Light/Video verification entry points. Changelog text remains user-visible and does not mention internal build mechanics.

- [ ] **Step 4: Verify library/localization contracts**

Run focused library tests, parse `Localizable.xcstrings` as JSON, run `git diff --check`, and scan for raw visible English strings introduced by this task.

---

### Task 6: Removal and End-to-End Verification

**Files:**
- Modify: `script/verify_video_variant_contract.sh`
- Modify: `script/package_mac.sh` only if package integration changes its existing behavior
- Modify: `script/build_and_run_native.sh` only if package resolution needs an explicit step
- Delete if present: `Features/Video/Remote/YTDLPRemoteVideoResolver.swift`
- Delete if present: `script/bootstrap_ytdlp.sh`
- Delete if present: `script/bootstrap_deno.sh`
- Delete if present: `script/embed_video_helpers.sh`

- [ ] **Step 1: Strengthen the removal contract**

Assert both built variants reject `Contents/Helpers/yt-dlp` and `Contents/Helpers/deno`; source/build scripts contain no functional `yt-dlp`, Deno, `Process`, or remote YouTubeKit fallback reference; Video resolves the pinned package; Light does not contain `YouTubeKit_YouTubeKit.bundle`, `yt_ejs_helper.js`, `meriyah.umd.js`, or `astring.umd.js`.

- [ ] **Step 2: Run all focused tests**

Run the remote identity, URL, selector, caption parser, resolver, playback session, subtitle loader, library/view-model, playback/history, mining, waveform, fullscreen, ambient, and Video variant contracts. Require zero failures and clean `git diff --check`.

- [ ] **Step 3: Build and verify Light**

Run:

```bash
./script/build_and_run.sh --instance youtubekit-light --verify
```

Confirm bundle id and executable path, then inspect the exact app for libmpv, YouTubeKit resources, yt-dlp, and Deno leakage.

- [ ] **Step 4: Build and verify Video**

Run:

```bash
./script/build_and_run.sh --video --instance youtubekit-video --verify
```

Confirm bundle id, executable path, JavaScriptCore linkage, libmpv linkage, absence of helper binaries, and successful launch.

- [ ] **Step 5: Manual live-service verification**

Open `https://www.youtube.com/watch?v=yrL6Qny0E5M` in the exact Video app. Verify audible playback, 1080p-or-lower quality switching with time/state preservation, all manual caption languages, absence of Japanese auto-generated caption, library/history reopen, screenshot mining, and audio mining. Record any unavailable Anki/account/live-service scenario explicitly.

- [ ] **Step 6: Final scope audit**

Review `git status`, diff only task-owned changes, verify current waveform/Reader modifications remain present, and report that the worktree is detached and uncommitted unless the user separately authorizes a branch or commit.
