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
let shortcutManager = read("Core/Shortcuts/ShortcutManager.swift")
let windowActivity = read("NativeMac/NativeWindowActivityReader.swift")
let playbackEngine = read("Features/Video/Playback/PlaybackEngine.swift")
let mpvEngine = read("Features/Video/Playback/MpvPlayerEngine.swift")
let clientHeader = read("Features/Video/Playback/HSMpvClient.h")
let clientImplementation = read("Features/Video/Playback/HSMpvClient.mm")

require(
    coordinator.contains("static let windowID = \"video-player\"")
        && app.contains("Window(\"Video\", id: VideoWindowCoordinator.windowID)")
        && app.contains(".windowManagerRole(.principal)")
        && app.contains(".restorationBehavior(.disabled)")
        && app.contains(".defaultSize(width: 1200, height: 760)")
        && app.contains(".id(videoWindowCoordinator.sessionID)")
        && app.contains("videoWindowCoordinator.windowDidDisappear()"),
    "Video variant should declare one non-restoring dedicated player window"
)
require(
    app.contains(".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)")
        && !app.contains(".toolbar(.hidden, for: .windowToolbar)"),
    "dedicated Video window should keep native traffic-light controls while making only the toolbar background transparent"
)
require(
    windowChrome.contains("final class VideoWindowChromeController")
        && windowChrome.contains("private weak var window: NSWindow?")
        && windowChrome.contains("private var shouldShowWindowButtons: Bool")
        && windowChrome.contains("chromeVisible || isFullScreen")
        && windowChrome.contains("standardWindowButton(.closeButton)")
        && windowChrome.contains("standardWindowButton(.miniaturizeButton)")
        && windowChrome.contains("standardWindowButton(.zoomButton)")
        && windowChrome.contains("func setChromeVisible(_ visible: Bool)")
        && windowChrome.contains("func toggleFullScreen()")
        && windowChrome.contains("window?.toggleFullScreen(nil)"),
    "Video window chrome should keep native traffic lights visible in full screen while owning its full-screen target"
)
require(
    windowChrome.contains("enum VideoWindowAspectLayout")
        && windowChrome.contains("func setVideoLayout(")
        && windowChrome.contains("window.contentAspectRatio")
        && windowChrome.contains("applyVideoAspectLock")
        && windowChrome.contains("restoreVideoAspectLock"),
    "Video window chrome should own windowed aspect-ratio constraints and release them for full screen"
)
require(
    app.contains("@State private var videoWindowChrome = VideoWindowChromeController()")
        && app.contains("windowChrome: videoWindowChrome")
        && app.contains("videoWindowChrome.attach(window)"),
    "the dedicated Video scene should attach one window-specific chrome controller"
)
require(
    player.contains("let windowChrome: VideoWindowChromeController")
        && player.contains(".onChange(of: shouldShowPlaybackChrome, initial: true)")
        && player.contains("windowChrome.setChromeVisible(isVisible)")
        && player.contains("windowChrome.toggleFullScreen()")
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
    !detail.contains("VideoPlayerScreen")
        && detail.contains("case .video:")
        && detail.contains("VideoLibraryView(onOpenVideo: onOpenVideo)"),
    "main detail should render the Video library without keeping a hidden VideoPlayerScreen alive"
)
require(
    root.contains("@Environment(\\.openWindow)")
        && root.contains("VideoMediaTypes.isMediaFile(url)")
        && root.contains("openVideoWindow(with: url)")
        && root.contains("videoWindowCoordinator.requestOpen(url, subtitleURL: subtitleURL)")
        && root.contains("openWindow(id: VideoWindowCoordinator.windowID)")
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
    app.contains("@State private var isKeyWindow = false")
        && app.contains("NativeWindowActivityReader")
        && app.contains("isActive: isKeyWindow")
        && root.contains("let isKeyWindow: Bool")
        && root.contains("guard isKeyWindow else { return }")
        && app.contains("activateVideoProfileIfNeeded()"),
    "Profile and Video shortcut activation should follow the key window instead of scene creation order"
)

print("Video window contract tests passed")
