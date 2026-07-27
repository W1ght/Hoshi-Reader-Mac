import AppKit
import SwiftUI

@MainActor
final class MangaWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = MangaWindowPresenter()
    private static let frameAutosaveName = NSWindow.FrameAutosaveName("Niratan.MangaReaderWindow")

    private var window: NSWindow?
    private weak var coordinator: MangaWindowCoordinator?

    func open(
        item: MangaLibraryItem,
        source: MangaLibrarySource,
        coordinator: MangaWindowCoordinator,
        userConfig: UserConfig
    ) {
        self.coordinator = coordinator
        coordinator.requestOpen(item: item, source: source)
        let window = window ?? makeWindow(
            coordinator: coordinator,
            userConfig: userConfig
        )
        window.title = item.displayTitle
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func open(
        session: MangaReadingSession,
        pageProvider: any MangaPageContentProvider,
        coordinator: MangaWindowCoordinator,
        userConfig: UserConfig
    ) {
        self.coordinator = coordinator
        coordinator.requestOpen(
            session: session,
            pageProvider: pageProvider
        )
        let window = window ?? makeWindow(
            coordinator: coordinator,
            userConfig: userConfig
        )
        window.title = session.title
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func open(
        request: MangaRemoteReadingRequest,
        coordinator: MangaWindowCoordinator,
        userConfig: UserConfig
    ) {
        self.coordinator = coordinator
        coordinator.requestOpen(request: request)
        let window = window ?? makeWindow(
            coordinator: coordinator,
            userConfig: userConfig
        )
        window.title = request.title
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow(
        coordinator: MangaWindowCoordinator,
        userConfig: UserConfig
    ) -> NSWindow {
        let rootView = MangaWindowRootView()
            .environment(coordinator)
            .environment(userConfig)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(MangaWindowCoordinator.windowID)
        window.minSize = NSSize(width: 760, height: 560)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = NSHostingController(rootView: rootView)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.delegate = self
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else {
            return
        }
        if !closingWindow.styleMask.contains(.fullScreen) {
            closingWindow.saveFrame(usingName: Self.frameAutosaveName)
        }
        coordinator?.windowDidDisappear()
        coordinator = nil
        DispatchQueue.main.async { [weak self, weak closingWindow] in
            guard self?.window === closingWindow else { return }
            closingWindow?.delegate = nil
            self?.window = nil
        }
    }
}

private struct MangaWindowRootView: View {
    @Environment(UserConfig.self) private var userConfig
    @Environment(MangaWindowCoordinator.self) private var coordinator
    @State private var shortcutManager = ShortcutManager(registry: .application)

    var body: some View {
        Group {
            if let request = coordinator.currentRequest {
                switch request.content {
                case .local(let item, let source):
                    MangaReaderView(item: item, source: source)
                        .id(coordinator.sessionID)
                case .remote(let session, let pageProvider):
                    MangaReaderView(
                        session: session,
                        pageProvider: pageProvider
                    )
                    .id(coordinator.sessionID)
                case .remoteRequest(let request):
                    MangaRemoteReaderLoadingView(request: request)
                        .id(coordinator.sessionID)
                }
            } else {
                EmptyView()
            }
        }
        .environment(shortcutManager)
        .toolbar(.visible, for: .windowToolbar)
        .background {
            NativeWindowActivityReader { window, _ in
                shortcutManager.manageEvents(for: window)
            }
        }
        .onAppear {
            coordinator.windowDidAppear()
            shortcutManager.configure(userConfig: userConfig)
            shortcutManager.install()
        }
        .onDisappear {
            coordinator.windowDidDisappear()
            shortcutManager.uninstall()
        }
    }
}

private struct MangaRemoteReaderLoadingView: View {
    let request: MangaRemoteReadingRequest

    @State private var result: MangaRemoteReadingResult?
    @State private var errorMessage: String?
    @State private var loadID = UUID()

    var body: some View {
        Group {
            if let result {
                MangaReaderView(
                    session: result.session,
                    pageProvider: result.pageProvider
                )
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(
                        "Unable to Open Manga",
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        loadID = UUID()
                    }
                    .buttonStyle(.glass)
                }
            } else {
                ProgressView("Preparing Manga Pages…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .task(id: loadID) {
            errorMessage = nil
            do {
                result = try await request.load()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
