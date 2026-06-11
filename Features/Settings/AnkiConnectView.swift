//
//  AnkiConnectView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AnkiConnectView: View {
    @State private var ankiManager = AnkiManager.shared

    var body: some View {
        #if os(macOS) && !targetEnvironment(macCatalyst)
        NativeSettingsForm {
            NativeSettingsSectionCard {
                Text("AnkiConnect", tableName: "Dictionaries")
            } content: {
                NativeSettingsButtonRow {
                    Text("Mac card creation uses AnkiConnect.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("AnkiMobile callbacks are not used in the Mac app.")
            }

            NativeSettingsSectionCard {
                Text("Connection", tableName: "Dictionaries")
            } content: {
                NativeSettingsRow {
                    Text("Address", tableName: "Dictionaries")
                } accessory: {
                    TextField(text: Binding(
                        get: { ankiManager.ankiConnectConfig?.url ?? "http://127.0.0.1:8765" },
                        set: { ankiManager.ankiConnectConfig?.url = $0 }
                    ), prompt: Text("Address", tableName: "Dictionaries")) {
                        Text("Address", tableName: "Dictionaries")
                    }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { ankiManager.save() }
                }
                NativeSettingsSeparator()
                NativeSettingsButtonRow {
                    Button {
                        Task { await ankiManager.pingAnkiConnect() }
                    } label: {
                        Text("Connect", tableName: "Dictionaries")
                    }
                    Text("Status: \(connectionStatus)", tableName: "Dictionaries")
                        .foregroundStyle(.secondary)
                }
            }

            if ankiManager.isConnected {
                NativeSettingsSectionCard {
                    Text("Settings", tableName: "Dictionaries")
                } content: {
                    NativeSettingsRow {
                        Text("Duplicate Scope", tableName: "Dictionaries")
                    } accessory: {
                        NativeGlassSegmentedPicker(
                            selection: Binding(
                                get: { ankiManager.ankiConnectConfig?.duplicateScope ?? .collection },
                                set: { value in
                                    ankiManager.ankiConnectConfig?.duplicateScope = value
                                    ankiManager.save()
                                }
                            ),
                            values: [DuplicateScope.collection, .deck, .deckroot],
                            minSegmentWidth: 82
                        ) { scope in
                            duplicateScopeText(scope)
                        }
                    }

                    NativeSettingsSeparator()
                    NativeSettingsRow {
                        Text("Check All Models", tableName: "Dictionaries")
                    } accessory: {
                        Toggle("", isOn: Binding(
                            get: { ankiManager.ankiConnectConfig?.checkAllModels ?? false },
                            set: { value in
                                ankiManager.ankiConnectConfig?.checkAllModels = value
                                ankiManager.save()
                            }
                        ))
                        .labelsHidden()
                    }

                    NativeSettingsSeparator()
                    NativeSettingsRow {
                        Text("Force Sync on adding card", tableName: "Dictionaries")
                    } accessory: {
                        Toggle("", isOn: Binding(
                            get: { ankiManager.ankiConnectConfig?.forceSync ?? false },
                            set: { value in
                                ankiManager.ankiConnectConfig?.forceSync = value
                                ankiManager.save()
                            }
                        ))
                        .labelsHidden()
                    }
                }
            }
        }
        .navigationTitle(String(localized: "AnkiConnect", table: "Dictionaries"))
        .onAppear {
            ankiManager.handleAppBecameActive()
        }
        #else
        List {
            Section {
                Text("Mac card creation uses AnkiConnect.")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("AnkiMobile callbacks are not used in the Mac app.")
            }

            Section {
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
            } header: {
                Text("Connection", tableName: "Dictionaries")
            } footer: {
                Text("Status: \(connectionStatus)", tableName: "Dictionaries")
            }

            if ankiManager.isConnected {
                Section {
                    #if os(macOS) && !targetEnvironment(macCatalyst)
                    HStack {
                        Text("Duplicate Scope", tableName: "Dictionaries")
                        Spacer()
                        NativeGlassSegmentedPicker(
                            selection: Binding(
                                get: { ankiManager.ankiConnectConfig?.duplicateScope ?? .collection },
                                set: { value in
                                    ankiManager.ankiConnectConfig?.duplicateScope = value
                                    ankiManager.save()
                                }
                            ),
                            values: [DuplicateScope.collection, .deck, .deckroot],
                            minSegmentWidth: 82
                        ) { scope in
                            duplicateScopeText(scope)
                        }
                    }
                    #else
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
                    #endif

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
            ankiManager.handleAppBecameActive()
        }
        #endif
    }

    private var connectionStatus: String {
        if ankiManager.isConnected {
            String(localized: "Connected", table: "Dictionaries")
        } else {
            String(localized: "Not connected", table: "Dictionaries")
        }
    }

    private func duplicateScopeText(_ scope: DuplicateScope) -> Text {
        switch scope {
        case .collection:
            Text("Collection", tableName: "Dictionaries")
        case .deck:
            Text("Deck", tableName: "Dictionaries")
        case .deckroot:
            Text("Deck Root", tableName: "Dictionaries")
        }
    }
}
