#if HOSHI_VIDEO
import AppKit
import Observation

enum VideoWindowAspectLayout {
    static func videoAspectRatio(
        displaySize: CGSize?,
        override: VideoAspectRatio,
        rotation: Int
    ) -> CGFloat? {
        let baseRatio: CGFloat?
        if let overrideRatio = override.numericValue {
            baseRatio = overrideRatio
        } else if let displaySize,
                  displaySize.width > 0,
                  displaySize.height > 0 {
            baseRatio = displaySize.width / displaySize.height
        } else {
            baseRatio = nil
        }

        guard let ratio = baseRatio,
              ratio.isFinite,
              ratio > 0 else {
            return nil
        }

        return isQuarterTurn(rotation) ? 1 / ratio : ratio
    }

    static func fittedContentSize(
        currentContentSize: CGSize,
        videoAspectRatio: CGFloat,
        sidebarWidth: CGFloat,
        visibleContentFrame: CGRect
    ) -> CGSize {
        guard videoAspectRatio.isFinite,
              videoAspectRatio > 0 else {
            return currentContentSize
        }

        let sidebarWidth = max(sidebarWidth, 0)
        let maxWidth = max(visibleContentFrame.width, 1)
        let maxHeight = max(visibleContentFrame.height, 1)
        let availableVideoWidth = max(maxWidth - sidebarWidth, 1)
        var height = max(currentContentSize.height, 1)

        if height > maxHeight {
            height = maxHeight
        }
        if height * videoAspectRatio > availableVideoWidth {
            height = max(availableVideoWidth / videoAspectRatio, 1)
        }

        let width = min(height * videoAspectRatio + sidebarWidth, maxWidth)
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    static func aspectFittingSidebarWidth(
        contentSize: CGSize,
        videoAspectRatio: CGFloat?,
        proposedWidth: CGFloat,
        minWidth: CGFloat,
        maxWidth: CGFloat
    ) -> CGFloat {
        let clampedProposedWidth = min(max(proposedWidth, minWidth), maxWidth)
        guard let videoAspectRatio,
              videoAspectRatio.isFinite,
              videoAspectRatio > 0,
              contentSize.width > 0,
              contentSize.height > 0 else {
            return clampedProposedWidth
        }

        let fittedWidth = contentSize.width - contentSize.height * videoAspectRatio
        guard fittedWidth.isFinite,
              fittedWidth >= minWidth,
              fittedWidth <= maxWidth else {
            return clampedProposedWidth
        }
        return fittedWidth
    }

    static func clampedFrame(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
        var result = frame
        if result.width > visibleFrame.width {
            result.size.width = visibleFrame.width
        }
        if result.height > visibleFrame.height {
            result.size.height = visibleFrame.height
        }
        if result.maxX > visibleFrame.maxX {
            result.origin.x = visibleFrame.maxX - result.width
        }
        if result.minX < visibleFrame.minX {
            result.origin.x = visibleFrame.minX
        }
        if result.maxY > visibleFrame.maxY {
            result.origin.y = visibleFrame.maxY - result.height
        }
        if result.minY < visibleFrame.minY {
            result.origin.y = visibleFrame.minY
        }
        return result
    }

    private static func isQuarterTurn(_ rotation: Int) -> Bool {
        let normalized = ((rotation % 360) + 360) % 360
        return normalized == 90 || normalized == 270
    }
}

@MainActor
@Observable
final class VideoWindowChromeController {
    private weak var window: NSWindow?
    private var originalTitleVisibility: NSWindow.TitleVisibility?
    private var videoLayoutPolicy = VideoLayoutPolicy()
    private var fullScreenObservers: [NSObjectProtocol] = []
    private var fullScreenTransitionFallbackTask: Task<Void, Never>?
    private var fullScreenState: FullScreenState = .windowed
    private var isFullScreenTransitioning: Bool {
        fullScreenState.isTransitioning
    }

    var hasWindow: Bool { window != nil }

    private(set) var isFullScreen = false
    func attach(_ window: NSWindow?) {
        guard self.window !== window else {
            guard !isFullScreenTransitioning else { return }
            configureSystemFullScreenBehavior(for: window)
            applyChromeVisibility()
            applyVideoAspectFit(adjustFrame: false)
            return
        }
        restoreAttachedWindow()
        self.window = window
        updateFullScreenState()
        fullScreenState = isFullScreen ? .fullScreen : .windowed
        originalTitleVisibility = window?.titleVisibility
        configureSystemFullScreenBehavior(for: window)
        installFullScreenObservers(for: window)
        applyChromeVisibility()
        applyVideoAspectFit(adjustFrame: false)
    }

    func setChromeVisible(_ visible: Bool) {
        _ = visible
        guard !isFullScreenTransitioning else { return }
        applyChromeVisibility()
    }

    func setVideoLayout(
        videoAspectRatio: CGFloat?,
        studySidebarWidth: CGFloat,
        isStudySidebarVisible: Bool
    ) {
        let nextPolicy = VideoLayoutPolicy(
            videoAspectRatio: videoAspectRatio,
            sidebarWidth: studySidebarWidth,
            isSidebarVisible: isStudySidebarVisible
        )
        let shouldAdjustFrame = nextPolicy != videoLayoutPolicy
        videoLayoutPolicy = nextPolicy
        guard !isFullScreenTransitioning else { return }
        applyVideoAspectFit(adjustFrame: shouldAdjustFrame)
    }

    func toggleFullScreen() {
        guard let window, !isFullScreenTransitioning else { return }
        clearVideoAspectConstraint()
        fullScreenState = currentSystemFullScreenState() ? .exiting : .entering
        window.toggleFullScreen(nil)
        scheduleFullScreenTransitionFallback()
    }

