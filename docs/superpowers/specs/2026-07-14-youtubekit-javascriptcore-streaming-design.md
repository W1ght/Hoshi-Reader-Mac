# YouTubeKit + JavaScriptCore Streaming Design

## Goal

Complete Niratan Video's YouTube streaming path with native Swift components while removing every local and remote dependency on `yt-dlp` and Deno. The Video app must resolve and play supported YouTube URLs, expose distinct qualities up to 1080p, load publisher-provided subtitles, restore library/history state, and keep screenshot/audio mining on the existing libmpv pipeline.

## Product Boundary

- The integration accepts YouTube watch, short, embed, nocookie, and `youtu.be` URLs only. Generic web-video extraction is out of scope.
- Stream extraction uses `alexeichhorn/YouTubeKit` 0.4.8 pinned to revision `65be95dbb1dbd749499e0638871568c823822276`.
- YouTubeKit must be initialized with `methods: [.local]`. Its hosted remote fallback must never be selected because that service delegates extraction to a remote `youtube-dl` implementation.
- Signature and `n`-parameter evaluation run in Apple's system JavaScriptCore through YouTubeKit. Niratan does not bundle or launch a separate JavaScript runtime.
- Only publisher-provided caption tracks are exposed. Tracks whose `kind` is `asr` are automatic captions and must be discarded before reaching the UI.
- The feature remains best-effort and unofficial. Failures must be localized without exposing signed URLs, raw page data, stack traces, or package internals.

## Dependency Integration

The Xcode project declares the upstream repository as a remote Swift Package pinned to the exact 0.4.8 revision and links the `YouTubeKit` product to the existing `Niratan` app target. Video code imports it only inside `#if HOSHI_VIDEO` files. The package's MIT license is recorded in the Video learning architecture documentation.

The Light package must remain free of Video functionality and libmpv. Verification must additionally inspect the Light app for YouTubeKit's JavaScript resource bundle. If Xcode copies that bundle into Light despite all callers compiling out, the dependency must be moved behind a Video-only local package boundary or equivalent configuration-specific linkage before completion; silently shipping Video extraction assets in Light is not accepted.

## Source Migration

The provider-independent work already developed in the `codex/remote-video-sources` worktree remains the basis for durable media identity, library/history integration, remote playback sessions, subtitle loading, quality switching, and mining. It is transplanted into this worktree by responsibility rather than by applying the complete dirty diff, so existing waveform and Reader changes are preserved and `yt-dlp`-specific process/packaging code never enters the destination.

The durable provider identifier becomes `youtube`. Test-build catalog entries written with provider identifier `ytdlp` are migrated to `youtube` when their original or canonical URL is a YouTube URL. Signed GoogleVideo URLs, request headers, caption URLs, and expiry times remain memory-only.

## Resolution Architecture

`YouTubeKitRemoteVideoResolver` conforms to the existing `RemoteVideoResolving` boundary and coordinates two narrow collaborators:

1. `YouTubeKitMediaLoader` constructs `YouTube(url:methods:[.local])`, requests streams and metadata, and converts public YouTubeKit models into Niratan-owned stream descriptors.
2. `YouTubePageMetadataLoader` fetches the canonical watch page with a bounded `URLSession`, extracts the anonymous visitor identity and watch-page duration, then requests the same Android VR Innertube player response used by the pinned YouTubeKit client. `YouTubeAndroidVRPlayerResponseParser` decodes caption tracks plus `lengthSeconds` without evaluating page JavaScript. This companion request is necessary because current watch-page `timedtext` URLs can return HTTP 200 with an empty body, while YouTubeKit does not expose caption metadata through its public API.

The resolver executes both collaborators concurrently. Metadata/caption failure is non-fatal when media streams resolve; stream failure is terminal. Cancellation propagates through structured concurrency and stale completion is discarded by the existing playback generation boundary.

## Stream Selection

Stream selection stays independent from YouTubeKit types so it can be tested without networking or an Xcode package build.

- Audio: choose the highest-bitrate audio-only stream, preferring M4A/AAC when bitrate is otherwise comparable.
- Video qualities: group video-only streams by height, discard unknown and greater-than-1080p heights, and choose the best stream in each group by codec/container suitability and bitrate.
- Progressive fallback: choose the best combined audio/video stream at or below 1080p. This is the muxed recovery path if external audio cannot attach.
- Initial playback: choose the highest distinct quality at or below 1080p and attach the selected external audio stream. If no split stream is available, use the progressive stream.
- Mining: use the best progressive stream when available; otherwise use the selected playback stream and its external audio through the existing remote mining boundary.

