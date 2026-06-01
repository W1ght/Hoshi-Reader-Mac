//
//  HoshiReader.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

@main
struct HoshiReaderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var userConfig = UserConfig()
    @State private var pendingImportURL: URL?
    @State private var pendingRemoteImportURL: URL?
    @State private var pendingLookup: String?
    @State private var pendingTab: Int?
    
    init() {
        TokenStorage.clearOldKeys()
        BookStorage.migrateFromDocuments()
        BookStorage.migrateBooks()
        WebViewPreloader.shared.warmup()
        _ = DictionaryManager.shared
        AppAppearance.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            BookshelfView(
                pendingImportURL: $pendingImportURL,
                pendingRemoteImportURL: $pendingRemoteImportURL,
                pendingLookup: $pendingLookup,
                pendingTab: $pendingTab
            )
            .environment(userConfig)
            .preferredColorScheme(userConfig.theme == .custom ? userConfig.uiTheme.colorScheme : (userConfig.theme == .sepia && userConfig.sepiaInvertInDark ? nil : userConfig.theme.colorScheme))
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active:
                    LocalFileServer.shared.setAudioServer(enabled: userConfig.enableLocalAudio)
                    AnkiManager.shared.handleAppBecameActive()
                    if userConfig.autoUpdateDictionaries {
                        DictionaryManager.shared.autoUpdateDictionaries()
                    }
                default:
                    break
                }
            }
            .onChange(of: userConfig.enableLocalAudio) { _, _ in
                LocalFileServer.shared.setAudioServer(enabled: userConfig.enableLocalAudio)
            }
            .onOpenURL { url in
                handleURL(url)
            }
        }
    }
    
    private func handleURL(_ url: URL) {
        if url.scheme == "hoshi" {
            if url.host == "search" {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                pendingLookup = components?.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
            } else if url.host == "open", let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let urlString = components.queryItems?.first(where: { $0.name == "url" })?.value,
                      let remoteURL = URL(string: urlString) {
                pendingRemoteImportURL = remoteURL
            }
        } else if url.isFileURL {
            pendingImportURL = url
        }
    }
}
