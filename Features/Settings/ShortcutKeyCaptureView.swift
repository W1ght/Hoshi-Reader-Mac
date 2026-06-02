//
//  ShortcutKeyCaptureView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

#if canImport(UIKit)
import UIKit

struct ShortcutKeyCaptureView: UIViewRepresentable {
    let onCapture: (ReaderKeyboardShortcut) -> Void
    let onCancel: () -> Void

    func makeUIView(context: Context) -> KeyCaptureUIView {
        let view = KeyCaptureUIView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.becomeFirstResponder()
        }
        return view
    }

    func updateUIView(_ uiView: KeyCaptureUIView, context: Context) {
        uiView.onCapture = onCapture
        uiView.onCancel = onCancel
        DispatchQueue.main.async {
            uiView.becomeFirstResponder()
        }
    }

    final class KeyCaptureUIView: UIView {
        var onCapture: ((ReaderKeyboardShortcut) -> Void)?
        var onCancel: (() -> Void)?

        override var canBecomeFirstResponder: Bool {
            true
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let key = presses.first?.key else {
                super.pressesBegan(presses, with: event)
                return
            }

            if key.keyCode == .keyboardEscape {
                onCancel?()
                return
            }

            guard let shortcut = ReaderKeyboardShortcut(uiKey: key) else {
                super.pressesBegan(presses, with: event)
                return
            }

            onCapture?(shortcut)
        }
    }
}
#elseif canImport(AppKit)
import AppKit

struct ShortcutKeyCaptureView: NSViewRepresentable {
    let onCapture: (ReaderKeyboardShortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class KeyCaptureNSView: NSView {
        var onCapture: ((ReaderKeyboardShortcut) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onCancel?()
                return
            }

            guard let shortcut = ReaderKeyboardShortcut(nsEvent: event) else {
                super.keyDown(with: event)
                return
            }

            onCapture?(shortcut)
        }
    }
}

extension ReaderKeyboardShortcut {
    init?(nsEvent event: NSEvent) {
        guard let keyValue = Self.keyValue(for: event) else {
            return nil
        }

        key = keyValue
        modifiers = Self.eventModifiers(from: event.modifierFlags).rawValue
    }

    private static func keyValue(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 123: return "leftArrow"
        case 124: return "rightArrow"
        case 126: return "upArrow"
        case 125: return "downArrow"
        case 116: return "pageUp"
        case 121: return "pageDown"
        case 49: return "space"
        case 53: return nil
        default:
            guard let character = event.charactersIgnoringModifiers?.lowercased().first,
                  !character.isWhitespace else {
                return nil
            }
            return String(character)
        }
    }

    private static func eventModifiers(from flags: NSEvent.ModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        let filtered = flags.intersection(.deviceIndependentFlagsMask)
        if filtered.contains(.command) { modifiers.insert(.command) }
        if filtered.contains(.shift) { modifiers.insert(.shift) }
        if filtered.contains(.option) { modifiers.insert(.option) }
        if filtered.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
#endif
