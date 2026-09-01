//
//  AudioView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

struct AudioView: View {
    @Environment(UserConfig.self) var userConfig
    @State private var nameInput = ""
    @State private var urlInput = ""
    @State private var isImporting = false
    @State private var importedSize: String?
    @State private var dropTargetAudioSourceID: String?
    @State private var activeAudioSourceDragSourceID: String?
    @State private var audioSourceRowFrames: [String: CGRect] = [:]

    private var audioSourceReorderCoordinateSpaceName: String {
        "settings-audio-source-reorder"
    }

    var body: some View {
        @Bindable var userConfig = userConfig
        NativeSettingsForm {
            NativeSettingsSectionCard("Sources") {
                VStack(spacing: 0) {
                    ForEach($userConfig.audioSources) { $source in
                        let sourceID = source.id
                        if sourceID != userConfig.audioSources.first?.id {
                            NativeSettingsSeparator()
                        }
                        NativeSettingsRow {
                            HStack(spacing: 10) {
                                audioSourceReorderHandle()
                                    .contentShape(Rectangle())
                                    .highPriorityGesture(audioSourceReorderGesture(for: sourceID))
                                VStack(alignment: .leading) {
                                    sourceName(of: source)
                                        .lineLimit(1)
                                    if !source.isDefault && source.url != UserConfig.localAudioSource.url {
                                        Text(source.url)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        } accessory: {
                            Toggle("", isOn: $source.isEnabled)
                            .labelsHidden()
                        }
                        .contentShape(Rectangle())
                        .background {
                            if dropTargetAudioSourceID == sourceID {
                                Color.accentColor.opacity(0.12)
                            }
                        }
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: AudioSourceRowFramePreferenceKey.self,
                                    value: [sourceID: proxy.frame(in: .named(audioSourceReorderCoordinateSpaceName))]
                                )
                            }
                        }
                        .contextMenu {
                            if !source.isDefault && source.url != UserConfig.localAudioSource.url {
                                Button(role: .destructive) {
                                    deleteAudioSource(id: sourceID)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .scaleEffect(activeAudioSourceDragSourceID == sourceID ? 1.01 : 1)
                        .zIndex(activeAudioSourceDragSourceID == sourceID ? 1 : 0)
                        .frame(maxWidth: .infinity)
                    }
                }
                .coordinateSpace(name: audioSourceReorderCoordinateSpaceName)
                .onPreferenceChange(AudioSourceRowFramePreferenceKey.self) { frames in
                    audioSourceRowFrames = frames
                }
            }

            NativeSettingsSectionCard("Add Source") {
                NativeSettingsRow("Name") {
                    TextField("Name", text: $nameInput)
                        .nativeSettingsTextField()
                }
                NativeSettingsSeparator()
                NativeSettingsRow("URL") {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("URL", text: $urlInput)
                                .autocorrectionDisabled()
                                .nativeSettingsTextField()

                            Button {
                                let trimmedURL = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                let trimmedName = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmedURL.isEmpty && !userConfig.audioSources.contains(where: { $0.url == trimmedURL }) {
                                    userConfig.audioSources.append(AudioSource(name: trimmedName, url: trimmedURL))
                                    nameInput = ""
                                    urlInput = ""
                                }
                            } label: {
                                Label("Add Source", systemImage: "plus")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .controlSize(.large)
                            .help("Add Source")
                            .disabled(
                                urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                    }
                }
            } footer: {
                Text("Yomitan JSON audio sources are supported")
            }

            NativeSettingsSectionCard("Playback") {
                NativeSettingsToggle("Auto-play on Lookup", isOn: $userConfig.audioEnableAutoplay)
                NativeSettingsSeparator()
                NativeSettingsRow("Background Audio") {
                    NativeGlassSegmentedPicker(
                        selection: $userConfig.audioPlaybackMode,
                        values: AudioPlaybackMode.allCases,
                        minSegmentWidth: 92
                    ) { mode in
                        backgroundAudioText(mode)
                    }
                }
            }

            NativeSettingsSectionCard {
                Text("Local Audio")
            } content: {
                NativeSettingsToggle("Enable", isOn: $userConfig.enableLocalAudio)
                if userConfig.enableLocalAudio {
                    NativeSettingsSeparator()
                    NativeSettingsButtonRow {
                        Button("Import") {
                            isImporting = true
                        }
                        if let importedSize {
                            Button("Delete android.db (\(importedSize))", role: .destructive) {
                                deleteAudioDb()
                            }
                        }
                    }
                }
            } footer: {
                Text("Import a local audio database for offline dictionary audio. The local audio source is automatically added when enabled.")
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "db")!]
        ) { result in
            importAudioDb(result: result)
        }
        .onAppear {
            calcAudioDbSize()
        }
        .navigationTitle("Audio")
    }

    private let audioDbURL: URL = {
        let docs = try! BookStorage.getAppDirectory()
        return docs.appendingPathComponent(LocalFileServer.localAudioPath)
    }()

    private func deleteAudioDb() {
        try? BookStorage.delete(at: audioDbURL)
        importedSize = nil
    }

    private func importAudioDb(result: Result<URL, Error>) {
        guard let sourceURL = try? result.get(),
              let _ = try? BookStorage.copySecurityScopedFile(from: sourceURL, to: LocalFileServer.localAudioPath) else {
            return
        }
        var url = audioDbURL
        try? url.excludeFromBackup()
        calcAudioDbSize()
    }

    private func calcAudioDbSize() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: audioDbURL.path(percentEncoded: false)),
              let size = attributes[.size] as? Int64 else {
            importedSize = nil
            return
        }
        importedSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func sourceName(of source: AudioSource) -> Text {
        source.name == "Default" ? Text("Default") : Text(source.name)
    }

    private func deleteAudioSource(id sourceID: AudioSource.ID) {
        let remainingSources = userConfig.audioSources.filter { $0.id != sourceID }
        guard remainingSources.count != userConfig.audioSources.count else {
            return
        }
        userConfig.audioSources = remainingSources
    }

    private func reorderAudioSource(_ sourceID: String, onto targetID: String) -> Bool {
        guard let sourceIndex = userConfig.audioSources.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = userConfig.audioSources.firstIndex(where: { $0.id == targetID }),
              let destination = AudioSourceReorder.destinationOffset(
                sourceIndex: sourceIndex,
                targetIndex: targetIndex
              ) else {
            return false
        }
        withAnimation(.snappy(duration: 0.18)) {
            userConfig.audioSources.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destination
            )
        }
        return true
    }

    private func audioSourceReorderGesture(for sourceID: String) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(audioSourceReorderCoordinateSpaceName))
            .onChanged { value in
                updateAudioSourceDrag(sourceID, to: value.location)
            }
            .onEnded { value in
                endAudioSourceDrag(sourceID, at: value.location)
            }
    }

    private func updateAudioSourceDrag(_ sourceID: String, to location: CGPoint) {
        beginAudioSourceDragIfNeeded(sourceID)
        guard let targetID = audioSourceRowFrames.first(where: { id, frame in
            id != sourceID && frame.insetBy(dx: -4, dy: -4).contains(location)
        })?.key else {
            return
        }
        guard dropTargetAudioSourceID != targetID else {
            return
        }
        if reorderAudioSource(sourceID, onto: targetID) {
            dropTargetAudioSourceID = targetID
        }
    }

    private func endAudioSourceDrag(_ sourceID: String, at location: CGPoint) {
        updateAudioSourceDrag(sourceID, to: location)
        withAnimation(.easeOut(duration: 0.16)) {
            activeAudioSourceDragSourceID = nil
            dropTargetAudioSourceID = nil
        }
    }

    private func beginAudioSourceDragIfNeeded(_ sourceID: String) {
        guard activeAudioSourceDragSourceID != sourceID else {
            return
        }
        withAnimation(.snappy(duration: 0.16)) {
            activeAudioSourceDragSourceID = sourceID
            dropTargetAudioSourceID = nil
        }
    }

    private func audioSourceReorderHandle() -> some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .frame(width: 18, height: 32)
            .accessibilityHidden(true)
    }

    private func backgroundAudioText(_ mode: AudioPlaybackMode) -> Text {
        switch mode {
        case .interrupt:
            Text("Interrupt")
        case .duck:
            Text("Lower Volume")
        case .mix:
            Text("Keep Volume")
        }
    }
}

private struct AudioSourceRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}
