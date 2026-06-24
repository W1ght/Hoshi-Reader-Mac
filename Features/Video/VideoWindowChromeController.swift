#if HOSHI_VIDEO
import AppKit
import Observation

@MainActor
@Observable
final class VideoWindowChromeController {
    private weak var window: NSWindow?
    private var chromeVisible = true
    private var originalTitleVisibility: NSWindow.TitleVisibility?
    private var fullScreenObservers: [NSObjectProtocol] = []

    var hasWindow: Bool { window != nil }

    private(set) var isFullScreen = false
    private var shouldShowWindowButtons: Bool {
        chromeVisible || isFullScreen
    }

    func attach(_ window: NSWindow?) {
        guard self.window !== window else {
            applyChromeVisibility()
            return
        }
        restoreAttachedWindow()
        self.window = window
        updateFullScreenState()
        originalTitleVisibility = window?.titleVisibility
        installFullScreenObservers(for: window)
        applyChromeVisibility()
    }

    func setChromeVisible(_ visible: Bool) {
        chromeVisible = visible
        applyChromeVisibility()
    }

    func toggleFullScreen() {
        window?.toggleFullScreen(nil)
    }

    private func applyChromeVisibility() {
        guard let window else { return }
        for button in windowButtons(in: window) {
            button.isHidden = !shouldShowWindowButtons
        }
        window.titleVisibility = chromeVisible ? .visible : .hidden
    }

    private func installFullScreenObservers(for window: NSWindow?) {
        guard let window else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            fullScreenObservers.append(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.updateFullScreenState()
                        self?.applyChromeVisibility()
                    }
                }
            )
        }
    }

    private func restoreAttachedWindow() {
        fullScreenObservers.forEach(NotificationCenter.default.removeObserver)
        fullScreenObservers.removeAll()
        guard let window else { return }
        for button in windowButtons(in: window) {
            button.isHidden = false
        }
        window.titleVisibility = originalTitleVisibility ?? .visible
        self.window = nil
        isFullScreen = false
        originalTitleVisibility = nil
    }

    private func updateFullScreenState() {
        isFullScreen = window?.styleMask.contains(.fullScreen) == true
    }

    private func windowButtons(in window: NSWindow) -> [NSButton] {
        [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton),
        ].compactMap { $0 }
    }
}
#endif
