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
    @State private var dropTargetDictionaryID: UUID?
    @State private var activeDictionaryDragSourceID: UUID?
    @State private var dictionaryRowFrames: [UUID: CGRect] = [:]

    private var dictionaries: [DictionaryInfo] {
        switch selectedType {
        case .term: return dictionaryManager.termDictionaries
        case .frequency: return dictionaryManager.frequencyDictionaries
        case .pitch: return dictionaryManager.pitchDictionaries
        }
    }

    private var dictionaryReorderCoordinateSpaceName: String {
        "settings-dictionary-reorder-\(selectedType.rawValue)"
    }

    private var lastUpdate: String {
        guard let date = UserDefaults.standard.object(forKey: "lastDictionaryUpdate") as? Date else {
            return String(localized: "Never", table: "Dictionaries")
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var recommendedDownloadMessage: String {
        let heading = String(
            localized: "This will download the following recommended dictionaries:",
            table: "Dictionaries"
        )
        let entries = dictionaryManager.recommendedDictionaries.map { recommendation in
            let type = switch recommendation.type {
            case .term: String(localized: "Term", table: "Dictionaries")
            case .frequency: String(localized: "Frequency", table: "Dictionaries")
            case .pitch: String(localized: "Pitch", table: "Dictionaries")
            }
            return "\(recommendation.name) (\(type))"
        }
        return ([heading] + entries).joined(separator: "\n")
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
            }

            DictionaryBehaviorSettingsSections()

            NativeSettingsSectionCard {
                HStack {
                    Text("Dictionaries", tableName: "Dictionaries")
                    Spacer()
                    dictionaryTypePicker
                }
            } content: {
                VStack(spacing: 0) {
                    ForEach(Array(dictionaries.enumerated()), id: \.element.id) { index, dict in
                        if index > 0 {
                            NativeSettingsSeparator()
                        }
                        NativeSettingsRow {
                            HStack(spacing: 10) {
                                dictionaryReorderHandle()
                                    .contentShape(Rectangle())
                                    .highPriorityGesture(dictionaryReorderGesture(for: dict.id))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: dict.index.title)
                                    Text(verbatim: dict.index.revision)
                                        .lineLimit(1)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } accessory: {
                            Toggle("", isOn: Binding(
                                get: { dict.isEnabled },
                                set: { dictionaryManager.toggleDictionary(id: dict.id, enabled: $0, type: selectedType) }
                            ))
                            .labelsHidden()
                        }
                        .contentShape(Rectangle())
                        .background {
                            if dropTargetDictionaryID == dict.id {
                                Color.accentColor.opacity(0.12)
                            }
                        }
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: DictionaryRowFramePreferenceKey.self,
                                    value: [dict.id: proxy.frame(in: .named(dictionaryReorderCoordinateSpaceName))]
                                )
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteDictionary(dict)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .scaleEffect(activeDictionaryDragSourceID == dict.id ? 1.01 : 1)
                        .zIndex(activeDictionaryDragSourceID == dict.id ? 1 : 0)
                        .frame(maxWidth: .infinity)
                    }
                }
                .coordinateSpace(name: dictionaryReorderCoordinateSpaceName)
                .onPreferenceChange(DictionaryRowFramePreferenceKey.self) { frames in
                    dictionaryRowFrames = frames
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
            Text(verbatim: recommendedDownloadMessage)
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

    private func reorderDictionary(_ sourceID: UUID, onto targetID: UUID) -> Bool {
        guard let sourceIndex = dictionaries.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = dictionaries.firstIndex(where: { $0.id == targetID }),
              let destination = DictionaryReorder.destinationOffset(
                sourceIndex: sourceIndex,
                targetIndex: targetIndex
              ) else {
            return false
        }
        withAnimation(.snappy(duration: 0.18)) {
            dictionaryManager.moveDictionary(
                from: IndexSet(integer: sourceIndex),
                to: destination,
                type: selectedType
            )
        }
        return true
    }

    private func dictionaryReorderGesture(for sourceID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(dictionaryReorderCoordinateSpaceName))
            .onChanged { value in
                updateDictionaryDrag(sourceID, to: value.location)
            }
            .onEnded { value in
                endDictionaryDrag(sourceID, at: value.location)
            }
    }

    private func updateDictionaryDrag(_ sourceID: UUID, to location: CGPoint) {
        beginDictionaryDragIfNeeded(sourceID)
        guard let targetID = dictionaryRowFrames.first(where: { id, frame in
            id != sourceID && frame.insetBy(dx: -4, dy: -4).contains(location)
        })?.key else {
            return
        }
        guard dropTargetDictionaryID != targetID else {
            return
        }
        if reorderDictionary(sourceID, onto: targetID) {
            dropTargetDictionaryID = targetID
        }
    }

    private func endDictionaryDrag(_ sourceID: UUID, at location: CGPoint) {
        updateDictionaryDrag(sourceID, to: location)
        withAnimation(.easeOut(duration: 0.16)) {
            activeDictionaryDragSourceID = nil
            dropTargetDictionaryID = nil
        }
    }

    private func beginDictionaryDragIfNeeded(_ sourceID: UUID) {
        guard activeDictionaryDragSourceID != sourceID else {
            return
        }
        withAnimation(.snappy(duration: 0.16)) {
            activeDictionaryDragSourceID = sourceID
            dropTargetDictionaryID = nil
        }
    }

    private func dictionaryReorderHandle() -> some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .frame(width: 18, height: 32)
            .accessibilityHidden(true)
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

private struct DictionaryRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

private struct DictionaryBehaviorSettingsSections: View {
    @Environment(UserConfig.self) private var userConfig

    var body: some View {
        @Bindable var userConfig = userConfig
        Group {
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
                NativeSettingsToggle("Two-Column Layout", isOn: $userConfig.twoColumnLayout)
                NativeSettingsSeparator()
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
            } footer: {
                Text(
                    "Arranges glossaries in two columns. Only recommended when used with full-width or on larger screens.",
                    tableName: "Dictionaries"
                )
            }
        }
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
                .background {
                    NativeGlassPageBackground()
                }
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
