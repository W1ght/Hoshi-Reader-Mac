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
                    Toggle("Use AnkiConnect", isOn: $ankiManager.useAnkiConnect)
                        .onChange(of: ankiManager.useAnkiConnect) { _, _ in ankiManager.save() }
                }
            } footer: {
                Text(AppPlatform.usesDesktopLayout ? "The iOS AnkiMobile callback flow is not available on Mac." : "This will replace AnkiMobile callbacks with AnkiConnect requests.")
            }

            Section {
                if ankiManager.useAnkiConnect || AppPlatform.usesDesktopLayout {
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Address", text: Binding(
                            get: { ankiManager.ankiConnectConfig?.url ?? "http://127.0.0.1:8765" },
                            set: { ankiManager.ankiConnectConfig?.url = $0 }
                        ))
                        .onSubmit { ankiManager.save() }
                    }
                    Button("Connect") { Task { await ankiManager.pingAnkiConnect() } }
                }
            } header: {
                Text("Connection")
            } footer: {
                if ankiManager.useAnkiConnect || AppPlatform.usesDesktopLayout {
                    Text("Status: \(ankiManager.isConnected ? "Connected" : "Not connected")")
                }
            }

            if (ankiManager.useAnkiConnect || AppPlatform.usesDesktopLayout) && ankiManager.isConnected {
                Section("Settings") {
                    Picker("Duplicate Scope", selection: Binding(
                        get: { ankiManager.ankiConnectConfig?.duplicateScope ?? .collection },
                        set: { value in
                            ankiManager.ankiConnectConfig?.duplicateScope = value
                            ankiManager.save()
                        }
                    )) {
                        Text("Collection").tag(DuplicateScope.collection)
                        Text("Deck").tag(DuplicateScope.deck)
                        Text("Deck Root").tag(DuplicateScope.deckroot)
                    }

                    Toggle("Check All Models", isOn: Binding(
                        get: { ankiManager.ankiConnectConfig?.checkAllModels ?? false },
                        set: { value in
                            ankiManager.ankiConnectConfig?.checkAllModels = value
                            ankiManager.save()
                        }
                    ))

                    Toggle("Force Sync on adding card", isOn: Binding(
                        get: { ankiManager.ankiConnectConfig?.forceSync ?? false },
                        set: { value in
                            ankiManager.ankiConnectConfig?.forceSync = value
                            ankiManager.save()
                        }
                    ))
                }
            }
        }
        .navigationTitle("AnkiConnect")
        .onAppear {
            if AppPlatform.usesDesktopLayout && !ankiManager.useAnkiConnect {
                ankiManager.useAnkiConnect = true
                ankiManager.save()
            }
        }
    }
}
