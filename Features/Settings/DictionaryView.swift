//
//  DictionaryView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import UniformTypeIdentifiers
import SwiftUI

struct DictionaryView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var dictionaryManager = DictionaryManager.shared
    @State private var isImporting = false
    @State private var showCSSEditor = false
    @State private var showDownloadConfirmation = false
    @State private var showUpdateConfirmation = false
    @State private var selectedType: DictionaryType = .term

    private var dictionaries: [DictionaryInfo] {
        switch selectedType {
        case .term: return dictionaryManager.termDictionaries
        case .frequency: return dictionaryManager.frequencyDictionaries
        case .pitch: return dictionaryManager.pitchDictionaries
        }
    }

    private var lastUpdate: String {
        guard let date = UserDefaults.standard.object(forKey: "lastDictionaryUpdate") as? Date else {
            return String(localized: "Never", table: "Dictionaries")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func dictionaryUpdateIntervalText(_ interval: DictionaryUpdateInterval) -> Text {
        switch interval {
        case .daily:
            Text("Daily", tableName: "Dictionaries")
        case .weekly:
            Text("Weekly", tableName: "Dictionaries")
        case .monthly:
            Text("Monthly", tableName: "Dictionaries")
        }
    }

    var body: some View {
        @Bindable var userConfig = userConfig
        NativeSettingsForm {
            NativeSettingsSectionCard {
                Text("Dictionaries", tableName: "Dictionaries")
            } content: {
                NativeSettingsButtonRow {
                    Button {
                        showDownloadConfirmation = true
                    } label: {
                        Text("Download Recommended Dictionaries", tableName: "Dictionaries")
                    }
                    .disabled(dictionaryManager.isImporting)
                }
                NativeSettingsSeparator()
                NativeSettingsRow {
                    Text("Supported Formats", tableName: "Dictionaries")
                } accessory: {
                    Text("Yomitan term, frequency and pitch dictionaries (.zip) are supported", tableName: "Dictionaries")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }

            if dictionaryManager.updatableDictionaries.count > 0 {
                NativeSettingsSectionCard {
                    Text("Updates", tableName: "Dictionaries")
                } content: {
                    NativeSettingsToggle(
                        "Update Automatically",
                        isOn: $userConfig.autoUpdateDictionaries
                    )
                    if userConfig.autoUpdateDictionaries {
                        NativeSettingsSeparator()
                        NativeSettingsRow {
                            Text("Interval", tableName: "Dictionaries")
                        } accessory: {
                            NativeGlassSegmentedPicker(
                                selection: $userConfig.dictionaryUpdateInterval,
                                values: DictionaryUpdateInterval.allCases,
                                minSegmentWidth: 66
                            ) { interval in
                                dictionaryUpdateIntervalText(interval)
                            }
                        }
                    }
                    NativeSettingsSeparator()
                    NativeSettingsRow {
                        Text("Last Update", tableName: "Dictionaries")
                    } accessory: {
                        Text(verbatim: lastUpdate)
                            .foregroundStyle(.secondary)
                    }
                    NativeSettingsSeparator()
                    NativeSettingsButtonRow {
                        Button {
                            showUpdateConfirmation = true
                        } label: {
                            Text("Update Dictionaries", tableName: "Dictionaries")
                        }
                    }
                }
            }

            NativeSettingsSectionCard("Settings") {
                NativeSettingsToggle(
                    "Default to Dictionary Tab",
                    isOn: $userConfig.dictionaryTabDefault
                )
                NativeSettingsSeparator()
                NativeSettingsButtonRow {
                    NavigationLink {
                        DictionarySettingsView()
                    } label: {
                        Text("Settings", tableName: "Dictionaries")
                    }
                }
            }

            NativeSettingsSectionCard {
                HStack {
                    Text("Dictionaries", tableName: "Dictionaries")
                    Spacer()
                    dictionaryTypePicker
                }
            } content: {
                ForEach(Array(dictionaries.enumerated()), id: \.element.id) { index, dict in
                    if index > 0 {
                        NativeSettingsSeparator()
                    }
                    NativeSettingsRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: dict.index.title)
                            Text(verbatim: dict.index.revision)
                                .lineLimit(1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } accessory: {
                        Toggle("", isOn: Binding(
                            get: { dict.isEnabled },
                            set: { dictionaryManager.toggleDictionary(id: dict.id, enabled: $0, type: selectedType) }
                        ))
                        .labelsHidden()
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteDictionary(dict)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCSSEditor) {
            DictionaryDetailSettingView()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showCSSEditor = true
                } label: {
                    Image(systemName: "curlybraces")
                }
                .disabled(dictionaryManager.isImporting || dictionaryManager.isUpdating)
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "plus")
                }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.zip],
                    allowsMultipleSelection: true,
                    onCompletion: { result in
                        if case .success(let urls) = result {
                            dictionaryManager.importDictionary(from: urls)
                        }
                    }
                )
                .disabled(dictionaryManager.isImporting || dictionaryManager.isUpdating)
            }
        }
        .overlay {
            if dictionaryManager.isImporting || dictionaryManager.isUpdating {
                LoadingOverlay(dictionaryManager.currentImport)
            }
        }
        .navigationTitle(String(localized: "Dictionaries", table: "Dictionaries"))
        .alert(String(localized: "Download Dictionaries", table: "Dictionaries"), isPresented: $showDownloadConfirmation) {
            Button {
                dictionaryManager.importRecommendedDictionaries()
            } label: {
                Text("Download", tableName: "Dictionaries")
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", tableName: "Dictionaries")
            }
        } message: {
            Text("This will download the latest version of the following dictionaries (33 MB):\nJMdict (Term)\nJMnedict (Term)\nJiten (Frequency)", tableName: "Dictionaries")
        }
        .alert(String(localized: "Update Dictionaries", table: "Dictionaries"), isPresented: $showUpdateConfirmation) {
            Button {
                dictionaryManager.updateDictionaries()
            } label: {
                Text("Update", tableName: "Dictionaries")
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", tableName: "Dictionaries")
            }
        } message: {
            Text("This will check for and install updates for these dictionaries:\n\(dictionaryManager.updatableDictionaries.map(\.0.index.title).joined(separator: "\n"))", tableName: "Dictionaries")
        }
        .alert(String(localized: "Error", table: "Dictionaries"), isPresented: $dictionaryManager.shouldShowError) {
            Button(role: .cancel) {
            } label: {
                Text("OK", tableName: "Dictionaries")
            }
        } message: {
            Text(verbatim: dictionaryManager.errorMessage)
        }
    }

    private func deleteDictionary(_ dictionary: DictionaryInfo) {
        guard let index = dictionaries.firstIndex(where: { $0.id == dictionary.id }) else {
            return
        }
        dictionaryManager.deleteDictionary(indexSet: IndexSet(integer: index), type: selectedType)
    }

    @ViewBuilder
    private var dictionaryListHeader: some View {
        #if os(macOS)
        Text("Dictionaries", tableName: "Dictionaries")
        #else
        dictionaryTypePicker
            .listRowInsets(EdgeInsets())
            .padding(.bottom, 12)
        #endif
    }

    private var dictionaryTypePicker: some View {
        NativeGlassSegmentedPicker(
            selection: $selectedType,
            values: [DictionaryType.term, .frequency, .pitch],
            minSegmentWidth: 72
        ) { type in
            switch type {
            case .term:
                Text("Term", tableName: "Dictionaries")
            case .frequency:
                Text("Frequency", tableName: "Dictionaries")
            case .pitch:
                Text("Pitch", tableName: "Dictionaries")
            }
        }
    }
}

