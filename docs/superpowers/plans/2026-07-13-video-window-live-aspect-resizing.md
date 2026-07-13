# Video Window Live Aspect Resizing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the effective video aspect ratio during every user-driven Video window resize without reintroducing persistent AppKit aspect constraints or destabilizing native full-screen transitions.

**Architecture:** `VideoWindowAspectLayout` performs pure frame/content geometry. The existing window-scoped `VideoWindowChromeController` owns the effective layout policy and native full-screen state, while `VideoWindowPresenter` remains the sole `NSWindowDelegate` and forwards proposed user resize sizes to that controller. The delegate correction is synchronous, installs no nonzero `aspectRatio`/`contentAspectRatio`, and performs no follow-up `setFrame`.

**Tech Stack:** Swift 6, AppKit `NSWindowDelegate`, SwiftUI Observation, existing standalone Swift contract tests, Xcode Light/Video schemes.

## Global Constraints

- Native macOS 26.0+ is the only supported platform.
- The Light build must not compile, link, copy, or runtime-discover Video/libmpv code.
- `VideoWindowChromeController` remains the single native full-screen state source.
- The live-resize path must pass AppKit proposals through unchanged while entering, in, or exiting native full screen.
- Never install a nonzero persistent `NSWindow.aspectRatio` or `NSWindow.contentAspectRatio`.
- Never call `setFrame` from `windowWillResize(_:to:)` or the live-resize resolver.
- Preserve the existing standard title bar, single non-restoring Video window, stable mpv render view, study-sidebar push layout, and inspector overlay layout.
- Do not commit, push, tag, or release without explicit user approval.

---

### Task 1: Add pure live-resize geometry

**Files:**
- Modify: `script/test_video_window_aspect_layout.swift:19-103`
- Modify: `Features/Video/VideoWindowChromeController.swift:5-111`

**Interfaces:**
- Consumes: existing `VideoWindowAspectLayout.videoAspectRatio`, current/proposed frame sizes, title-bar decoration size, effective video ratio, visible study-sidebar width, and `NSWindow.minSize`.
- Produces: `VideoWindowAspectLayout.constrainedFrameSize(currentFrameSize:proposedFrameSize:frameDecorationSize:videoAspectRatio:sidebarWidth:minimumFrameSize:) -> CGSize`.

- [ ] **Step 1: Write failing horizontal, vertical, corner, sidebar, minimum, and invalid-input tests**

Append these cases before the final print in `script/test_video_window_aspect_layout.swift`:

```swift
        let currentFrameSize = CGSize(width: 1280, height: 748)
        let titlebarDecoration = CGSize(width: 0, height: 28)
        let minimumFrameSize = CGSize(width: 900, height: 620)

        let horizontalResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: currentFrameSize,
            proposedFrameSize: CGSize(width: 1600, height: 748),
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 0,
            minimumFrameSize: minimumFrameSize
        )
        expect(approximatelyEqual(horizontalResize.width, 1600), "horizontal resizing should preserve the proposed width")
        expect(approximatelyEqual(horizontalResize.height, 928), "horizontal resizing should derive content height before restoring title-bar height")

        let verticalResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: currentFrameSize,
            proposedFrameSize: CGSize(width: 1280, height: 928),
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 0,
            minimumFrameSize: minimumFrameSize
        )
        expect(approximatelyEqual(verticalResize.width, 1600), "vertical resizing should derive width from the proposed content height")
        expect(approximatelyEqual(verticalResize.height, 928), "vertical resizing should preserve the proposed frame height")

        let cornerResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: currentFrameSize,
            proposedFrameSize: CGSize(width: 1480, height: 808),
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 0,
            minimumFrameSize: minimumFrameSize
        )
        expect(approximatelyEqual(cornerResize.width, 1480), "corner resizing should honor the dominant normalized width delta")
        expect(approximatelyEqual(cornerResize.height, 860.5), "corner resizing should derive the paired dimension from the dominant delta")

        let sidebarResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: CGSize(width: 1620, height: 748),
            proposedFrameSize: CGSize(width: 1940, height: 748),
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 340,
            minimumFrameSize: minimumFrameSize
        )
        expect(approximatelyEqual(sidebarResize.width, 1940), "study-sidebar resizing should preserve the proposed total width")
        expect(approximatelyEqual(sidebarResize.height, 928), "study-sidebar resizing should keep only the video surface aspect-correct")

        let minimumResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: currentFrameSize,
            proposedFrameSize: CGSize(width: 800, height: 500),
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 0,
            minimumFrameSize: minimumFrameSize
        )
        expect(approximatelyEqual(minimumResize.width, 592 * 16.0 / 9.0), "minimum height should grow width along the video ratio")
        expect(approximatelyEqual(minimumResize.height, 620), "live resizing should respect the minimum frame height")

        let invalidResizeProposal = CGSize(width: 1400, height: 900)
        let invalidResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: currentFrameSize,
            proposedFrameSize: invalidResizeProposal,
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: .nan,
            sidebarWidth: 0,
            minimumFrameSize: minimumFrameSize
        )
        expect(invalidResize == invalidResizeProposal, "invalid layout inputs should leave AppKit's proposal unchanged")
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-video-aspect-clang \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-video-aspect-swift \
xcrun swiftc -D HOSHI_VIDEO -parse-as-library \
  Features/Video/Playback/PlaybackEngine.swift \
  Features/Video/VideoWindowChromeController.swift \
  script/test_video_window_aspect_layout.swift \
  -o /tmp/test_video_window_aspect_layout
```

