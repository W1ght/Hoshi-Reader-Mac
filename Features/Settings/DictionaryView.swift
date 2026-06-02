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
        List {
            Section {
                Button {
                    showDownloadConfirmation = true
                } label: {
                    Text("Download Recommended Dictionaries", tableName: "Dictionaries")
                }
                .disabled(dictionaryManager.isImporting)
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
            } footer: {
                Text("Yomitan term, frequency and pitch dictionaries (.zip) are supported", tableName: "Dictionaries")
            }

            if dictionaryManager.updatableDictionaries.count > 0 {
                Section {
                    Toggle(isOn: $userConfig.autoUpdateDictionaries) {
                        Text("Update Automatically", tableName: "Dictionaries")
                    }
                    if userConfig.autoUpdateDictionaries {
                        Picker(selection: $userConfig.dictionaryUpdateInterval) {
                            ForEach(DictionaryUpdateInterval.allCases, id: \.self) { interval in
                                dictionaryUpdateIntervalText(interval).tag(interval)
                            }
                        } label: {
                            Text("Interval", tableName: "Dictionaries")
                        }
                    }
                    LabeledContent {
                        Text(verbatim: lastUpdate)
                    } label: {
                        Text("Last Update", tableName: "Dictionaries")
                    }
                    Button {
                        showUpdateConfirmation = true
                    } label: {
                        Text("Update Dictionaries", tableName: "Dictionaries")
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
                } header: {
                    Text("Updates", tableName: "Dictionaries")
                }
            }

            Section {
                Toggle(isOn: $userConfig.dictionaryTabDefault) {
                    Text("Default to Dictionary Tab", tableName: "Dictionaries")
                }
                NavigationLink {
                    DictionarySettingsView()
                } label: {
                    Text("Settings", tableName: "Dictionaries")
                }
            }

            Section {
                ForEach(dictionaries) { dict in
                    Toggle(isOn: Binding(
                        get: { dict.isEnabled },
                        set: { dictionaryManager.toggleDictionary(id: dict.id, enabled: $0, type: selectedType) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: dict.index.title)
                            Text(verbatim: dict.index.revision)
                                .lineLimit(1)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteDictionary(dict)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove { from, to in
                    dictionaryManager.moveDictionary(from: from, to: to, type: selectedType)
                }
                .onDelete { indexSet in
                    dictionaryManager.deleteDictionary(indexSet: indexSet, type: selectedType)
                }
            } header: {
                Picker(selection: $selectedType) {
                    Text("Term", tableName: "Dictionaries").tag(DictionaryType.term)
                    Text("Frequency", tableName: "Dictionaries").tag(DictionaryType.frequency)
                    Text("Pitch", tableName: "Dictionaries").tag(DictionaryType.pitch)
                } label: {
                    Text("Type", tableName: "Dictionaries")
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showCSSEditor) {
            DictionaryDetailSettingView()
        }
        .toolbar {
            #if os(macOS)
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
            #else
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCSSEditor = true
                } label: {
                    Image(systemName: "curlybraces")
                }
                .disabled(dictionaryManager.isImporting || dictionaryManager.isUpdating)
            }

            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            ToolbarItem(placement: .topBarTrailing) {
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
            #endif
        }
        .overlay {
            if dictionaryManager.isImporting || dictionaryManager.isUpdating {
                LoadingOverlay(dictionaryManager.currentImport)
            }
        }
        .navigationTitle(String(localized: "Dictionaries", table: "Dictionaries"))
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
}

struct DictionarySettingsView: View {
    @Environment(UserConfig.self) private var userConfig

    var body: some View {
        @Bindable var userConfig = userConfig
        List {
            Section {
                Toggle(isOn: $userConfig.scanNonJapaneseText) {
                    Text("Scan Non-Japanese Text", tableName: "Dictionaries")
                }
                HStack {
                    Text("Max Results", tableName: "Dictionaries")
                    Spacer()
                    Text(verbatim: "\(userConfig.maxResults)")
                        .fontWeight(.semibold)
                    Stepper(value: $userConfig.maxResults, in: 1...50) {
                        Text("Max Results", tableName: "Dictionaries")
                    }
                    .labelsHidden()
                }
                HStack {
                    Text("Scan Length", tableName: "Dictionaries")
                    Spacer()
                    Text(verbatim: "\(userConfig.scanLength)")
                        .fontWeight(.semibold)
                    Stepper(value: $userConfig.scanLength, in: 1...64) {
                        Text("Scan Length", tableName: "Dictionaries")
                    }
                    .labelsHidden()
                }
            } header: {
                Text("Lookup", tableName: "Dictionaries")
            }
            Section {
                Picker(selection: $userConfig.collapseMode) {
                    ForEach(CollapseMode.allCases, id: \.self) { m in
                        collapseModeText(m).tag(m)
                    }
                } label: {
                    Text("Mode", tableName: "Dictionaries")
                }
                if userConfig.collapseMode != .expandAll {
                    Toggle(isOn: $userConfig.expandFirstDictionary) {
                        Text("Expand First Dictionary", tableName: "Dictionaries")
                    }
                }
                if userConfig.collapseMode == .custom {
                    NavigationLink {
                        CollapsedDictionariesView()
                    } label: {
                        Text("Configure", tableName: "Dictionaries")
                    }
                }
            } header: {
                Text("Collapse Dictionaries", tableName: "Dictionaries")
            }

            Section {
                Toggle(isOn: $userConfig.compactGlossaries) {
                    Text("Compact Glossaries", tableName: "Dictionaries")
                }
                Toggle(isOn: $userConfig.showExpressionTags) {
                    Text("Show Expression Tags", tableName: "Dictionaries")
                }
                Toggle(isOn: $userConfig.harmonicFrequency) {
                    Text("Harmonic Frequency", tableName: "Dictionaries")
                }
                Toggle(isOn: $userConfig.deduplicatePitchAccents) {
                    Text("Deduplicate Pitch Accents", tableName: "Dictionaries")
                }
                Toggle(isOn: $userConfig.compactPitchAccents) {
                    Text("Compact Pitch Accents", tableName: "Dictionaries")
                }
                VStack {
                    HStack {
                        Text("Mac Hover Delay")
                        Spacer()
                        Text("\(userConfig.desktopLookupHoverDelayMs) ms")
                            .fontWeight(.semibold)
                    }
                    Slider(value: .init(
                        get: { Double(userConfig.desktopLookupHoverDelayMs) },
                        set: { userConfig.desktopLookupHoverDelayMs = Int($0) }
                    ), in: 0...250, step: 5)
                }
            } header: {
                Text("Behaviour", tableName: "Dictionaries")
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
        List {
            ForEach(dictionaryManager.termDictionaries) { dict in
                HStack {
                    Image(systemName: dictionaryManager.collapsedDictionaries.contains(dict.index.title) ? "chevron.right" : "chevron.down")
                        .foregroundStyle(dictionaryManager.collapsedDictionaries.contains(dict.index.title) ? .secondary : .primary)
                        .frame(width: 16)
                    Text(verbatim: dict.index.title)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    dictionaryManager.toggleCollapsedDictionary(title: dict.index.title)
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
