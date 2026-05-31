//
//  AnkiConnectView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

struct AnkiConnectView: View {
    @State private var ankiManager = AnkiManager.shared

    var body: some View {
        List {
            Section {
                if AppPlatform.usesDesktopLayout {
                    Text("Mac card creation uses AnkiConnect.")
                        .foregroundStyle(.secondary)
                } else {
                    Toggle(isOn: $ankiManager.useAnkiConnect) {
                        Text("Use AnkiConnect", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.useAnkiConnect) { _, _ in ankiManager.save() }
                }
            } footer: {
                Text(AppPlatform.usesDesktopLayout ? "The iOS AnkiMobile callback flow is not available on Mac." : "This will replace AnkiMobile callbacks with AnkiConnect requests.")
            }

            Section {
                if ankiManager.useAnkiConnect || AppPlatform.usesDesktopLayout {
                    VStack(alignment: .leading, spacing: 3) {
                        TextField(text: Binding(
                            get: { ankiManager.ankiConnectConfig?.url ?? "http://127.0.0.1:8765" },
                            set: { ankiManager.ankiConnectConfig?.url = $0 }
                        ), prompt: Text("Address", tableName: "Dictionaries")) {
                            Text("Address", tableName: "Dictionaries")
                        }
                        .onSubmit { ankiManager.save() }
                    }
                    Button {
                        Task { await ankiManager.pingAnkiConnect() }
                    } label: {
                        Text("Connect", tableName: "Dictionaries")
                    }
                }
            } header: {
                Text("Connection", tableName: "Dictionaries")
            } footer: {
                if ankiManager.useAnkiConnect || AppPlatform.usesDesktopLayout {
                    Text("Status: \(connectionStatus)", tableName: "Dictionaries")
                }
            }

            if (ankiManager.useAnkiConnect || AppPlatform.usesDesktopLayout) && ankiManager.isConnected {
                Section {
                    Picker(selection: Binding(
                        get: { ankiManager.ankiConnectConfig?.duplicateScope ?? .collection },
                        set: { value in
                            ankiManager.ankiConnectConfig?.duplicateScope = value
                            ankiManager.save()
                        }
                    )) {
                        Text("Collection", tableName: "Dictionaries").tag(DuplicateScope.collection)
                        Text("Deck", tableName: "Dictionaries").tag(DuplicateScope.deck)
                        Text("Deck Root", tableName: "Dictionaries").tag(DuplicateScope.deckroot)
                    } label: {
                        Text("Duplicate Scope", tableName: "Dictionaries")
                    }

                    Toggle(isOn: Binding(
                        get: { ankiManager.ankiConnectConfig?.checkAllModels ?? false },
                        set: { value in
                            ankiManager.ankiConnectConfig?.checkAllModels = value
                            ankiManager.save()
                        }
                    )) {
                        Text("Check All Models", tableName: "Dictionaries")
                    }

                    Toggle(isOn: Binding(
                        get: { ankiManager.ankiConnectConfig?.forceSync ?? false },
                        set: { value in
                            ankiManager.ankiConnectConfig?.forceSync = value
                            ankiManager.save()
                        }
                    )) {
                        Text("Force Sync on adding card", tableName: "Dictionaries")
                    }
                } header: {
                    Text("Settings", tableName: "Dictionaries")
                }
            }
        }
        .navigationTitle(String(localized: "AnkiConnect", table: "Dictionaries"))
        .onAppear {
            if AppPlatform.usesDesktopLayout && !ankiManager.useAnkiConnect {
                ankiManager.useAnkiConnect = true
                ankiManager.save()
            }
        }
    }

    private var connectionStatus: String {
        if ankiManager.isConnected {
            String(localized: "Connected", table: "Dictionaries")
        } else {
            String(localized: "Not connected", table: "Dictionaries")
        }
    }
}