Expected: compilation fails because `VideoWindowAspectLayout` has no member `constrainedFrameSize`.

- [ ] **Step 3: Implement the minimal pure geometry helper**

Add this method after `fittedContentSize` in `VideoWindowAspectLayout`:

```swift
    static func constrainedFrameSize(
        currentFrameSize: CGSize,
        proposedFrameSize: CGSize,
        frameDecorationSize: CGSize,
        videoAspectRatio: CGFloat,
        sidebarWidth: CGFloat,
        minimumFrameSize: CGSize
    ) -> CGSize {
        let scalarValues = [
            currentFrameSize.width, currentFrameSize.height,
            proposedFrameSize.width, proposedFrameSize.height,
            frameDecorationSize.width, frameDecorationSize.height,
            videoAspectRatio, sidebarWidth,
            minimumFrameSize.width, minimumFrameSize.height,
        ]
        guard scalarValues.allSatisfy(\.isFinite),
              currentFrameSize.width > 0,
              currentFrameSize.height > 0,
              proposedFrameSize.width > 0,
              proposedFrameSize.height > 0,
              videoAspectRatio > 0 else {
            return proposedFrameSize
        }

        let decorationWidth = max(frameDecorationSize.width, 0)
        let decorationHeight = max(frameDecorationSize.height, 0)
        let sidebarWidth = max(sidebarWidth, 0)
        let currentContentWidth = max(currentFrameSize.width - decorationWidth, 1)
        let currentContentHeight = max(currentFrameSize.height - decorationHeight, 1)
        let proposedContentWidth = max(proposedFrameSize.width - decorationWidth, 1)
        let proposedContentHeight = max(proposedFrameSize.height - decorationHeight, 1)
        let widthDelta = proposedContentWidth - currentContentWidth
        let heightDelta = proposedContentHeight - currentContentHeight
        let tolerance: CGFloat = 0.5

        guard abs(widthDelta) > tolerance || abs(heightDelta) > tolerance else {
            return proposedFrameSize
        }

        let isWidthDriven: Bool
        if abs(heightDelta) <= tolerance {
            isWidthDriven = true
        } else if abs(widthDelta) <= tolerance {
            isWidthDriven = false
        } else {
            isWidthDriven = abs(widthDelta / videoAspectRatio) >= abs(heightDelta)
        }

        var contentHeight = isWidthDriven
            ? (proposedContentWidth - sidebarWidth) / videoAspectRatio
            : proposedContentHeight
        let minimumContentHeight = max(
            max(
                minimumFrameSize.height - decorationHeight,
                (minimumFrameSize.width - decorationWidth - sidebarWidth) / videoAspectRatio
            ),
            1
        )
        contentHeight = max(contentHeight, minimumContentHeight)

        let result = CGSize(
            width: contentHeight * videoAspectRatio + sidebarWidth + decorationWidth,
            height: contentHeight + decorationHeight
        )
        guard result.width.isFinite,
              result.height.isFinite,
              result.width > 0,
              result.height > 0 else {
            return proposedFrameSize
        }
        return result
    }
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the compile command from Step 2 followed by:

```bash
/tmp/test_video_window_aspect_layout
```

Expected: `Video window aspect layout tests passed`.

---

### Task 2: Route live AppKit resize proposals through the window-scoped controller

**Files:**
- Modify: `script/test_video_window_contract.swift:82-108`
- Modify: `script/test_video_fullscreen_contract.swift:158-173`
- Modify: `Features/Video/VideoWindowChromeController.swift:113-168`
- Modify: `NativeMac/VideoWindowPresenter.swift:5-107`

**Interfaces:**
- Consumes: Task 1's `VideoWindowAspectLayout.constrainedFrameSize(...)`, `VideoLayoutPolicy`, and the existing `FullScreenState`.
- Produces: `VideoWindowChromeController.constrainedFrameSize(for:) -> NSSize`; `VideoWindowPresenter.windowWillResize(_:to:) -> NSSize`; one shared controller instance per player window.

- [ ] **Step 1: Write failing wiring and full-screen safety contracts**

Replace the existing controller-ownership assertion in `script/test_video_window_contract.swift` with:

```swift
require(
    presenter.contains("private var videoWindowChrome: VideoWindowChromeController?")
        && presenter.contains("let videoWindowChrome = VideoWindowChromeController()")
        && presenter.contains("VideoWindowRootView(videoWindowChrome: videoWindowChrome)")
        && presenter.contains("@State private var videoWindowChrome: VideoWindowChromeController")
        && presenter.contains("_videoWindowChrome = State(initialValue: videoWindowChrome)")
        && presenter.contains("windowChrome: videoWindowChrome")
        && presenter.contains("videoWindowChrome.attach(window)"),
    "the dedicated Video window and SwiftUI root should share one window-scoped chrome controller"
)
require(
    presenter.contains("func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize")
        && presenter.contains("videoWindowChrome?.constrainedFrameSize(for: frameSize) ?? frameSize")
        && windowChrome.contains("func constrainedFrameSize(for proposedFrameSize: NSSize) -> NSSize")
        && windowChrome.contains("case .windowed = fullScreenState")
        && windowChrome.contains("VideoWindowAspectLayout.constrainedFrameSize("),
    "user-driven Video window resizing should be corrected by the window-scoped layout and full-screen policy"
)
```

Extend the final AppKit-aspect assertion in `script/test_video_fullscreen_contract.swift` to require:

```swift
require(
    windowChrome.contains("window.contentAspectRatio = .zero")
        && !windowChrome.contains("window.contentAspectRatio = aspectRatio")
        && !windowChrome.contains("window.aspectRatio =")
        && windowChrome.contains("case .windowed = fullScreenState"),
    "Video live resizing should avoid persistent AppKit aspect constraints and bypass non-windowed states"
)
```

- [ ] **Step 2: Run the contracts and verify RED**

Run:

```bash
swift script/test_video_window_contract.swift
swift script/test_video_fullscreen_contract.swift
```

Expected: both fail because the presenter does not yet forward `windowWillResize` and still constructs the controller inside the SwiftUI root.

- [ ] **Step 3: Add the full-screen-gated controller resolver**

Add this method after `setVideoLayout` in `VideoWindowChromeController`:

```swift
    func constrainedFrameSize(for proposedFrameSize: NSSize) -> NSSize {
        guard let window,
              case .windowed = fullScreenState,
              let videoAspectRatio = videoLayoutPolicy.videoAspectRatio else {
            return proposedFrameSize
        }

        let currentFrameSize = window.frame.size
        let currentContentSize = window.contentRect(forFrameRect: window.frame).size
        let frameDecorationSize = CGSize(
            width: max(currentFrameSize.width - currentContentSize.width, 0),
            height: max(currentFrameSize.height - currentContentSize.height, 0)
        )
        let sidebarWidth = videoLayoutPolicy.isSidebarVisible
            ? videoLayoutPolicy.sidebarWidth
            : 0
        return VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: currentFrameSize,
            proposedFrameSize: proposedFrameSize,
            frameDecorationSize: frameDecorationSize,
            videoAspectRatio: videoAspectRatio,
            sidebarWidth: sidebarWidth,
            minimumFrameSize: window.minSize
        )
    }
