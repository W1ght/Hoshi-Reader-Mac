//
//  SyncView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct SyncView: View {
    @Environment(UserConfig.self) var userConfig
    @State private var isAuthenticated = GoogleDriveAuth.shared.isAuthenticated
    @State private var isConnecting = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showClearCacheConfirmation = false
    @State private var showSignOutConfirmation = false
    
    var body: some View {
        @Bindable var userConfig = userConfig
        NativeSettingsForm {
            NativeSettingsSectionCard {
                Text("Syncing")
            } content: {
                NativeSettingsToggle("Enable", isOn: $userConfig.enableSync)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync bookmarks and statistics with ッツ Reader or between Hoshi Reader devices via Google Drive.")
                    if userConfig.enableSync {
                        Text("A **[Google Cloud project](https://github.com/ttu-ttu/ebook-reader?tab=readme-ov-file#storage-sources)** is necessary for syncing.")
                        Text("1. After the initial setup, create another **OAuth client ID** in the same project.")
                        Text("2. Select **iOS** as the **Application type** and set the **Bundle ID** to '**moe.shishamo.hoshi**'.")
                        Text("3. Paste the **Client ID** in the textbox below and press '**Connect Google Drive**'.")
                        Text("4. You can sync individual books by long-pressing and selecting '**Sync**'.")
                        Text("**[More...](https://github.com/Manhhao/Hoshi-Reader/blob/develop/TTUSYNC.md)**")
                    }
                }
            }

            if userConfig.enableSync {
                NativeSettingsSectionCard("Client ID") {
                    NativeSettingsRow("Required") {
                        TextField("Required", text: $userConfig.googleClientId)
                            .disabled(isAuthenticated)
                            .opacity(isAuthenticated ? 0.6 : 1)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                NativeSettingsSectionCard("Connection") {
                    NativeSettingsRow("Status") {
                        Text(isConnecting
                             ? String(localized: "Connecting...")
                             : (isAuthenticated ? String(localized: "Connected") : String(localized: "Not connected")))
                            .foregroundStyle(.secondary)
                    }
                    NativeSettingsSeparator()
                    NativeSettingsButtonRow {
                        if isAuthenticated {
                            Button(role: .destructive) {
                                showClearCacheConfirmation = true
                            } label: {
                                Text("Clear Cache")
                            }
                            Button(role: .destructive) {
                                showSignOutConfirmation = true
                            } label: {
                                Text("Sign out")
                            }
                        } else {
                            Button {
                                Task {
                                    isConnecting = true
                                    defer {
                                        isConnecting = false
                                        isAuthenticated = GoogleDriveAuth.shared.isAuthenticated
                                    }
                                    do {
                                        try await GoogleDriveAuth.shared.authenticate(clientId: userConfig.googleClientId)
                                    } catch {
                                        errorMessage = error.localizedDescription
                                        showError = true
                                    }
                                }
                            } label: {
                                Text("Connect Google Drive")
                            }
                            .disabled(isConnecting)
                        }
                    }
                }

                NativeSettingsSectionCard("Behaviour") {
                    NativeSettingsRow("Direction") {
                        NativeGlassSegmentedPicker(
                            selection: $userConfig.syncMode,
                            values: SyncMode.allCases,
                            minSegmentWidth: 76
                        ) { mode in
                            textOfSyncMode(mode)
                        }
                    }
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Auto Sync", isOn: $userConfig.enableAutoSync)
                }

                NativeSettingsSectionCard("Data") {
                    NativeSettingsToggle("Upload Books", isOn: $userConfig.syncUploadBooks)
                    NativeSettingsButtonRow {
                        Text("Uploads books on first sync if no bookdata is stored on Google Drive.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if userConfig.enableStatistics {
                        NativeSettingsSeparator()
                        NativeSettingsToggle("Sync Stats", isOn: $userConfig.statisticsEnableSync)
                    }

                    if userConfig.enableSasayaki {
                        NativeSettingsSeparator()
                        NativeSettingsToggle("Sync Audiobook Progress", isOn: $userConfig.sasayakiEnableSync)
                    }
                }
            }
        }
        .navigationTitle("Syncing")
        .onAppear {
            isAuthenticated = GoogleDriveAuth.shared.isAuthenticated
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Clear Cache?", isPresented: $showClearCacheConfirmation) {
            Button("Clear", role: .destructive) {
                GoogleDriveHandler.clearCache()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will clear cached folder ids and book covers.")
        }
        .alert("Sign out?", isPresented: $showSignOutConfirmation) {
            Button("Confirm", role: .destructive) {
                GoogleDriveAuth.shared.signOut()
                isAuthenticated = GoogleDriveAuth.shared.isAuthenticated
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Signing out will clear authorization tokens, cached folder ids and book covers.")
        }
    }

    private func textOfSyncMode(_ mode: SyncMode) -> some View {
        switch mode {
        case .auto:
            Text("Auto")
        case .manual:
            Text("Manual")
        }
    }
}
