//
//  SasayakiSheet.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

struct SasayakiSheet: View {
    @Environment(UserConfig.self) private var userConfig
    var player: SasayakiPlayer
    let onImportAudio: (URL) throws -> Void
    let onDismiss: () -> Void
    
    @State private var isImportingAudio = false
    
    var body: some View {
        NavigationStack {
            sasayakiContent
            .navigationTitle("Sasayaki")
            .sasayakiNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    closeButton
                }
            }
            .fileImporter(
                isPresented: $isImportingAudio,
                allowedContentTypes: ["mp3", "m4b"].compactMap { UTType(filenameExtension: $0) }
            ) { result in
                guard case .success(let url) = result else { return }
                do {
                    try onImportAudio(url)
                } catch {
                    player.errorMessage = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private var sasayakiContent: some View {
        nativeSasayakiContent
    }

    private var nativeSasayakiContent: some View {
        @Bindable var userConfig = userConfig

        return NativeSettingsForm {
            NativeSettingsSectionCard("Audio") {
                if player.hasAudio {
                    audioControls
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    NativeSettingsSeparator()
                    Text("\(Self.formatTime(player.currentTime)) / \(Self.formatTime(player.duration))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    NativeSettingsSeparator()
                }

                NativeSettingsRow("Load Audio") {
                    Button("Load Audio") {
                        isImportingAudio = true
                    }
                }

                if let errorMessage = player.errorMessage {
                    NativeSettingsSeparator()
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }

            NativeSettingsSectionCard("Playback") {
                VStack(spacing: 8) {
                    HStack {
                        Text("Delay")
                        Spacer()
                        Text(String(format: "%+.2fs", player.delay))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    Slider(value: Bindable(player).delay, in: -2...2, step: 0.05)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                NativeSettingsSeparator()

                VStack(spacing: 8) {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text(String(format: "%.2fx", player.rate))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    Slider(value: Bindable(player).rate, in: 0.5...1.5, step: 0.05)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            NativeSettingsSectionCard("Settings") {
                NativeSettingsToggle("Show Sasayaki Toggle", isOn: $userConfig.readerShowSasayakiToggle)
                NativeSettingsSeparator()
                NativeSettingsToggle("Auto-Scroll", isOn: $userConfig.sasayakiAutoScroll)
                NativeSettingsSeparator()
                NativeSettingsToggle("Auto-Pause on Lookup", isOn: $userConfig.sasayakiAutoPause)
            }

            NativeSettingsSectionCard("Light Theme") {
                NativeSettingsRow("Text Color") {
                    ColorPicker("", selection: $userConfig.sasayakiTextColor)
                        .labelsHidden()
                }
                NativeSettingsSeparator()
                NativeSettingsRow("Background Color") {
                    ColorPicker("", selection: $userConfig.sasayakiBackgroundColor)
                        .labelsHidden()
                }
            }

            NativeSettingsSectionCard("Dark Theme") {
                NativeSettingsRow("Text Color") {
                    ColorPicker("", selection: $userConfig.sasayakiDarkTextColor)
                        .labelsHidden()
                }
                NativeSettingsSeparator()
                NativeSettingsRow("Background Color") {
                    ColorPicker("", selection: $userConfig.sasayakiDarkBackgroundColor)
                        .labelsHidden()
                }
            }
        }
    }

    private var legacySasayakiContent: some View {
        @Bindable var userConfig = userConfig

        return Form {
            Section("Audio") {
                if player.hasAudio {
                    audioControls
                        .buttonStyle(.borderless)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)

                    Text("\(Self.formatTime(player.currentTime)) / \(Self.formatTime(player.duration))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Button("Load Audio") {
                    isImportingAudio = true
                }

                if let errorMessage = player.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("Playback") {
                VStack {
                    HStack {
                        Text("Delay")
                        Spacer()
                        Text(String(format: "%+.2fs", player.delay))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    Slider(value: Bindable(player).delay, in: -2...2, step: 0.05)
                }
                VStack {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text(String(format: "%.2fx", player.rate))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    Slider(value: Bindable(player).rate, in: 0.5...1.5, step: 0.05)
                }
            }

            Section("Settings") {
                Toggle("Show Sasayaki Toggle", isOn: $userConfig.readerShowSasayakiToggle)
                Toggle("Auto-Scroll", isOn: $userConfig.sasayakiAutoScroll)
                Toggle("Auto-Pause on Lookup", isOn: $userConfig.sasayakiAutoPause)
            }

            Section("Light Theme") {
                ColorPicker("Text Color", selection: $userConfig.sasayakiTextColor)
                ColorPicker("Background Color", selection: $userConfig.sasayakiBackgroundColor)
            }

            Section("Dark Theme") {
                ColorPicker("Text Color", selection: $userConfig.sasayakiDarkTextColor)
                ColorPicker("Background Color", selection: $userConfig.sasayakiDarkBackgroundColor)
            }
        }
    }

    private var audioControls: some View {
        HStack(spacing: 20) {
            Button {
                player.skip(forward: false)
            } label: {
                Image(systemName: "15.arrow.trianglehead.counterclockwise")
            }

            Button {
                player.prevCue()
            } label: {
                Image(systemName: "backward.fill")
            }

            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30))
            }

            Button {
                player.nextCue()
            } label: {
                Image(systemName: "forward.fill")
            }

            Button {
                player.skip(forward: true)
            } label: {
                Image(systemName: "15.arrow.trianglehead.clockwise")
            }
        }
        .buttonStyle(.borderless)
        .font(.title2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
    
    private static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private var closeButton: some View {
        NativeGlassCircleButton(systemName: "xmark", diameter: 34, fontSize: 13) {
            onDismiss()
        }
    }
}

private struct SasayakiNavigationChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

private extension View {
    func sasayakiNavigationChrome() -> some View {
        modifier(SasayakiNavigationChromeModifier())
    }
}
