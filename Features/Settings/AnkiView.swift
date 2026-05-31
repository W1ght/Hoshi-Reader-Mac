//
//  AnkiView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

struct AnkiView: View {
    @State private var ankiManager = AnkiManager.shared
    @State private var dictionaryManager = DictionaryManager.shared
    @State private var isImporting = false
    @State private var confirmFetch = false

    private var prefersAnkiConnect: Bool {
        AppPlatform.usesDesktopLayout || ankiManager.useAnkiConnect
    }

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
            .map(\.rawValue)
        for dict in dictionaryManager.termDictionaries {
            options.append("\(Handlebars.singleGlossaryPrefix)\(dict.index.title)}")
        }
        return options
    }

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

            if prefersAnkiConnect {
                Section {
                    TextField(text: Binding(
                        get: { ankiManager.ankiConnectConfig?.url ?? "http://127.0.0.1:8765" },
                        set: { ankiManager.ankiConnectConfig?.url = $0 }
                    ), prompt: Text("Address", tableName: "Dictionaries")) {
                        Text("Address", tableName: "Dictionaries")
                    }
                    .onSubmit { ankiManager.save() }

                    Button {
                        if ankiManager.ankiConnectConfig?.url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                            ankiManager.ankiConnectConfig?.url = "http://127.0.0.1:8765"
                        }
                        ankiManager.save()
                        ankiManager.handleAppBecameActive()
                    } label: {
                        Text("Connect", tableName: "Dictionaries")
                    }
                } header: {
                    Text("Connection", tableName: "Dictionaries")
                } footer: {
                    Text("Status: \(connectionStatus)", tableName: "Dictionaries")
                }
            }

            if !prefersAnkiConnect || ankiManager.isConnected {
                Section {
                    Button {
                        confirmFetch = true
                    } label: {
                        if prefersAnkiConnect {
                            Text("Fetch decks and models from AnkiConnect")
                        } else {
                            Text("Fetch decks and models from Anki", tableName: "Dictionaries")
                        }
                    }
                } footer: {
                    if !ankiManager.isConnected {
                        Text(AppPlatform.usesDesktopLayout ? "Connect to AnkiConnect before configuring decks, models, and fields." : "AnkiMobile or a hosted AnkiConnect instance is required to mine words.")
                    } else {
                        Text("Fetching refreshes decks and models while preserving mappings for fields that still exist.")
                    }
                }
            }

            if ankiManager.isConnected {
                if prefersAnkiConnect {
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
                        Text("AnkiConnect Settings")
                    }
                }

                Section {
                    Picker(selection: $ankiManager.selectedDeck) {
                        ForEach(ankiManager.availableDecks, id: \.self) { deck in
                            Text(verbatim: deck).tag(deck as String?)
                        }
                    } label: {
                        Text("Deck", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.selectedDeck) { _, _ in ankiManager.save() }

                    Picker(selection: $ankiManager.selectedNoteType) {
                        ForEach(ankiManager.availableNoteTypes) { noteType in
                            Text(verbatim: noteType.name).tag(noteType.name as String?)
                        }
                    } label: {
                        Text("Model", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.selectedNoteType) { _, _ in ankiManager.save() }

                    if !ankiManager.useAnkiConnect {
                        Button {
                            isImporting = true
                        } label: {
                            Text("Import Anki Backup (Stored Words: \(ankiManager.savedWords.count.formatted(.number.grouping(.never))))", tableName: "Dictionaries")
                        }
                    }
                } header: {
                    Text("Config", tableName: "Dictionaries")
                } footer: {
                    if !ankiManager.useAnkiConnect {
                        Text("Importing a .colpkg/.apkg backup from Anki will allow Hoshi Reader to check for duplicates immediately. It's recommended to do this periodically to reduce drift.", tableName: "Dictionaries")
                    }
                }

                Section {
                    Toggle(isOn: $ankiManager.allowDupes) {
                        Text("Allow Duplicates", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.allowDupes) { _, _ in ankiManager.save() }

                    Toggle(isOn: $ankiManager.compactGlossaries) {
                        Text("Compact Glossaries", tableName: "Dictionaries")
                    }
                    .onChange(of: ankiManager.compactGlossaries) { _, _ in ankiManager.save() }

                    if !prefersAnkiConnect {
                        VStack {
                            Toggle(String(localized: "Embed Dictionary Media", table: "Dictionaries"), isOn: $ankiManager.embedMedia)
                                .onChange(of: ankiManager.embedMedia) { _, _ in ankiManager.save() }
                            Text("Embedding media will increase size of glossaries (AnkiMobile).", tableName: "Dictionaries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } header: {
                    Text("Settings", tableName: "Dictionaries")
                } footer: {
                    if AppPlatform.usesDesktopLayout {
                        Text("On Mac, duplicate checks and card creation are performed through AnkiConnect.")
                    }
                }
            }

            if ankiManager.isConnected,
               let typeName = ankiManager.selectedNoteType,
               let noteType = ankiManager.availableNoteTypes.first(where: { $0.name == typeName }) {
                Section {
                    ForEach(noteType.fields, id: \.self) { field in
                        VStack(alignment: .leading, spacing: 3) {
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
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tags", tableName: "Dictionaries")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        TextField(text: $ankiManager.tags, prompt: Text("None", tableName: "Dictionaries")) {
                            Text("None", tableName: "Dictionaries")
                        }
                        .submitLabel(.done)
                        .onSubmit {
                            ankiManager.save()
                        }
                    }
                } header: {
                    Text("Fields", tableName: "Dictionaries")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: ["colpkg", "apkg"].map { UTType(filenameExtension: $0)! }
        ) { result in
            if case .success(let url) = result {
                do {
                    try ankiManager.importAnkiBackup(from: url)
                } catch {
                    ankiManager.errorMessage = error.localizedDescription
                }
            }
        }
        .navigationTitle(String(localized: "Anki", table: "Dictionaries"))
        .onAppear {
            if prefersAnkiConnect {
                ankiManager.handleAppBecameActive()
            }
        }
        .onDisappear { ankiManager.save() }
        .alert(String(localized: "Fetch from Anki?", table: "Dictionaries"), isPresented: $confirmFetch) {
            Button {
                if prefersAnkiConnect {
                    Task { await ankiManager.fetchAnkiConnect() }
                } else {
                    ankiManager.requestInfo()
                }
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

    private var connectionStatus: String {
        if ankiManager.isConnected {
            String(localized: "Connected", table: "Dictionaries")
        } else {
            String(localized: "Not connected", table: "Dictionaries")
        }
    }
}
