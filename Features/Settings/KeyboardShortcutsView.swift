//
//  KeyboardShortcutsView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UIKit

struct KeyboardShortcutsView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var recording: ShortcutAction?

    var body: some View {
        @Bindable var userConfig = userConfig

        List {
            Section {
                ShortcutRecorderRow(
                    title: "Previous Page",
                    shortcut: $userConfig.readerPreviousPageShortcut,
                    action: .previousPage,
                    recording: $recording
                )
                ShortcutRecorderRow(
                    title: "Next Page",
                    shortcut: $userConfig.readerNextPageShortcut,
                    action: .nextPage,
                    recording: $recording
                )
            } header: {
                Text("Reading")
            } footer: {
                Text("Click a shortcut, then press a single key or a key combination.")
            }

            Section("Sasayaki") {
                ShortcutRecorderRow(
                    title: "Previous Cue",
                    shortcut: $userConfig.sasayakiPreviousCueShortcut,
                    action: .previousSasayakiCue,
                    recording: $recording
                )
                ShortcutRecorderRow(
                    title: "Play/Pause",
                    shortcut: $userConfig.sasayakiPlayPauseShortcut,
                    action: .playPauseSasayaki,
                    recording: $recording
                )
                ShortcutRecorderRow(
                    title: "Next Cue",
                    shortcut: $userConfig.sasayakiNextCueShortcut,
                    action: .nextSasayakiCue,
                    recording: $recording
                )
                ShortcutRecorderRow(
                    title: "Replay Cue",
                    shortcut: $userConfig.sasayakiReplayCueShortcut,
                    action: .replaySasayakiCue,
                    recording: $recording
                )
                ShortcutRecorderRow(
                    title: "Jump Cue",
                    shortcut: $userConfig.sasayakiJumpCueShortcut,
                    action: .jumpSasayakiCue,
                    recording: $recording
                )
            }

            Section("Dictionary") {
                ShortcutRecorderRow(
                    title: "Previous Entry",
                    shortcut: $userConfig.dictionaryPreviousEntryShortcut,
                    action: .previousDictionaryEntry,
                    recording: $recording
                )
                ShortcutRecorderRow(
                    title: "Next Entry",
                    shortcut: $userConfig.dictionaryNextEntryShortcut,
                    action: .nextDictionaryEntry,
                    recording: $recording
                )
                Stepper(value: $userConfig.dictionaryEntryJumpCount, in: 1...10) {
                    HStack {
                        Text("Entry Jump Count")
                        Spacer()
                        Text(verbatim: "\(userConfig.dictionaryEntryJumpCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Keyboard Shortcuts")
        .overlay {
            if recording != nil {
                ShortcutKeyCaptureView { shortcut in
                    assign(shortcut)
                }
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
                    Text("Press keys...")
                        .font(.body.monospaced())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                } else {
                    Text(shortcut.label)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutKeyCaptureView: UIViewRepresentable {
    let onCapture: (ReaderKeyboardShortcut) -> Void

    func makeUIView(context: Context) -> KeyCaptureUIView {
        let view = KeyCaptureUIView()
        view.onCapture = onCapture
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: KeyCaptureUIView, context: Context) {
        uiView.onCapture = onCapture
        DispatchQueue.main.async {
            uiView.becomeFirstResponder()
        }
    }

    final class KeyCaptureUIView: UIView {
        var onCapture: ((ReaderKeyboardShortcut) -> Void)?

        override var canBecomeFirstResponder: Bool {
            true
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let key = presses.first?.key,
                  let shortcut = ReaderKeyboardShortcut(uiKey: key) else {
                super.pressesBegan(presses, with: event)
                return
            }

            onCapture?(shortcut)
        }
    }
}
