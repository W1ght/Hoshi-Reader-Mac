import AppKit
import SwiftUI

final class HoshiNativeMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.sendAction(#selector(NSWindowController.newWindowForTab(_:)), to: nil, from: nil)
        }
        return true
    }
}

@main
struct HoshiNativeMacApp: App {
    @NSApplicationDelegateAdaptor(HoshiNativeMacAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var userConfig = UserConfig()
    @State private var selectionLookupCoordinator = SelectionLookupCoordinator()
    @State private var systemColorScheme = Self.currentSystemColorScheme()
    #if HOSHI_VIDEO
    @State private var videoWindowCoordinator = VideoWindowCoordinator()
    #endif

    init() {
        BookStorage.migrateFromDocuments()
        BookStorage.migrateBooks()
        _ = ProfileRepository.shared
        _ = DictionaryManager.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if HOSHI_VIDEO
                ShortcutManagedRootView()
                    .environment(videoWindowCoordinator)
                #else
                ShortcutManagedRootView()
                #endif
            }
                .frame(minWidth: 900, minHeight: 620)
                .environment(userConfig)
                .environment(selectionLookupCoordinator)
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    ProfileSettingsStore.shared.bootstrap(userConfig: userConfig)
                    selectionLookupCoordinator.configure(userConfig: userConfig)
                    syncApplicationAppearance()
                    refreshSystemColorScheme()
                }
                .onChange(of: userConfig.theme) { _, _ in
                    syncApplicationAppearance()
                    refreshSystemColorScheme()
                }
                .onChange(of: userConfig.uiTheme) { _, _ in
                    syncApplicationAppearance()
                    refreshSystemColorScheme()
                }
                .onChange(of: userConfig.sepiaInvertInDark) { _, _ in
                    syncApplicationAppearance()
                    refreshSystemColorScheme()
                }
                .onChange(of: userConfig.readerProfileSettings()) { _, settings in
                    ProfileSettingsStore.shared.persistReaderSettings(settings)
                }
                .onReceive(
                    DistributedNotificationCenter.default().publisher(
                        for: Notification.Name("AppleInterfaceThemeChangedNotification")
                    )
                ) { _ in
                    refreshSystemColorScheme()
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        selectionLookupCoordinator.refresh()
                        refreshSystemColorScheme()
                        LocalFileServer.shared.setAudioServer(enabled: userConfig.enableLocalAudio)
                        AnkiManager.shared.handleAppBecameActive()
                        if userConfig.autoUpdateDictionaries {
                            DictionaryManager.shared.autoUpdateDictionaries()
                        }
                    } else {
                        ProfileSettingsStore.shared.persistCurrent(userConfig: userConfig)
                        AnkiManager.shared.save()
                    }
                }
                .onChange(of: userConfig.enableLocalAudio) { _, _ in
                    LocalFileServer.shared.setAudioServer(enabled: userConfig.enableLocalAudio)
                }
                .onChange(of: userConfig.shortcutBinding(for: GlobalShortcutActions.lookupSelectedText)) { _, _ in
                    selectionLookupCoordinator.refresh()
                }
        }

        #if HOSHI_VIDEO
        Window("Video", id: VideoWindowCoordinator.windowID) {
            VideoWindowSceneRoot()
                .frame(minWidth: 900, minHeight: 620)
                .environment(userConfig)
                .environment(videoWindowCoordinator)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 1200, height: 760)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .windowManagerRole(.principal)
        #endif
    }

    private var preferredColorScheme: ColorScheme? {
        if userConfig.theme == .custom {
            return userConfig.uiTheme.colorScheme
        }

        if userConfig.theme == .system {
            return systemColorScheme
        }

        if userConfig.theme == .sepia && userConfig.sepiaInvertInDark {
            return systemColorScheme
        }

        return userConfig.theme.colorScheme
    }

    private func syncApplicationAppearance() {
        switch preferredColorScheme {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case nil:
            NSApp.appearance = nil
        @unknown default:
            NSApp.appearance = nil
        }
    }

    private func refreshSystemColorScheme() {
        DispatchQueue.main.async {
            systemColorScheme = Self.currentSystemColorScheme()
        }
    }

    private static func currentSystemColorScheme() -> ColorScheme {
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" {
            return .dark
        }
        return .light
    }
}

#if HOSHI_VIDEO
private struct VideoWindowSceneRoot: View {
    @Environment(UserConfig.self) private var userConfig
    @Environment(VideoWindowCoordinator.self) private var videoWindowCoordinator
    @State private var shortcutManager = ShortcutManager(registry: .application)
    @State private var profileRepository = ProfileRepository.shared
    @State private var isKeyWindow = false
    @State private var videoWindowChrome = VideoWindowChromeController()

    var body: some View {
        VideoPlayerScreen(
            isActive: isKeyWindow,
            openRequest: videoWindowCoordinator.pendingRequest,
            onConsumeOpenRequest: videoWindowCoordinator.consume,
            windowChrome: videoWindowChrome
        )
        .id(videoWindowCoordinator.sessionID)
        .environment(shortcutManager)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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
            activateVideoProfileIfNeeded()
        }
        .onChange(of: isKeyWindow) { _, _ in
            activateVideoProfileIfNeeded()
        }
        .onChange(of: profileRepository.storedVideoProfileID) { _, _ in
            activateVideoProfileIfNeeded()
        }
        .onDisappear {
            videoWindowCoordinator.windowDidDisappear()
            videoWindowChrome.attach(nil)
            shortcutManager.uninstall()
        }
    }

    private func activateVideoProfileIfNeeded() {
        guard isKeyWindow else { return }
        ProfileActivationCoordinator.activate(
            .video(profileID: profileRepository.videoProfileID),
            userConfig: userConfig,
            repository: profileRepository
        )
    }
}
#endif

private struct ShortcutManagedRootView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var shortcutManager = ShortcutManager(registry: .application)
    @State private var isKeyWindow = false

    var body: some View {
        NativeMacRootView(isKeyWindow: isKeyWindow)
            .environment(shortcutManager)
            .background {
                NativeWindowActivityReader { window, isKey in
                    shortcutManager.manageEvents(for: window)
                    isKeyWindow = isKey
                }
            }
            .onAppear {
                shortcutManager.configure(userConfig: userConfig)
                shortcutManager.install()
            }
            .onDisappear {
                shortcutManager.uninstall()
            }
    }
}