struct DictionarySettingsView: View {
    @Environment(UserConfig.self) private var userConfig

    var body: some View {
        @Bindable var userConfig = userConfig
        NativeSettingsForm {
            NativeSettingsSectionCard {
                Text("Lookup", tableName: "Dictionaries")
            } content: {
                NativeSettingsToggle(
                    "Scan Non-Japanese Text",
                    isOn: $userConfig.scanNonJapaneseText
                )
                NativeSettingsSeparator()
                NativeSettingsRow {
                    Text("Max Results", tableName: "Dictionaries")
                } accessory: {
                    Text(verbatim: "\(userConfig.maxResults)")
                        .fontWeight(.semibold)
                    Stepper(value: $userConfig.maxResults, in: 1...50) {
                        Text("Max Results", tableName: "Dictionaries")
                    }
                    .labelsHidden()
                }
                NativeSettingsSeparator()
                NativeSettingsRow {
                    Text("Scan Length", tableName: "Dictionaries")
                } accessory: {
                    Text(verbatim: "\(userConfig.scanLength)")
                        .fontWeight(.semibold)
                    Stepper(value: $userConfig.scanLength, in: 1...64) {
                        Text("Scan Length", tableName: "Dictionaries")
                    }
                    .labelsHidden()
                }
            }

            NativeSettingsSectionCard {
                Text("Collapse Dictionaries", tableName: "Dictionaries")
            } content: {
                NativeSettingsRow {
                    Text("Mode", tableName: "Dictionaries")
                } accessory: {
                    NativeGlassSegmentedPicker(
                        selection: $userConfig.collapseMode,
                        values: CollapseMode.allCases,
                        minSegmentWidth: 82
                    ) { mode in
                        collapseModeText(mode)
                    }
                }
                if userConfig.collapseMode != .expandAll {
                    NativeSettingsSeparator()
                    NativeSettingsToggle(
                        "Expand First Dictionary",
                        isOn: $userConfig.expandFirstDictionary
                    )
                }
                if userConfig.collapseMode == .custom {
                    NativeSettingsSeparator()
                    NativeSettingsButtonRow {
                        NavigationLink {
                            CollapsedDictionariesView()
                        } label: {
                            Text("Configure", tableName: "Dictionaries")
                        }
                    }
                }
            }

            NativeSettingsSectionCard {
                Text("Behaviour", tableName: "Dictionaries")
            } content: {
                NativeSettingsToggle("Compact Glossaries", isOn: $userConfig.compactGlossaries)
                NativeSettingsSeparator()
                NativeSettingsToggle("Show Expression Tags", isOn: $userConfig.showExpressionTags)
                NativeSettingsSeparator()
                NativeSettingsToggle("Harmonic Frequency", isOn: $userConfig.harmonicFrequency)
                NativeSettingsSeparator()
                NativeSettingsToggle("Deduplicate Pitch Accents", isOn: $userConfig.deduplicatePitchAccents)
                NativeSettingsSeparator()
                NativeSettingsToggle("Compact Pitch Accents", isOn: $userConfig.compactPitchAccents)
                NativeSettingsSeparator()
                NativeSettingsSliderRow(
                    title: "Mac Hover Delay",
                    value: "\(userConfig.desktopLookupHoverDelayMs) ms"
                ) {
                    Slider(value: .init(
                        get: { Double(userConfig.desktopLookupHoverDelayMs) },
                        set: { userConfig.desktopLookupHoverDelayMs = Int($0) }
                    ), in: 0...250, step: 5)
                }
            }
        }
        .navigationTitle(String(localized: "Settings", table: "Dictionaries"))
        .inlineNavigationTitleIfAvailable()
    }

