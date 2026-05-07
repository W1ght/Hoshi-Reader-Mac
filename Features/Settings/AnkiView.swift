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
        var options = Handlebars.allCases.map(\.rawValue)
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
                    Toggle("Use AnkiConnect", isOn: $ankiManager.useAnkiConnect)
                        .onChange(of: ankiManager.useAnkiConnect) { _, _ in ankiManager.save() }
                }
            } footer: {
                Text(AppPlatform.usesDesktopLayout ? "The iOS AnkiMobile callback flow is not available on Mac." : "This will replace AnkiMobile callbacks with AnkiConnect requests.")
            }

            if prefersAnkiConnect {
                Section {
                    TextField("Address", text: Binding(
                        get: { ankiManager.ankiConnectConfig?.url ?? "http://127.0.0.1:8765" },
                        set: { ankiManager.ankiConnectConfig?.url = $0 }
                    ))
                    .onSubmit { ankiManager.save() }

                    Button("Connect") {
                        if ankiManager.ankiConnectConfig?.url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                            ankiManager.ankiConnectConfig?.url = "http://127.0.0.1:8765"
                        }
                        ankiManager.save()
                        ankiManager.handleAppBecameActive()
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Status: \(ankiManager.isConnected ? String(localized: "Connected") : String(localized: "Not connected"))")
                }
            }

            if !prefersAnkiConnect || ankiManager.isConnected {
                Section {
                    Button(prefersAnkiConnect ? "Fetch decks and models from AnkiConnect" : "Fetch decks and models from Anki") {
                        confirmFetch = true
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
                    Section("AnkiConnect Settings") {
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

                Section {
                    Picker("Deck", selection: $ankiManager.selectedDeck) {
                        ForEach(ankiManager.availableDecks, id: \.self) { deck in
                            Text(deck).tag(deck as String?)
                        }
                    }
                    .onChange(of: ankiManager.selectedDeck) { _, _ in ankiManager.save() }

                    Picker("Model", selection: $ankiManager.selectedNoteType) {
                        ForEach(ankiManager.availableNoteTypes) { noteType in
                            Text(noteType.name).tag(noteType.name as String?)
                        }
                    }
                    .onChange(of: ankiManager.selectedNoteType) { _, _ in ankiManager.save() }

                    if !ankiManager.useAnkiConnect {
                        Button("Import Anki Backup (Stored Words: \(ankiManager.savedWords.count.formatted(.number.grouping(.never))))") {
                            isImporting = true
                        }
                    }
                } header: {
                    Text("Config");
                } footer: {
                    if !ankiManager.useAnkiConnect {
                        Text("Importing a .colpkg/.apkg backup from Anki will allow Hoshi Reader to check for duplicates immediately. It's recommended to do this periodically to reduce drift.")
                    }
                }

                Section {
                    Toggle("Allow Duplicates", isOn: $ankiManager.allowDupes)
                        .onChange(of: ankiManager.allowDupes) { _, _ in ankiManager.save() }

                    Toggle("Compact Glossaries", isOn: $ankiManager.compactGlossaries)
                        .onChange(of: ankiManager.compactGlossaries) { _, _ in ankiManager.save() }

                    if !prefersAnkiConnect {
                        Toggle("Embed Dictionary Media", isOn: $ankiManager.embedMedia)
                            .onChange(of: ankiManager.embedMedia) { _, _ in ankiManager.save() }
                    }
                } header: {
                    Text("Settings")
                } footer: {
                    if !prefersAnkiConnect {
                        Text("Embedding media will increase size of glossaries (AnkiMobile).")
                    } else if AppPlatform.usesDesktopLayout {
                        Text("On Mac, duplicate checks and card creation are performed through AnkiConnect.")
                    }
                }
            }

            if ankiManager.isConnected,
               let typeName = ankiManager.selectedNoteType,
               let noteType = ankiManager.availableNoteTypes.first(where: { $0.name == typeName }) {
                Section("Fields") {
                    ForEach(noteType.fields, id: \.self) { field in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(field)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            HStack {
                                TextField("None", text: Binding(
                                    get: { ankiManager.fieldMappings[field] ?? "" },
                                    set: { value in
                                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if trimmed.isEmpty {
                                            ankiManager.fieldMappings.removeValue(forKey: field)
                                        } else {
                                            ankiManager.fieldMappings[field] = value
                                        }
                                    }
                                ))
                                .submitLabel(.done)
                                .onSubmit {
                                    ankiManager.save()
                                }

                                Menu {
                                    Button("-") {
                                        ankiManager.fieldMappings.removeValue(forKey: field)
                                        ankiManager.save()
                                    }
                                    Divider()
                                    ForEach(availableHandlebars, id: \.self) { option in
                                        Button(option) {
                                            ankiManager.fieldMappings[field] = option
                                            ankiManager.save()
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
                        Text("Tags")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        TextField("None", text: $ankiManager.tags)
                            .submitLabel(.done)
                            .onSubmit {
                                ankiManager.save()
                            }
                    }
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
        .navigationTitle("Anki")
        .onAppear {
            if prefersAnkiConnect {
                ankiManager.handleAppBecameActive()
            }
        }
        .onDisappear { ankiManager.save() }
        .alert("Fetch from Anki?", isPresented: $confirmFetch) {
            Button("OK") {
                if prefersAnkiConnect {
                    Task { await ankiManager.fetchAnkiConnect() }
                } else {
                    ankiManager.requestInfo()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will refresh decks and models while preserving mappings for fields that still exist.")
        }
        .alert("Error", isPresented: .init(
            get: { ankiManager.errorMessage != nil },
            set: { if !$0 { ankiManager.errorMessage = nil } }
        )) {
            Button("OK") { ankiManager.errorMessage = nil }
        } message: {
            Text(ankiManager.errorMessage ?? "")
        }
    }
}