Each quality option carries a stable ID derived from its YouTube itag. Signed URLs expire in memory and are refreshed by resolving the durable identity again. Quality refresh preserves the selected height when still available.

## Publisher Subtitle Extraction

`YouTubeInitialPlayerResponseParser` remains the pure shared player-response decoder and watch-page duration fallback. `YouTubeAndroidVRPlayerResponseParser` feeds the valid Android VR player JSON through that shared decoder. Fixtures cover watch-page marker shapes, escaped strings, nested objects, missing captions, malformed JSON, mixed manual/automatic tracks, visitor propagation into the companion request, and replacement of the Android response's `srv3` format with WebVTT.

Each accepted caption track becomes a `RemoteVideoSubtitleOption`:

- ID: `vssId` when present, otherwise language plus stable index.
- Language: `languageCode`.
- Name: `name.simpleText`, falling back to the language code.
- URL: `baseUrl` with `fmt=vtt` appended through `URLComponents`.
- Format: WebVTT.
- Automatic: always false after filtering `kind == "asr"`.

Niratan continues to download the chosen track into its managed temporary directory, parse VTT itself, render the transparent interactive subtitle overlay, and keep mpv subtitle rendering disabled.

The Add Link sheet stores the resolved source and dismisses first. Its parent opens or focuses the dedicated player only from the sheet's `onDismiss` callback, so AppKit never orders a second key window inside SwiftUI's active sheet/window transaction.

## Errors and Recovery

The resolver maps YouTubeKit failures into Niratan domain cases for unavailable/private content, age or sign-in restrictions, region restrictions, malformed/unsupported URLs, no playable streams, cancellation, and generic resolution failure. The mapping may inspect typed `YouTubeKitError` values but never render their raw payload directly.

The existing remote playback session remains authoritative:

1. Reuse a non-expired in-memory resolution.
2. On load or authorization failure, resolve once again with the same durable identity.
3. Preserve the selected height when the refreshed manifest still contains it.
4. If external audio attachment still fails, retry once with the progressive fallback.
5. Stop with a localized audio/source error after recovery is exhausted.

Caption extraction or download failure does not stop valid playback.

## Removal Contract

Completion requires all of the following:

- No `YTDLPRemoteVideoResolver`, process runner, helper bootstrap script, helper embedding script, helper license copy, or Deno cache logic.
- No source, build setting, script, test, documentation, or app-bundle path contains a functional reference to `yt-dlp` or Deno, except migration documentation that explicitly states their removal.
- Video packaging contains no `Contents/Helpers/yt-dlp` or `Contents/Helpers/deno`.
- Light and Video build/run paths do not download helpers.
- The Video app does not connect to YouTubeKit's hosted remote extraction server.

## Verification

Implementation follows red-green-refactor cycles. Automated coverage must prove:

- URL recognition accepts only supported YouTube hosts and extracts stable IDs.
- stream selection yields distinct 1080p-or-lower choices, separate audio, and progressive fallback;
- initial-player-response parsing returns every manual language while excluding `kind=asr`;
- legacy `ytdlp` YouTube identities migrate without persisting signed URLs;
- stale playback/subtitle resolutions are discarded;
- quality switching and refresh preserve playback context;
- remote mining consumes real resolved streams;
- project/package contracts pin YouTubeKit, select `.local`, and contain no helper/runtime packaging;
- Light and Video builds succeed, Light contains no Video extraction resource leakage, and exact-app Video launch verification succeeds.

Live validation uses `https://www.youtube.com/watch?v=yrL6Qny0E5M` because it currently exposes split streams, progressive streams, multiple resolutions through 1080p, multiple publisher caption languages, and a Japanese `kind=asr` track that must be absent from Niratan. Live-service observations are recorded as time-sensitive evidence rather than deterministic unit-test expectations.

## Completion Criteria

The work is complete when the exact built Video app can open the reference URL, play audible video, switch among available qualities up to 1080p, list all publisher subtitle languages without the automatic Japanese track, restore the remote item from library/history, and use the existing screenshot/audio mining pipeline; both app variants build without any `yt-dlp` or Deno artifact, process, download, or runtime dependency.