```

- [ ] **Step 4: Share the controller and forward delegate resizing**

In `VideoWindowPresenter`:

```swift
    private var window: NSWindow?
    private var videoWindowChrome: VideoWindowChromeController?
    private weak var coordinator: VideoWindowCoordinator?
```

Create and inject the controller at the start of `makeWindow`:

```swift
        let videoWindowChrome = VideoWindowChromeController()
        let rootView = VideoWindowRootView(videoWindowChrome: videoWindowChrome)
            .environment(userConfig)
            .environment(coordinator)
```

Retain it with the window:

```swift
        self.videoWindowChrome = videoWindowChrome
        self.window = window
```

Forward AppKit proposals:

```swift
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === window else { return frameSize }
        return videoWindowChrome?.constrainedFrameSize(for: frameSize) ?? frameSize
    }
```

Clear it in the existing deferred teardown:

```swift
            if self?.window === closingWindow {
                self?.videoWindowChrome = nil
                self?.window = nil
            }
```

Replace the root's constructed controller with injected state:

```swift
    @State private var videoWindowChrome: VideoWindowChromeController

    init(videoWindowChrome: VideoWindowChromeController) {
        _videoWindowChrome = State(initialValue: videoWindowChrome)
    }
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
swift script/test_video_window_contract.swift
swift script/test_video_fullscreen_contract.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-video-aspect-clang \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-video-aspect-swift \
xcrun swiftc -D HOSHI_VIDEO -parse-as-library \
  Features/Video/Playback/PlaybackEngine.swift \
  Features/Video/VideoWindowChromeController.swift \
  script/test_video_window_aspect_layout.swift \
  -o /tmp/test_video_window_aspect_layout && /tmp/test_video_window_aspect_layout
