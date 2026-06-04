import SwiftUI

@main
struct HoshiNativeMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var userConfig = UserConfig()

    init() {
        TokenStorage.clearOldKeys()
        BookStorage.migrateFromDocuments()
        BookStorage.migrateBooks()
        _ = DictionaryManager.shared
    }

    var body: some Scene {
        WindowGroup {
            NativeMacRootView()
                .frame(minWidth: 900, minHeight: 620)
                .environment(userConfig)
                .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : (userConfig.theme == .sepia && userConfig.sepiaInvertInDark ? nil : userConfig.theme.colorScheme))
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        LocalFileServer.shared.setAudioServer(enabled: userConfig.enableLocalAudio)
                        AnkiManager.shared.handleAppBecameActive()
                        if userConfig.autoUpdateDictionaries {
                            DictionaryManager.shared.autoUpdateDictionaries()
                        }
                    }
                }
                .onChange(of: userConfig.enableLocalAudio) { _, _ in
                    LocalFileServer.shared.setAudioServer(enabled: userConfig.enableLocalAudio)
                }
        }
    }
}
