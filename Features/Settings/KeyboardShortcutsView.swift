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
}

private struct ShortcutRecorderRow: View {
    let title: String
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

                Text(isRecording ? "Press keys..." : shortcut.label)
                    .font(.body.monospaced())
                    .foregroundStyle(isRecording ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
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
                  let shortcut = ReaderKeyboardShortcut(key: key) else {
                super.pressesBegan(presses, with: event)
                return
            }

            onCapture?(shortcut)
        }
    }
}

private extension ReaderKeyboardShortcut {
    init?(key: UIKey) {
        guard let keyValue = Self.keyValue(for: key) else {
            return nil
        }

        self.key = keyValue
        self.modifiers = Self.eventModifiers(from: key.modifierFlags).rawValue
    }

    private static func keyValue(for key: UIKey) -> String? {
        switch key.keyCode {
        case .keyboardLeftArrow: return "leftArrow"
        case .keyboardRightArrow: return "rightArrow"
        case .keyboardUpArrow: return "upArrow"
        case .keyboardDownArrow: return "downArrow"
        case .keyboardPageUp: return "pageUp"
        case .keyboardPageDown: return "pageDown"
        case .keyboardSpacebar: return "space"
        case .keyboardEscape: return nil
        default:
            guard let character = key.charactersIgnoringModifiers.lowercased().first,
                  !character.isWhitespace else {
                return nil
            }
            return String(character)
        }
    }

    private static func eventModifiers(from flags: UIKeyModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