```

Expected: all three checks pass.

---

### Task 3: Synchronize user-visible and architecture truth sources

**Files:**
- Modify: `docs/CHANGELOG.md:5-26`
- Modify: `docs/VIDEO_LEARNING_ARCHITECTURE.md:201,257-272`
- Modify: `docs/TODO.md:31,52`

**Interfaces:**
- Consumes: completed live-resize behavior and its verified safety boundary.
- Produces: accurate user-visible release note, architecture constraint, current state, and manual validation coverage.

- [ ] **Step 1: Update the changelog in Chinese and English**

Add one item to each `1.3.6` language section:

```markdown
- 修复 Video 窗口可被自由拉伸而产生黑边的问题；普通窗口现在始终按当前视频比例缩放，打开学习侧栏时仍保持视频画面比例，并避开原生全屏切换期间的窗口约束。
```

```markdown
- Fixed the Video window being freely stretched into letterboxing. Windowed resizing now follows the current video aspect ratio, keeps the video surface aspect-correct with the study sidebar open, and avoids window constraints during native full-screen transitions.
```

- [ ] **Step 2: Update architecture and TODO wording**

Replace the windowed playback implementation bullet in `docs/VIDEO_LEARNING_ARCHITECTURE.md` with:

```markdown
- Windowed playback uses mpv's display dimensions for one-shot fitting when media, rotation, aspect override, or study-sidebar state changes. During user-driven resizing, `VideoWindowPresenter.windowWillResize(_:to:)` asks the window-scoped chrome controller for an aspect-correct proposed size only while safely windowed; the video surface keeps its effective ratio and the pushed study sidebar keeps its current width. Hoshi does not leave a persistent `NSWindow.aspectRatio` or `NSWindow.contentAspectRatio` constraint installed, because AppKit full-screen exit snapshots can crash or freeze when a constrained window is resized during the system transition. Full screen keeps normal pure-black letterboxing; the existing mpv video-only screenshot path remains isolated from window chrome and subtitles.
```

Replace the stable full-screen chain paragraph with:

```markdown
The stable Hoshi chain is now: `VideoWindowPresenter` owns a normal AppKit `NSWindow` with `fullScreenPrimary` and forwards user resize proposals to the same window-scoped `VideoWindowChromeController`; the controller is the single full-screen state source, clears any old aspect constraint, ignores repeated toggles while entering/exiting, applies one-shot windowed aspect fitting outside full screen, and returns aspect-correct delegate sizes only in the settled windowed state; `MpvRenderView` remains attached instead of being removed or blacked out for transition workarounds; custom fullscreen controls, double-click, `f`, and `Esc` all route through the same window toggle/exit path. Future changes must not reintroduce a persistent AppKit aspect constraint, `setFrame` or size correction during native full-screen transitions, SwiftUI window identity churn, or mpv render detach inside AppKit full-screen will/exit notifications.
```

Replace the Visual Contract windowed-playback bullet with:

```markdown
- Windowed playback should avoid letterbox space by fitting the dedicated window to the current video's effective aspect ratio when media/sidebar state changes and by returning aspect-correct sizes throughout user edge/corner dragging. The pushed study sidebar adds its current width while the inspector remains an overlay. Do not leave a persistent AppKit aspect-ratio lock installed or constrain native full-screen transitions. Full screen keeps normal pure-black letterboxing and does not use ambient blur.
```

Append this sentence to the current-state Video-window bullet in `docs/TODO.md`:

```markdown
Windowed edge and corner resizing follows the effective video ratio through delegate-proposed sizes, reserves the pushed study-sidebar width, and bypasses all native full-screen transition states without installing a persistent AppKit aspect constraint.
```

In the existing manual Video validation entry, insert `aspect-locked resizing from all edges/corners before and after native full screen, resizing with the study sidebar visible,` immediately after `pointer playback/fullscreen gestures,`.

- [ ] **Step 3: Validate documentation and diff hygiene**

Run:

```bash
git diff --check
rg -n "live resize|windowWillResize|persistent AppKit|全屏|aspect" \
  docs/CHANGELOG.md docs/VIDEO_LEARNING_ARCHITECTURE.md docs/TODO.md
