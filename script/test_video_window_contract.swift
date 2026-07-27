import Foundation

private func read(_ path: String) -> String {
    guard let value = try? String(contentsOfFile: path, encoding: .utf8) else {
        fputs("FAIL: unable to read \(path)\n", stderr)
        exit(1)
    }
    return value
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let app = read("NativeMac/HoshiNativeMacApp.swift")
let root = read("NativeMac/NativeMacRootView.swift")
let detail = read("NativeMac/NativeMacDetailView.swift")
let player = read("Features/Video/VideoPlayerScreen.swift")
let renderView = read("Features/Video/Playback/MpvRenderView.swift")
let windowChrome = read("Features/Video/VideoWindowChromeController.swift")
let coordinator = read("Features/Video/VideoWindowCoordinator.swift")
let presenter = read("NativeMac/VideoWindowPresenter.swift")
let shortcutManager = read("Core/Shortcuts/ShortcutManager.swift")
let windowActivity = read("NativeMac/NativeWindowActivityReader.swift")
let playbackEngine = read("Features/Video/Playback/PlaybackEngine.swift")
let mpvEngine = read("Features/Video/Playback/MpvPlayerEngine.swift")
let clientHeader = read("Features/Video/Playback/HSMpvClient.h")
let clientImplementation = read("Features/Video/Playback/HSMpvClient.mm")

require(
    coordinator.contains("static let windowID = \"video-player\"")
        && presenter.contains("final class VideoWindowPresenter: NSObject, NSWindowDelegate")
        && presenter.contains("NSWindow(")
        && presenter.contains("window.identifier = NSUserInterfaceItemIdentifier(VideoWindowCoordinator.windowID)")
        && presenter.contains("window.collectionBehavior.insert(.fullScreenPrimary)")
        && presenter.contains("window.contentViewController = hostingController")
        && !app.contains(".windowManagerRole(.principal)")
        && !app.contains("Window(\"Video\", id: VideoWindowCoordinator.windowID)")
        && presenter.contains(".id(videoWindowCoordinator.sessionID)")
        && presenter.contains("videoWindowCoordinator.windowDidDisappear()"),
    "Video variant should declare one AppKit-owned non-restoring dedicated system-fullscreen player window"
)
require(
    presenter.contains("window.titlebarAppearsTransparent = false")
        && !presenter.contains("window.styleMask.insert(.fullSizeContentView)")
        && !presenter.contains(".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)")
        && !app.contains(".toolbar(.hidden, for: .windowToolbar)"),
    "dedicated Video window should keep standard native traffic-light controls available for system fullscreen"
)
require(
    presenter.contains("window.isReleasedWhenClosed = false")
        && presenter.contains("scheduleWindowTeardown(")
        && presenter.contains("DispatchQueue.main.async")
        && presenter.contains("closingWindow.contentViewController = nil")
        && presenter.contains("closingWindow.delegate = nil")
        && !presenter.contains("window = nil\n    }"),
    "manual Video NSWindow should remain retained through AppKit close teardown before releasing SwiftUI content"
)
require(
    windowChrome.contains("final class VideoWindowChromeController")
        && windowChrome.contains("private weak var window: NSWindow?")
        && windowChrome.contains("standardWindowButton(.closeButton)")
        && windowChrome.contains("standardWindowButton(.miniaturizeButton)")
        && windowChrome.contains("standardWindowButton(.zoomButton)")
        && windowChrome.contains("func setChromeVisible(_ visible: Bool)")
        && windowChrome.contains("func toggleFullScreen()")
        && windowChrome.contains("func exitFullScreen()")
        && windowChrome.contains("window.toggleFullScreen(nil)")
        && windowChrome.contains("NSWindow.willEnterFullScreenNotification")
        && windowChrome.contains("NSWindow.willExitFullScreenNotification")
        && windowChrome.contains("NSWindow.didExitFullScreenNotification")
        && windowChrome.contains("private enum FullScreenState")
        && windowChrome.contains("currentSystemFullScreenState()")
        && windowChrome.contains("scheduleFullScreenTransitionFallback()")
        && !windowChrome.contains("insert(.fullScreenNone)")
        && !windowChrome.contains("button.action = #selector"),
    "Video window chrome should keep native traffic lights visible while using system fullscreen"
)
require(
    windowChrome.contains("enum VideoWindowAspectLayout")
        && windowChrome.contains("func setVideoLayout(")
        && windowChrome.contains("applyVideoAspectFit")
        && windowChrome.contains("window.setFrame(")
        && windowChrome.contains("clearVideoAspectConstraint()")
        && windowChrome.contains("window.contentAspectRatio = .zero")
        && !windowChrome.contains("window.contentAspectRatio = aspectRatio"),
    "Video window chrome should fit the window frame without installing persistent AppKit aspect-ratio constraints"
)
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
require(
    player.contains("let windowChrome: VideoWindowChromeController")
        && player.contains(".onChange(of: shouldShowPlaybackChrome, initial: true)")
        && player.contains("windowChrome.setChromeVisible(isVisible)")
        && player.contains("windowChrome.toggleFullScreen()")
        && player.contains("isFullScreen: windowChrome.isFullScreen")
        && player.contains("windowChrome.setVideoLayout(")
        && player.contains("videoWindowAspectRatio")
        && player.contains("aspectFittingSidebarWidth")
        && !player.contains("NSApp.keyWindow?.toggleFullScreen(nil)"),
    "Video chrome visibility, full screen and aspect fitting should use the dedicated player window instead of global key-window state"
)
require(
    windowChrome.contains("func hidePlaybackCursorUntilMouseMoves()")
        && windowChrome.contains("NSApp.isActive")
        && windowChrome.contains("window?.isKeyWindow == true")
        && windowChrome.contains("NSCursor.setHiddenUntilMouseMoves(true)")
        && windowChrome.contains("func restorePlaybackCursor()")
        && windowChrome.contains("NSCursor.setHiddenUntilMouseMoves(false)")
        && windowChrome.contains("shouldRehidePlaybackCursorAfterMouseButtonEvent")
        && windowChrome.contains("NSEvent.addLocalMonitorForEvents(")
        && windowChrome.contains(".leftMouseDown")
        && windowChrome.contains(".rightMouseDown")
        && windowChrome.contains(".otherMouseDown")
        && windowChrome.contains("rehidePlaybackCursorAfterMouseButtonEventIfNeeded")
        && !windowChrome.contains("NSWindow.windowNumber(")
        && !windowChrome.contains("pointerWindowNumber == window?.windowNumber")
        && !windowChrome.contains("isCursorHiddenUntilMouseMoves")
        && !player.contains(".onChange(of: shouldHideVideoCursor"),
    "Video cursor auto-hide should follow IINA's direct AppKit call and reapply only for mouse-button events while playback chrome remains hidden"
)
require(
    player.contains("@AppStorage(\"videoStudySidebarWidth\")")
        && !player.contains("@SceneStorage(\"videoStudySidebarWidth\")"),
    "video player is hosted in a manual NSWindow and should not use SceneStorage for sidebar width"
)
require(
    playbackEngine.contains("var videoDisplaySize: CGSize?")
        && mpvEngine.contains("videoDisplaySize: videoWidth > 0 && videoHeight > 0")
        && clientHeader.contains("NSInteger videoWidth")
        && clientHeader.contains("NSInteger videoHeight")
        && clientImplementation.contains("mpv_observe_property(_handle, 12, \"video-params\", MPV_FORMAT_NODE)")
        && clientImplementation.contains("HSMpvVideoDisplaySizeFromNode"),
    "Video playback snapshots should carry mpv display dimensions for window aspect fitting"
)
require(
    mpvEngine.contains("private weak var attachedRenderView: HSMpvOpenGLView?")
        && mpvEngine.contains("if attachedRenderView === view { return true }")
        && mpvEngine.contains("client.attach(to: view)")
        && mpvEngine.contains("attachedRenderView = view")
        && !mpvEngine.contains("guard !isRenderAttached else { return true }"),
    "mpv playback should reattach when fullscreen transitions provide a new OpenGL render view"
)
require(
    clientImplementation.contains("if (_renderContext) {")
        && clientImplementation.contains("if (_view != view) {")
        && clientImplementation.contains("_view.renderContext = NULL;")
        && clientImplementation.contains("view.renderContext = _renderContext;")
        && clientImplementation.contains("[self installRenderUpdateCallbackForView:view];")
        && clientImplementation.contains("[view requestForcedRender];\n        return YES;"),
    "mpv client should move the existing render context and update callback to a replacement OpenGL view"
)
require(
    clientImplementation.contains("@interface HSMpvRenderUpdateTarget : NSObject")
        && clientImplementation.contains("@property (atomic, weak, nullable) HSMpvOpenGLView *view;")
        && clientImplementation.contains("@property (atomic) uint64_t generation;")
        && clientImplementation.contains("HSMpvRenderUpdateTarget *_renderUpdateTarget;")
        && clientImplementation.contains("void *_renderUpdateContext;")
        && clientImplementation.contains("_renderUpdateTarget = [[HSMpvRenderUpdateTarget alloc] init];")
        && clientImplementation.contains("HSMpvRenderUpdateTarget *target = (__bridge HSMpvRenderUpdateTarget *)context;")
        && clientImplementation.contains("uint64_t generation = target.generation;")
        && clientImplementation.contains("if (target.generation != generation) {")
        && clientImplementation.contains("HSMpvOpenGLView *view = target.view;")
        && clientImplementation.contains("[view requestRender];")
        && clientImplementation.contains("CFBridgingRetain(_renderUpdateTarget)")
        && clientImplementation.contains("CFRelease((CFTypeRef)_renderUpdateContext)")
        && clientImplementation.contains("_renderUpdateTarget.view = nil;")
        && clientImplementation.contains("_renderUpdateTarget.generation += 1;")
        && !clientImplementation.contains("mpv_render_context_set_update_callback(_renderContext, HSMpvRenderUpdate, (__bridge void *)view);"),
    "mpv render update callbacks should keep a retained stable weak-view target across asynchronous main-queue redraws"
)
require(
    clientImplementation.contains("- (void)performWithLockedOpenGLContext:(void (^)(void))body")
        && clientImplementation.contains("CGLLockContext(_context);")
        && clientImplementation.contains("CGLSetCurrentContext(_context);")
        && clientImplementation.contains("CGLUnlockContext(_context);")
        && clientImplementation.contains("[self performWithLockedOpenGLContext:^{")
        && clientImplementation.contains("[view performWithLockedOpenGLContext:^{")
        && clientImplementation.contains("HSMpvOpenGLView *view = _view;")
        && clientImplementation.contains("mpv_render_context_free(contextToFree);"),
    "mpv OpenGL render context should be rendered and freed only while its NSOpenGLContext is current and locked"
)
require(
    clientImplementation.contains("NSRecursiveLock *_subtitleCueLock;")
        && clientImplementation.contains("_subtitleCueLock = [[NSRecursiveLock alloc] init];")
        && clientImplementation.contains("- (void)resetSubtitleCueCache")
        && clientImplementation.contains("- (NSArray<HSMpvSubtitleCueInfo *> *)upsertFallbackSubtitleCueWithText:")
        && clientImplementation.contains("[_subtitleCueLock lock];")
        && clientImplementation.contains("[_subtitleCueLock unlock];")
        && !clientImplementation.contains("[_fallbackSubtitleCues removeAllObjects];"),
    "mpv subtitle cue cache should serialize fallback cue mutation before dispatching NSArray snapshots to the main queue"
)
require(
    !detail.contains("VideoPlayerScreen")
        && detail.contains("case .video:")
        && detail.contains("VideoLibraryView(")
        && detail.contains("onOpenVideo: onOpenVideo")
        && detail.contains("onOpenRemoteVideo: onOpenRemoteVideo"),
    "main detail should render the Video library without keeping a hidden VideoPlayerScreen alive"
)
require(
    !root.contains("@Environment(\\.openWindow)")
        && root.contains("VideoMediaTypes.isMediaFile(url)")
        && root.contains("openVideoWindow(with: url)")
        && root.contains("VideoWindowPresenter.shared.open(")
        && !root.contains("isSelectingVideoFile")
        && !root.contains("lastNonVideoSection"),
    "URL/file routes should open media in the dedicated player while sidebar Video stays on the library page"
)
require(
    player.contains("let openRequest: VideoWindowOpenRequest?")
        && player.contains(".onChange(of: openRequest, initial: true)")
        && player.contains("openGate.receive(request)")
        && player.contains("openGate.renderDidBecomeReady()")
        && renderView.contains("let onRenderReady: () -> Void")
        && !player.contains("toggleSidebar()")
        && !player.contains("Label(\"Sidebar\", systemImage: \"sidebar.leading\")"),
    "dedicated player should wait for render attachment before consuming external requests"
)
require(
    player.contains("VideoMediaTypes.contentTypes")
        && player.contains("VideoMediaTypes.isMediaFile")
        && !player.contains("private static let mpvMediaExtensions"),
    "main picker, player picker and drop routing should share one media type source"
)
require(
    windowActivity.contains("struct NativeWindowActivityReader")
        && windowActivity.contains("NSWindow.didBecomeKeyNotification")
        && windowActivity.contains("NSWindow.didResignKeyNotification")
        && shortcutManager.contains("private weak var managedWindow: NSWindow?")
        && shortcutManager.contains("func manageEvents(for window: NSWindow?)")
        && shortcutManager.contains("event.window === managedWindow"),
    "each scene should route keyboard events only through the manager that owns the event window"
)
require(
    presenter.contains("@State private var isKeyWindow = false")
        && presenter.contains("NativeWindowActivityReader")
        && presenter.contains("isActive: isKeyWindow")
        && player.contains("let isActive: Bool")
        && !presenter.contains("activateVideoProfileIfNeeded")
        && !presenter.contains("ProfileActivationCoordinator")
        && !presenter.contains("ProfileRepository")
        && !root.contains("ProfileActivationCoordinator"),
    "Video key-window state should control shortcuts only and must not activate a window-local Profile"
)

print("Video window contract tests passed")
