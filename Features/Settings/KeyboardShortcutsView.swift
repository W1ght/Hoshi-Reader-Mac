//
//  KeyboardShortcutsView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct KeyboardShortcutsView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var recording: ShortcutAction?

    var body: some View {
        @Bindable var userConfig = userConfig

        NativeSettingsForm {
            NativeSettingsSectionCard {
                Text("Reading")
            } content: {
                ShortcutRecorderRow(
                    title: "Previous Page",
                    shortcut: $userConfig.readerPreviousPageShortcut,
                    action: .previousPage,
                    recording: $recording
                )
                NativeSettingsSeparator()
                ShortcutRecorderRow(
                    title: "Next Page",
                    shortcut: $userConfig.readerNextPageShortcut,
                    action: .nextPage,
                    recording: $recording
                )
            } footer: {
                Text("Click a shortcut, then press a single key or a key combination.")
            }

            NativeSettingsSectionCard("Sasayaki") {
                ShortcutRecorderRow(
                    title: "Previous Cue",
                    shortcut: $userConfig.sasayakiPreviousCueShortcut,
                    action: .previousSasayakiCue,
                    recording: $recording
                )
                NativeSettingsSeparator()
                ShortcutRecorderRow(
                    title: "Play/Pause",
                    shortcut: $userConfig.sasayakiPlayPauseShortcut,
                    action: .playPauseSasayaki,
                    recording: $recording
                )
                NativeSettingsSeparator()
                ShortcutRecorderRow(
                    title: "Next Cue",
                    shortcut: $userConfig.sasayakiNextCueShortcut,
                    action: .nextSasayakiCue,
                    recording: $recording
                )
                NativeSettingsSeparator()
                ShortcutRecorderRow(
                    title: "Replay Cue",
                    shortcut: $userConfig.sasayakiReplayCueShortcut,
                    action: .replaySasayakiCue,
                    recording: $recording
                )
                NativeSettingsSeparator()
                ShortcutRecorderRow(
                    title: "Jump Cue",
                    shortcut: $userConfig.sasayakiJumpCueShortcut,
                    action: .jumpSasayakiCue,
                    recording: $recording
                )
            }

            NativeSettingsSectionCard("Dictionary") {
                ShortcutRecorderRow(
                    title: "Previous Entry",
                    shortcut: $userConfig.dictionaryPreviousEntryShortcut,
                    action: .previousDictionaryEntry,
                    recording: $recording
                )
                NativeSettingsSeparator()
                ShortcutRecorderRow(
                    title: "Next Entry",
                    shortcut: $userConfig.dictionaryNextEntryShortcut,
                    action: .nextDictionaryEntry,
                    recording: $recording
                )
                NativeSettingsSeparator()
                NativeSettingsRow("Entry Jump Count") {
                    Text(verbatim: "\(userConfig.dictionaryEntryJumpCount)")
                        .foregroundStyle(.secondary)
                    Stepper("", value: $userConfig.dictionaryEntryJumpCount, in: 1...10)
                        .labelsHidden()
                }
            }
        }
        .navigationTitle("Keyboard Shortcuts")
        .overlay {
            if recording != nil {
                ShortcutKeyCaptureView(
                    onCapture: { shortcut in
                        assign(shortcut)
                    },
                    onCancel: {
                        recording = nil
                    }
                )
                .frame(width: 0, height: 0)
            }
        }
    }

    private func assign(_ shortcut: ReaderKeyboardShortcut) {
        guard let recording else { return }

        switch recording {
        case .previousPage:
            userConfig.readerPreviousPageShortcut = shortcut
        case .nextPage:
            userConfig.readerNextPageShortcut = shortcut
        case .previousSasayakiCue:
            userConfig.sasayakiPreviousCueShortcut = shortcut
        case .playPauseSasayaki:
            userConfig.sasayakiPlayPauseShortcut = shortcut
        case .nextSasayakiCue:
            userConfig.sasayakiNextCueShortcut = shortcut
        case .replaySasayakiCue:
            userConfig.sasayakiReplayCueShortcut = shortcut
        case .jumpSasayakiCue:
            userConfig.sasayakiJumpCueShortcut = shortcut
        case .previousDictionaryEntry:
            userConfig.dictionaryPreviousEntryShortcut = shortcut
        case .nextDictionaryEntry:
            userConfig.dictionaryNextEntryShortcut = shortcut
        }

        self.recording = nil
    }
}

private enum ShortcutAction: Hashable {
    case previousPage
    case nextPage
    case previousSasayakiCue
    case playPauseSasayaki
    case nextSasayakiCue
    case replaySasayakiCue
    case jumpSasayakiCue
    case previousDictionaryEntry
    case nextDictionaryEntry
}

private struct ShortcutRecorderRow: View {
    let title: LocalizedStringKey
    @Binding var shortcut: ReaderKeyboardShortcut
    let action: ShortcutAction
    @Binding var recording: ShortcutAction?

    private var isRecording: Bool {
        recording == action
    }

    var body: some View {
        Button {
            recording = action
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                if isRecording {
                    ShortcutValuePill {
                        Text("Press keys...")
                            .foregroundStyle(Color.accentColor)
                    }
                } else {
                    ShortcutValuePill {
                        Text(shortcut.label)
                    }
                }
            }
            .frame(minHeight: 46)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutValuePill<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(.body.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
    }
}
