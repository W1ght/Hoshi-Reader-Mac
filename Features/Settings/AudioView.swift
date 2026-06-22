//
//  AudioView.swift
//  Hoshi Reader
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

    var body: some View {
        @Bindable var userConfig = userConfig
        NativeSettingsForm {
            NativeSettingsSectionCard("Sources") {
                ForEach(Array(userConfig.audioSources.enumerated()), id: \.element.id) { index, source in
                    if index > 0 {
                        NativeSettingsSeparator()
                    }
                    NativeSettingsReorderRow(
                        isTargeted: Binding(
                            get: { dropTargetAudioSourceID == source.id },
                            set: { dropTargetAudioSourceID = $0 ? source.id : nil }
                        ),
                        onDrop: { payload in
                            acceptAudioSourceDrop(payload, onto: source.id)
                        }
                    ) {
                        NativeSettingsRow {
                            HStack(spacing: 10) {
                                audioSourceReorderHandle()
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
                            Toggle("", isOn: Binding(
                                get: { source.isEnabled },
                                set: { userConfig.audioSources[index].isEnabled = $0 }
                            ))
                            .labelsHidden()
                        }
                        .contentShape(Rectangle())
                        .onDrag {
                            NSItemProvider(
                                object: AudioSourceReorder.payload(for: source.id) as NSString
                            )
                        } preview: {
                            audioSourceDragPreview(source)
                        }
                        .background {
                            if dropTargetAudioSourceID == source.id {
                                Color.accentColor.opacity(0.12)
                            }
                        }
                        .contextMenu {
                            if !source.isDefault && source.url != UserConfig.localAudioSource.url {
                                Button(role: .destructive) {
                                    userConfig.audioSources.remove(at: index)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            NativeSettingsSectionCard("Add Source") {
                NativeSettingsRow("Name") {
                    TextField("Name", text: $nameInput)
                        .textFieldStyle(.roundedBorder)
                }
                NativeSettingsSeparator()
                NativeSettingsRow("URL") {
                    TextField("URL", text: $urlInput)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let trimmedURL = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedName = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedURL.isEmpty && !userConfig.audioSources.contains(where: { $0.url == trimmedURL }) {
                            userConfig.audioSources.append(AudioSource(name: trimmedName, url: trimmedURL))
                            nameInput = ""
                            urlInput = ""
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(urlInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty || nameInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
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

    private func acceptAudioSourceDrop(_ payload: String, onto targetID: String) -> Bool {
        dropTargetAudioSourceID = nil
        guard let sourceID = AudioSourceReorder.audioSourceID(from: payload) else {
            return false
        }
        return reorderAudioSource(sourceID, onto: targetID)
    }

    private func audioSourceReorderHandle() -> some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .frame(width: 18, height: 32)
            .accessibilityHidden(true)
    }

    private func audioSourceDragPreview(_ source: AudioSource) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
            sourceName(of: source)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.7)
        }
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