```

Expected: no whitespace errors; the three truth sources describe the same behavior and safety boundary.

---

### Task 4: Verify both variants and the exact Video app

**Files:**
- Verify only: all files changed in Tasks 1-3.

**Interfaces:**
- Consumes: complete implementation and documentation.
- Produces: contract, build, launch, and manual runtime evidence without committing or publishing.

- [ ] **Step 1: Run affected standalone contracts**

Run:

```bash
swift script/test_video_window_contract.swift
swift script/test_video_fullscreen_contract.swift
swift script/test_video_liquid_glass_contract.swift
swift script/test_video_player_interactions_contract.swift
CLANG_MODULE_CACHE_PATH=/tmp/hoshi-video-aspect-clang \
SWIFT_MODULECACHE_PATH=/tmp/hoshi-video-aspect-swift \
xcrun swiftc -D HOSHI_VIDEO -parse-as-library \
  Features/Video/Playback/PlaybackEngine.swift \
  Features/Video/VideoWindowChromeController.swift \
  script/test_video_window_aspect_layout.swift \
  -o /tmp/test_video_window_aspect_layout && /tmp/test_video_window_aspect_layout
```

Expected: every contract prints its passing summary.

- [ ] **Step 2: Run Light release-boundary verification and launch**

Run:

```bash
./script/verify_native_release_contract.sh
./script/build_and_run.sh --instance video-aspect-light --verify
```

Expected: the Light contract passes; the exact DerivedData Light app has bundle id `moe.shishamo.hoshi`, launches successfully, and its running executable matches the script's built path.

- [ ] **Step 3: Run Video release-boundary verification and launch**

If bundled libmpv is not already present, run `./script/bootstrap_libmpv.sh` first. Then run:

```bash
./script/verify_video_variant_contract.sh
./script/build_and_run.sh --video --instance video-aspect-video --verify
```

Expected: the Video contract passes; the exact DerivedData Video app has bundle id `moe.shishamo.hoshi`, launches successfully, and its running executable matches the script's built path.

- [ ] **Step 4: Perform precise real-video window/full-screen validation**

Open a local video only through the exact Video build from Step 3. Verify all four edges and four corners at small, medium, and large window sizes; repeat with Mining History or Transcript visible. Then enter and exit native full screen through the bottom button, green traffic light, `f`, and `Esc`, waiting for each transition and re-reading current UI state before the next action. Confirm the returned window remains responsive, retains video-aspect resizing, and shows no crash, freeze, render detachment, or stale frame.

- [ ] **Step 5: Review the final working tree without committing**

Run:

```bash
git diff --check
git diff --stat
git status --short --branch
```

Expected: only the planned implementation, tests, design/plan, and minimum truth-source documentation are changed; the branch remains uncommitted for user review.
