//
//  AnkiView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AnkiView: View {
    @State private var ankiManager = AnkiManager.shared
    @State private var dictionaryManager = DictionaryManager.shared
    @State private var confirmFetch = false
    @State private var pendingDefaultsPreset: AnkiFieldMappingPreset?

    private var availableHandlebars: [String] {
        let hidden: Set<Handlebars> = [
            .glossaryNoDictionary,
            .glossaryFirstBrief,
            .glossaryFirstNoDictionary,
            .selectedGlossaryBrief,
            .selectedGlossaryBriefFallback,
            .selectedGlossaryNoDictionary,
            .selectedGlossaryNoDictionaryFallback
        ]
        var options = Handlebars.allCases
            .filter { !hidden.contains($0) }
            .filter { isVideoBuild || !$0.isVideoSpecific }
            .map(\.rawValue)
        for dict in dictionaryManager.termDictionaries {
            options.append("\(Handlebars.singleGlossaryPrefix)\(dict.index.title)}")
        }
        return options
    }

    private var isVideoBuild: Bool {
        Bundle.main.infoDictionary?["HoshiBuildVariant"] as? String == "Video"
    }

    var body: some View {
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
                        if ankiManager.ankiConnectConfig?.url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                            ankiManager.ankiConnectConfig?.url = "http://127.0.0.1:8765"
                        }
                        ankiManager.save()
                        ankiManager.handleAppBecameActive()
                    } label: {
                        Text("Connect", tableName: "Dictionaries")
                    }
                    Text("Status: \(connectionStatus)", tableName: "Dictionaries")
                        .foregroundStyle(.secondary)
                }
            }

            if ankiManager.isConnected {
                NativeSettingsSectionCard {
                    Text("Refresh", tableName: "Dictionaries")
                } content: {
                    NativeSettingsButtonRow {
                        Button {
                            confirmFetch = true
                        } label: {
                            Text("Fetch decks and models from AnkiConnect")
                        }
                    }
                } footer: {
                    Text("Fetching refreshes decks and models while preserving mappings for fields that still exist.")
                }

                NativeSettingsSectionCard {
                    Text("AnkiConnect Settings")
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
                    ankiConfigToggle(
                        title: "Check All Models",
                        value: ankiManager.ankiConnectConfig?.checkAllModels ?? false
                    ) { value in
                        ankiManager.ankiConnectConfig?.checkAllModels = value
                        ankiManager.save()
                    }
                    NativeSettingsSeparator()
                    ankiConfigToggle(
                        title: "Force Sync on adding card",
                        value: ankiManager.ankiConnectConfig?.forceSync ?? false
                    ) { value in
                        ankiManager.ankiConnectConfig?.forceSync = value
                        ankiManager.save()
                    }
                }

                NativeSettingsSectionCard {
                    Text("Config", tableName: "Dictionaries")
                } content: {
                    NativeSettingsRow {
                        Text("Deck", tableName: "Dictionaries")
                    } accessory: {
                        NativeGlassMenuPicker(
                            selection: $ankiManager.selectedDeck,
                            values: ankiManager.availableDecks.map(Optional.some),
                            minWidth: 160
                        ) { deck in
                            if let deck {
                                Text(verbatim: deck)
                            } else {
                                Text("Deck", tableName: "Dictionaries")
                            }
                        }
                        .onChange(of: ankiManager.selectedDeck) { _, _ in ankiManager.save() }
                    }
                    NativeSettingsSeparator()
                    NativeSettingsRow {
                        Text("Model", tableName: "Dictionaries")
                    } accessory: {
                        NativeGlassMenuPicker(
                            selection: $ankiManager.selectedNoteType,
                            values: ankiManager.availableNoteTypes.map { Optional.some($0.name) },
                            minWidth: 160
                        ) { noteType in
                            if let noteType {
                                Text(verbatim: noteType)
                            } else {
                                Text("Model", tableName: "Dictionaries")
                            }
                        }
                        .onChange(of: ankiManager.selectedNoteType) { _, _ in
                            ankiManager.autofillFieldMappings()
                            ankiManager.save()
                        }
                    }
                }

                NativeSettingsSectionCard {
                    Text("Settings", tableName: "Dictionaries")
                } content: {
                    NativeSettingsToggle("Allow Duplicates", isOn: $ankiManager.allowDupes)
                        .onChange(of: ankiManager.allowDupes) { _, _ in ankiManager.save() }
                    NativeSettingsSeparator()
                    NativeSettingsToggle("Compact Glossaries", isOn: $ankiManager.compactGlossaries)
                        .onChange(of: ankiManager.compactGlossaries) { _, _ in ankiManager.save() }
                } footer: {
                    Text("On Mac, duplicate checks and card creation are performed through AnkiConnect.")
                }
            }

            if ankiManager.isConnected,
               let typeName = ankiManager.selectedNoteType,
               let noteType = ankiManager.availableNoteTypes.first(where: { $0.name == typeName }) {
                NativeSettingsSectionCard {
                    Text("Fields", tableName: "Dictionaries")
                } content: {
                    if AnkiFieldTemplate.hasDefaults(noteType: typeName) {
                        NativeSettingsButtonRow {
                            Button {
                                pendingDefaultsPreset = .novel
                            } label: {
                                Text("Apply Novel Defaults", tableName: "Dictionaries")
                            }
                        }
                        NativeSettingsSeparator()
                        NativeSettingsButtonRow {
                            Button {
                                pendingDefaultsPreset = .anime
                            } label: {
                                Text("Apply Anime Defaults", tableName: "Dictionaries")
                            }
                        }
                        NativeSettingsSeparator()
                    }

                    ForEach(Array(noteType.fields.enumerated()), id: \.element) { index, field in
                        if index > 0 {
                            NativeSettingsSeparator()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: field)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            HStack {
                                TextField(text: Binding(
                                    get: { ankiManager.fieldMappings[field] ?? "" },
                                    set: { value in
                                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if trimmed.isEmpty {
                                            ankiManager.fieldMappings.removeValue(forKey: field)
                                        } else {
                                            ankiManager.fieldMappings[field] = value
                                        }
                                    }
                                ), prompt: Text("None", tableName: "Dictionaries")) {
                                    Text("None", tableName: "Dictionaries")
                                }
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.done)
                                .onSubmit {
                                    ankiManager.save()
                                }

                                Menu {
                                    Button {
                                        ankiManager.fieldMappings.removeValue(forKey: field)
                                        ankiManager.save()
                                    } label: {
                                        Text(verbatim: "-")
                                    }
                                    Divider()
                                    ForEach(availableHandlebars, id: \.self) { option in
                                        Button {
                                            ankiManager.fieldMappings[field] = option
                                            ankiManager.save()
                                        } label: {
                                            Text(verbatim: option)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "chevron.up.chevron.down")
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    NativeSettingsSeparator()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tags", tableName: "Dictionaries")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        TextField(text: $ankiManager.tags, prompt: Text("None", tableName: "Dictionaries")) {
                            Text("None", tableName: "Dictionaries")
                        }
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit {
                            ankiManager.save()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .navigationTitle(String(localized: "Anki", table: "Dictionaries"))
        .onAppear {
            ankiManager.handleAppBecameActive()
        }
        .onDisappear { ankiManager.save() }
        .alert(String(localized: "Fetch from Anki?", table: "Dictionaries"), isPresented: $confirmFetch) {
            Button {
                Task { await ankiManager.fetchAnkiConnect() }
            } label: {
                Text("OK", tableName: "Dictionaries")
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", tableName: "Dictionaries")
            }
        } message: {
            Text("This will refresh decks and models while preserving mappings for fields that still exist.")
        }
        .alert(defaultsConfirmationTitle, isPresented: defaultsConfirmationBinding) {
            Button {
                guard let preset = pendingDefaultsPreset else { return }
                if ankiManager.applyDefaultFieldMappings(preset: preset) {
                    ankiManager.save()
                }
                pendingDefaultsPreset = nil
            } label: {
                Text("Apply", tableName: "Dictionaries")
            }
            Button(role: .cancel) {
                pendingDefaultsPreset = nil
            } label: {
                Text("Cancel", tableName: "Dictionaries")
            }
        } message: {
            Text(
                "This replaces mappings for fields defined by the selected note type. Other fields are preserved.",
                tableName: "Dictionaries"
            )
        }
        .alert(String(localized: "Error", table: "Dictionaries"), isPresented: .init(
            get: { ankiManager.errorMessage != nil },
            set: { if !$0 { ankiManager.errorMessage = nil } }
        )) {
            Button {
                ankiManager.errorMessage = nil
            } label: {
                Text("OK", tableName: "Dictionaries")
            }
        } message: {
            Text(verbatim: ankiManager.errorMessage ?? "")
        }
    }

    private var defaultsConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDefaultsPreset != nil },
            set: { if !$0 { pendingDefaultsPreset = nil } }
        )
    }

    private var defaultsConfirmationTitle: String {
        switch pendingDefaultsPreset {
        case .anime:
            String(localized: "Apply anime defaults?", table: "Dictionaries")
        case .novel, nil:
            String(localized: "Apply novel defaults?", table: "Dictionaries")
        }
    }

    private func ankiConfigToggle(
        title: LocalizedStringKey,
        value: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        NativeSettingsRow(title) {
            Toggle("", isOn: Binding(
                get: { value },
                set: { newValue in onChange(newValue) }
            ))
                .labelsHidden()
        }
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