    func exitFullScreen() {
        guard currentSystemFullScreenState() else { return }
        toggleFullScreen()
    }

    private func applyChromeVisibility() {
        guard let window else { return }
        guard !isFullScreenTransitioning else { return }
        for button in windowButtons(in: window) {
            button.isHidden = false
        }
        window.titleVisibility = .visible
    }

    private func restoreAttachedWindow() {
        fullScreenObservers.forEach(NotificationCenter.default.removeObserver)
        fullScreenObservers.removeAll()
        fullScreenTransitionFallbackTask?.cancel()
        fullScreenTransitionFallbackTask = nil
        guard let window else { return }
        for button in windowButtons(in: window) {
            button.isHidden = false
        }
        window.titleVisibility = originalTitleVisibility ?? .visible
        clearVideoAspectConstraint()
        self.window = nil
        isFullScreen = false
        fullScreenState = .windowed
        originalTitleVisibility = nil
    }

    private func installFullScreenObservers(for window: NSWindow?) {
        guard let window else { return }
        let center = NotificationCenter.default
        let observedNotifications: [(Notification.Name, FullScreenState)] = [
            (NSWindow.willEnterFullScreenNotification, .entering),
            (NSWindow.didEnterFullScreenNotification, .fullScreen),
            (NSWindow.willExitFullScreenNotification, .exiting),
            (NSWindow.didExitFullScreenNotification, .windowed),
        ]
        for (name, state) in observedNotifications {
            fullScreenObservers.append(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.handleFullScreenNotification(state)
                    }
                }
            )
        }
    }

    private func handleFullScreenNotification(_ state: FullScreenState) {
        switch state {
        case .entering, .exiting:
            fullScreenState = state
            clearVideoAspectConstraint()
        case .fullScreen, .windowed:
            fullScreenState = state
            fullScreenTransitionFallbackTask?.cancel()
            fullScreenTransitionFallbackTask = nil
            updateFullScreenState()
            applyChromeVisibility()
            applyVideoAspectFit(adjustFrame: false)
        }
    }

    private func updateFullScreenState() {
        isFullScreen = currentSystemFullScreenState()
    }

    private func currentSystemFullScreenState() -> Bool {
        guard let window else { return false }
        return window.styleMask.contains(.fullScreen)
    }

    private func scheduleFullScreenTransitionFallback() {
        fullScreenTransitionFallbackTask?.cancel()
        fullScreenTransitionFallbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, self.isFullScreenTransitioning else { return }
            self.updateFullScreenState()
            self.fullScreenState = self.isFullScreen ? .fullScreen : .windowed
            self.applyChromeVisibility()
            self.applyVideoAspectFit(adjustFrame: false)
        }
    }

    private func applyVideoAspectFit(adjustFrame: Bool) {
        guard let window else { return }
        clearVideoAspectConstraint()
        guard !isFullScreenTransitioning,
              !isFullScreen,
              let videoAspectRatio = videoLayoutPolicy.videoAspectRatio else {
            return
        }

        let contentRect = window.contentRect(forFrameRect: window.frame)
        let sidebarWidth = videoLayoutPolicy.isSidebarVisible
            ? videoLayoutPolicy.sidebarWidth
            : 0
        let visibleFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? window.frame
        let fittedContentSize = VideoWindowAspectLayout.fittedContentSize(
            currentContentSize: contentRect.size,
            videoAspectRatio: videoAspectRatio,
            sidebarWidth: sidebarWidth,
            visibleContentFrame: visibleFrame
        )

        guard adjustFrame,
              abs(contentRect.width - fittedContentSize.width) > 0.5
                || abs(contentRect.height - fittedContentSize.height) > 0.5 else {
            return
        }

        let fittedContentRect = NSRect(
            x: contentRect.minX,
            y: contentRect.maxY - fittedContentSize.height,
            width: fittedContentSize.width,
            height: fittedContentSize.height
        )
        let fittedFrame = window.frameRect(forContentRect: fittedContentRect)
        window.setFrame(
            VideoWindowAspectLayout.clampedFrame(fittedFrame, to: visibleFrame),
            display: true,
            animate: false
        )
    }

    private func clearVideoAspectConstraint() {
        guard let window else { return }
        if window.contentAspectRatio != .zero {
            window.contentAspectRatio = .zero
        }
    }

    private func configureSystemFullScreenBehavior(for window: NSWindow?) {
        guard let window else { return }
        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.remove(.fullScreenDisallowsTiling)
        window.collectionBehavior.insert(.fullScreenPrimary)
    }

    private func windowButtons(in window: NSWindow) -> [NSButton] {
        [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton),
        ].compactMap { $0 }
    }

    private struct VideoLayoutPolicy: Equatable {
        var videoAspectRatio: CGFloat?
        var sidebarWidth: CGFloat
        var isSidebarVisible: Bool

        init(
            videoAspectRatio: CGFloat? = nil,
            sidebarWidth: CGFloat = 0,
            isSidebarVisible: Bool = false
        ) {
            if let videoAspectRatio,
               videoAspectRatio.isFinite,
               videoAspectRatio > 0 {
                self.videoAspectRatio = videoAspectRatio
            } else {
                self.videoAspectRatio = nil
            }
            self.sidebarWidth = max(sidebarWidth, 0)
            self.isSidebarVisible = isSidebarVisible
        }
    }

    private enum FullScreenState {
        case windowed
        case entering
        case fullScreen
        case exiting

        var isTransitioning: Bool {
            switch self {
            case .entering, .exiting:
                true
            case .windowed, .fullScreen:
                false
            }
        }
    }

}
#endif
