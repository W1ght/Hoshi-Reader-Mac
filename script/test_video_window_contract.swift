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
    presenter.contains("@State private var videoWindowChrome = VideoWindowChromeController()")
        && presenter.contains("windowChrome: videoWindowChrome")
        && presenter.contains("videoWindowChrome.attach(window)"),
    "the dedicated Video scene should attach one window-specific chrome controller"
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
        && clientImplementation.contains("mpv_render_context_set_update_callback(_renderContext, HSMpvRenderUpdate, (__bridge void *)view);")
        && clientImplementation.contains("[view setNeedsDisplay:YES];\n        return YES;"),
    "mpv client should move the existing render context and update callback to a replacement OpenGL view"
)
require(
    !detail.contains("VideoPlayerScreen")
        && detail.contains("case .video:")
        && detail.contains("VideoLibraryView(onOpenVideo: onOpenVideo)"),
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
        && root.contains("let isKeyWindow: Bool")
        && root.contains("guard isKeyWindow else { return }")
        && presenter.contains("activateVideoProfileIfNeeded()"),
    "Profile and Video shortcut activation should follow the key window instead of scene creation order"
)

print("Video window contract tests passed")
