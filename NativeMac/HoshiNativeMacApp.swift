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
    @State private var systemColorScheme = Self.currentSystemColorScheme()

    init() {
        BookStorage.migrateFromDocuments()
        BookStorage.migrateBooks()
        _ = ProfileRepository.shared
        _ = DictionaryManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ShortcutManagedRootView()
                .frame(minWidth: 900, minHeight: 620)
                .environment(userConfig)
                .preferredColorScheme(preferredColorScheme)
                .onAppear {
                    ProfileSettingsStore.shared.bootstrap(userConfig: userConfig)
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
                .onReceive(
                    DistributedNotificationCenter.default().publisher(
                        for: Notification.Name("AppleInterfaceThemeChangedNotification")
                    )
                ) { _ in
                    refreshSystemColorScheme()
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
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

private struct ShortcutManagedRootView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var shortcutManager = ShortcutManager(registry: .application)

    var body: some View {
        NativeMacRootView()
            .environment(shortcutManager)
            .onAppear {
                shortcutManager.configure(userConfig: userConfig)
                shortcutManager.install()
            }
            .onDisappear {
                shortcutManager.uninstall()
            }
    }
}
