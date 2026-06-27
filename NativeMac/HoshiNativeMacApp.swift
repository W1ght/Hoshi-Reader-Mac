import AppKit
import SwiftUI

final class HoshiNativeMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if HOSHI_VIDEO
        VideoPlaybackMenuVisibilityController.shared.install()
        #endif
    }

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
    @State private var readerWindowCoordinator = ReaderWindowCoordinator()
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
                    .environment(readerWindowCoordinator)
                    .environment(videoWindowCoordinator)
                #else
                ShortcutManagedRootView()
                    .environment(readerWindowCoordinator)
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
                .onChange(of: userConfig.dictionaryProfileSettings()) { _, settings in
                    ProfileSettingsStore.shared.persistDictionarySettings(settings)
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
        .commands {
            VideoPlaybackCommands()
        }
        #endif

        Settings {
            NativeSettingsWindowRoot()
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
                .onChange(of: userConfig.dictionaryProfileSettings()) { _, settings in
                    ProfileSettingsStore.shared.persistDictionarySettings(settings)
                }
        }

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

private struct NativeSettingsWindowRoot: View {
    var body: some View {
        NativeSettingsReuseView()
            .frame(width: 820, height: 560)
    }
}

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
