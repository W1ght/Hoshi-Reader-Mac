import AppKit
import SwiftUI

@MainActor
final class VideoWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = VideoWindowPresenter()

    private var window: NSWindow?
    private var videoWindowChrome: VideoWindowChromeController?
    private weak var coordinator: VideoWindowCoordinator?

    func open(
        url: URL,
        subtitleURL: URL? = nil,
        coordinator: VideoWindowCoordinator,
        userConfig: UserConfig
    ) {
        open(
            source: .localFile(url),
            subtitleURL: subtitleURL,
            coordinator: coordinator,
            userConfig: userConfig
        )
    }

    func open(
        source: VideoPlaybackSource,
        subtitleURL: URL? = nil,
        coordinator: VideoWindowCoordinator,
        userConfig: UserConfig
    ) {
        self.coordinator = coordinator
        coordinator.requestOpen(source, subtitleURL: subtitleURL)
        let window = window ?? makeWindow(
            coordinator: coordinator,
            userConfig: userConfig
        )
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow(
        coordinator: VideoWindowCoordinator,
        userConfig: UserConfig
    ) -> NSWindow {
        let videoWindowChrome = VideoWindowChromeController()
        let rootView = VideoWindowRootView(videoWindowChrome: videoWindowChrome)
            .environment(userConfig)
            .environment(coordinator)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: defaultVideoWindowFrame(),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(VideoWindowCoordinator.windowID)
        window.title = String(localized: "Video")
        configureVideoWindowChrome(window)
        window.minSize = NSSize(width: 900, height: 620)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = hostingController
        window.delegate = self
        self.videoWindowChrome = videoWindowChrome
        self.window = window
        return window
    }

    private func configureVideoWindowChrome(_ window: NSWindow) {
        window.titlebarAppearsTransparent = false
    }

    private func defaultVideoWindowFrame() -> NSRect {
        let visibleFrame = NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else {
            return NSRect(x: 0, y: 0, width: 1200, height: 760)
        }
        let size = NSSize(
            width: min(max(900, visibleFrame.width * 0.78), visibleFrame.width),
            height: min(max(620, visibleFrame.height * 0.78), visibleFrame.height)
        )
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        ).integral
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard sender === window else { return frameSize }
        return videoWindowChrome?.constrainedFrameSize(for: frameSize) ?? frameSize
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else {
            return
        }
        coordinator?.windowDidDisappear()
        coordinator = nil
        scheduleWindowTeardown(closingWindow)
    }

    private func scheduleWindowTeardown(_ closingWindow: NSWindow) {
        DispatchQueue.main.async { [weak self, closingWindow] in
            closingWindow.contentViewController = nil
            closingWindow.delegate = nil
            if self?.window === closingWindow {
                self?.videoWindowChrome = nil
                self?.window = nil
            }
        }
    }
}

private struct VideoWindowRootView: View {
    @Environment(UserConfig.self) private var userConfig
    @Environment(VideoWindowCoordinator.self) private var videoWindowCoordinator
    @State private var shortcutManager = ShortcutManager(registry: .application)
    @State private var isKeyWindow = false
    @State private var videoWindowChrome: VideoWindowChromeController

    init(videoWindowChrome: VideoWindowChromeController) {
        _videoWindowChrome = State(initialValue: videoWindowChrome)
    }

    var body: some View {
        VideoPlayerScreen(
            isActive: isKeyWindow,
            openRequest: videoWindowCoordinator.pendingRequest,
            onConsumeOpenRequest: videoWindowCoordinator.consume,
            windowChrome: videoWindowChrome
        )
        .id(videoWindowCoordinator.sessionID)
        .frame(minWidth: 900, minHeight: 620)
        .environment(shortcutManager)
        .preferredColorScheme(preferredColorScheme)
        .background {
            NativeWindowActivityReader { window, isKey in
                shortcutManager.manageEvents(for: window)
                videoWindowChrome.attach(window)
                isKeyWindow = isKey
            }
        }
        .onAppear {
            videoWindowCoordinator.windowDidAppear()
            shortcutManager.configure(userConfig: userConfig)
            shortcutManager.install()
        }
        .onDisappear {
            videoWindowCoordinator.windowDidDisappear()
            videoWindowChrome.attach(nil)
            shortcutManager.uninstall()
        }
    }

    private var preferredColorScheme: ColorScheme? {
        if userConfig.theme == .custom {
            return userConfig.uiTheme.colorScheme
        }

        if userConfig.theme == .system {
            return nil
        }

        if userConfig.theme == .sepia && userConfig.sepiaInvertInDark {
            return nil
        }

        return userConfig.theme.colorScheme
    }

}
