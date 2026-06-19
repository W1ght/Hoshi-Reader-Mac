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
                        Picker(selection: $ankiManager.selectedDeck) {
                            ForEach(ankiManager.availableDecks, id: \.self) { deck in
                                Text(verbatim: deck).tag(deck as String?)
                            }
                        } label: {
                            Text("Deck", tableName: "Dictionaries")
                        }
                        .labelsHidden()
                        .onChange(of: ankiManager.selectedDeck) { _, _ in ankiManager.save() }
                    }
                    NativeSettingsSeparator()
                    NativeSettingsRow {
                        Text("Model", tableName: "Dictionaries")
                    } accessory: {
                        Picker(selection: $ankiManager.selectedNoteType) {
                            ForEach(ankiManager.availableNoteTypes) { noteType in
                                Text(verbatim: noteType.name).tag(noteType.name as String?)
                            }
                        } label: {
                            Text("Model", tableName: "Dictionaries")
                        }
                        .labelsHidden()
                        .onChange(of: ankiManager.selectedNoteType) { _, _ in ankiManager.save() }
                    }
                }

                if isVideoBuild {
                    videoAnimeCardSection
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

    @ViewBuilder
    private var videoAnimeCardSection: some View {
        NativeSettingsSectionCard {
            Text("Anime Card Fields", tableName: "Dictionaries")
        } content: {
            NativeSettingsButtonRow {
                Button {
                    applyAnimeCardPreset()
                } label: {
                    Text("Apply Anime Card Preset", tableName: "Dictionaries")
                }
                .disabled(selectedNoteFields.isEmpty)
            }
            NativeSettingsSeparator()
            ForEach(videoFieldHints, id: \.handlebar) { hint in
                NativeSettingsRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hint.title, tableName: "Dictionaries")
                        Text(verbatim: hint.handlebar)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } accessory: {
                    Text(hint.detail, tableName: "Dictionaries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 260, alignment: .trailing)
                }
            }
        } footer: {
            Text("Video mining captures the current frame and the selected subtitle time range when you press Add to Anki. Map image and audio fields to the video placeholders to send those files to AnkiConnect.")
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

    private var selectedNoteFields: [String] {
        guard let typeName = ankiManager.selectedNoteType,
              let noteType = ankiManager.availableNoteTypes.first(where: { $0.name == typeName }) else {
            return []
        }
        return noteType.fields
    }

    private var videoFieldHints: [(title: LocalizedStringKey, handlebar: String, detail: LocalizedStringKey)] {
        [
            ("Word", Handlebars.expression.rawValue, "Dictionary expression"),
            ("Reading", Handlebars.reading.rawValue, "Dictionary reading"),
            ("Sentence", Handlebars.videoSubtitle.rawValue, "Current subtitle line"),
            ("Meaning", Handlebars.glossary.rawValue, "Dictionary definitions"),
            ("Audio", Handlebars.videoAudioClip.rawValue, "Subtitle audio clip"),
            ("Image", Handlebars.videoScreenshot.rawValue, "Current video frame"),
            ("Source", Handlebars.videoFileName.rawValue, "Video file name"),
            ("Timestamp", Handlebars.videoTimestamp.rawValue, "Cue start time")
        ]
    }

    private func applyAnimeCardPreset() {
        var mappings = ankiManager.fieldMappings
        for field in selectedNoteFields {
            guard let handlebar = animeCardHandlebar(for: field) else { continue }
            mappings[field] = handlebar.rawValue
        }
        ankiManager.fieldMappings = mappings
        ankiManager.save()
    }

    private func animeCardHandlebar(for field: String) -> Handlebars? {
        let normalized = field
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        if matches(normalized, ["expression", "word", "term", "vocab", "front"]) {
            return .expression
        }
        if matches(normalized, ["reading", "kana", "yomi", "pronunciation"]) {
            return .reading
        }
        if matches(normalized, ["sentence", "context", "line", "subtitle", "quote", "example"]) {
            return .videoSubtitle
        }
        if matches(normalized, ["meaning", "glossary", "definition", "definitions", "back"]) {
            return .glossary
        }
        if matches(normalized, ["audio", "sound", "sentenceaudio", "clozeaudio"]) {
            return .videoAudioClip
        }
        if matches(normalized, ["image", "picture", "screenshot", "snapshot", "frame"]) {
            return .videoScreenshot
        }
        if matches(normalized, ["source", "title", "filename", "file", "video"]) {
            return .videoFileName
        }
        if matches(normalized, ["timestamp", "time", "cue", "start"]) {
            return .videoTimestamp
        }
        return nil
    }

    private func matches(_ normalized: String, _ candidates: [String]) -> Bool {
        candidates.contains { normalized.contains($0) }
    }
}