    private func collapseModeText(_ mode: CollapseMode) -> Text {
        switch mode {
        case .expandAll:
            Text("Expand All", tableName: "Dictionaries")
        case .collapseAll:
            Text("Collapse All", tableName: "Dictionaries")
        case .custom:
            Text("Custom", tableName: "Dictionaries")
        }
    }
}

struct CollapsedDictionariesView: View {
    @State private var dictionaryManager = DictionaryManager.shared

    var body: some View {
        NativeSettingsForm {
            NativeSettingsSectionCard {
                Text("Collapse Dictionaries", tableName: "Dictionaries")
            } content: {
                ForEach(Array(dictionaryManager.termDictionaries.enumerated()), id: \.element.id) { index, dict in
                    if index > 0 {
                        NativeSettingsSeparator()
                    }
                    Button {
                        dictionaryManager.toggleCollapsedDictionary(title: dict.index.title)
                    } label: {
                        HStack {
                            Image(systemName: dictionaryManager.collapsedDictionaries.contains(dict.index.title) ? "chevron.right" : "chevron.down")
                                .foregroundStyle(dictionaryManager.collapsedDictionaries.contains(dict.index.title) ? .secondary : .primary)
                                .frame(width: 16)
                            Text(verbatim: dict.index.title)
                            Spacer()
                        }
                        .frame(minHeight: 46)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(String(localized: "Collapse Dictionaries", table: "Dictionaries"))
        .inlineNavigationTitleIfAvailable()
    }
}

struct DictionaryDetailSettingView: View {
    @Environment(UserConfig.self) var userConfig
    @Environment(\.dismiss) private var dismiss
    @State private var customCSS: String = ""

    var body: some View {
        NavigationStack {
            CSSEditorView(text: $customCSS)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                #if os(macOS)
                .background(Color(nsColor: .underPageBackgroundColor).ignoresSafeArea())
                #else
                .background(Color(.secondarySystemBackground).ignoresSafeArea())
                #endif
                .navigationTitle(String(localized: "Custom CSS", table: "Dictionaries"))
                .inlineNavigationTitleIfAvailable()
                .toolbar {
                    #if os(macOS)
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .destructive) {
                            customCSS = ""
                        } label: {
                            Text("Reset", tableName: "Dictionaries")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    #else
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .destructive) {
                            customCSS = ""
                        } label: {
                            Text("Reset", tableName: "Dictionaries")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    #endif
                }
        }
        .onAppear {
            customCSS = userConfig.customCSS
        }
        .onDisappear {
            userConfig.customCSS = customCSS
        }
    }
}
