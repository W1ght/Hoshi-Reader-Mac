import AppKit
import SwiftUI

@MainActor
final class ReaderWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = ReaderWindowPresenter()

    private var window: NSWindow?
    private weak var coordinator: ReaderWindowCoordinator?

    func open(
        book: BookMetadata,
        coordinator: ReaderWindowCoordinator,
        userConfig: UserConfig
    ) {
        self.coordinator = coordinator
        coordinator.requestOpen(book)
        let window = window ?? makeWindow(coordinator: coordinator, userConfig: userConfig)
        window.title = book.displayTitle
        applyDefaultFrame(to: window)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow(
        coordinator: ReaderWindowCoordinator,
        userConfig: UserConfig
    ) -> NSWindow {
        let rootView = ReaderWindowRootView()
            .environment(userConfig)
            .environment(coordinator)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(ReaderWindowCoordinator.windowID)
        configureReaderWindowChrome(window)
        window.minSize = NSSize(width: 720, height: 520)
        window.isRestorable = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = hostingController
        applyDefaultFrame(to: window)
        window.delegate = self
        self.window = window
        return window
    }

    private func configureReaderWindowChrome(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
    }

    private func defaultReaderWindowFrame() -> NSRect {
        let visibleFrame = NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let visibleFrame else {
            return NSRect(x: 0, y: 0, width: 1100, height: 760)
        }
        let size = NSSize(
            width: max(720, visibleFrame.width * 2 / 3),
            height: max(520, visibleFrame.height * 2 / 3)
        )
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        ).integral
    }

    private func applyDefaultFrame(to window: NSWindow) {
        let defaultFrame = defaultReaderWindowFrame()
        window.setFrame(defaultFrame, display: true)
    }

    func windowWillClose(_ notification: Notification) {
        coordinator?.windowDidDisappear()
        coordinator = nil
        window = nil
    }
}

private struct ReaderWindowRootView: View {
    @Environment(UserConfig.self) private var userConfig
    @Environment(ReaderWindowCoordinator.self) private var readerWindowCoordinator
    @State private var shortcutManager = ShortcutManager(registry: .application)
    @State private var profileRepository = ProfileRepository.shared
    @State private var readerWindowChrome = ReaderWindowChromeController()
    @State private var isKeyWindow = false
    @State private var readerWindow: NSWindow?

    var body: some View {
        Group {
            if let request = readerWindowCoordinator.currentRequest {
                NativeReaderLoader(
                    book: request.book,
                    isActive: isKeyWindow,
                    onFocusModeChanged: readerWindowChrome.setFocusModeEnabled,
                    onClose: {
                        closeReaderWindow()
                    }
                )
                .id(readerWindowCoordinator.sessionID)
            } else {
                EmptyView()
            }
        }
        .environment(shortcutManager)
        .background {
            NativeWindowActivityReader { window, isKey in
                shortcutManager.manageEvents(for: window)
                readerWindowChrome.attach(window)
                readerWindow = window
                isKeyWindow = isKey
            }
        }
        .onAppear {
            readerWindowCoordinator.windowDidAppear()
            shortcutManager.configure(userConfig: userConfig)
            shortcutManager.install()
            consumePendingReaderRequestIfNeeded()
            activateBookProfileIfNeeded()
        }
        .onChange(of: readerWindowCoordinator.pendingRequest, initial: true) { _, _ in
            consumePendingReaderRequestIfNeeded()
        }
        .onChange(of: isKeyWindow) { _, _ in
            activateBookProfileIfNeeded()
        }
        .onChange(of: readerWindowCoordinator.currentRequest) { _, _ in
            activateBookProfileIfNeeded()
        }
        .onDisappear {
            readerWindowCoordinator.windowDidDisappear()
            readerWindowChrome.attach(nil)
            readerWindow = nil
            shortcutManager.uninstall()
        }
    }

    private func consumePendingReaderRequestIfNeeded() {
        guard let request = readerWindowCoordinator.pendingRequest else { return }
        readerWindowCoordinator.consume(request.id)
    }

    private func activateBookProfileIfNeeded() {
        guard isKeyWindow, let book = readerWindowCoordinator.currentBook else { return }
        ProfileActivationCoordinator.activate(
            .book(profileID: book.profileId, bookLanguage: book.bookLanguage),
            userConfig: userConfig,
            repository: profileRepository
        )
    }

    private func closeReaderWindow() {
        readerWindow?.performClose(nil)
    }
}

@MainActor
private final class ReaderWindowChromeController {
    private weak var window: NSWindow?
    private var focusModeEnabled = false

    func attach(_ window: NSWindow?) {
        guard self.window !== window else {
            applyTrafficLightVisibility()
            return
        }
        restoreAttachedWindowButtons()
        self.window = window
        applyTrafficLightVisibility()
    }

    func setFocusModeEnabled(_ enabled: Bool) {
        focusModeEnabled = enabled
        applyTrafficLightVisibility()
    }

    private func applyTrafficLightVisibility() {
        guard let window else { return }
        for button in trafficLightButtons(in: window) {
            button.isHidden = focusModeEnabled
        }
    }

    private func restoreAttachedWindowButtons() {
        guard let window else { return }
        for button in trafficLightButtons(in: window) {
            button.isHidden = false
        }
    }

    private func trafficLightButtons(in window: NSWindow) -> [NSButton] {
        [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton),
        ].compactMap { $0 }
    }
}
