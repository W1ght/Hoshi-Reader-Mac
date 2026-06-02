import AppKit
import SwiftUI

struct NativeShortcutCaptureResult: Equatable {
    let keyCode: UInt16
    let charactersIgnoringModifiers: String
    let modifiers: NSEvent.ModifierFlags

    var modifierSummary: String {
        var parts: [String] = []
        if modifiers.contains(.command) {
            parts.append("Command")
        }
        if modifiers.contains(.option) {
            parts.append("Option")
        }
        if modifiers.contains(.control) {
            parts.append("Control")
        }
        if modifiers.contains(.shift) {
            parts.append("Shift")
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " + ")
    }

    var displayText: String {
        let key = charactersIgnoringModifiers.isEmpty ? "keyCode \(keyCode)" : charactersIgnoringModifiers
        return modifierSummary == "None" ? key : "\(modifierSummary) + \(key)"
    }
}

struct NativeShortcutCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (NativeShortcutCaptureResult) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        nsView.isActive = isActive

        guard isActive else {
            return
        }

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class KeyCaptureNSView: NSView {
        var isActive = false
        var onCapture: ((NativeShortcutCaptureResult) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool {
            true
        }

        override var canBecomeKeyView: Bool {
            true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            guard isActive else {
                return
            }

            DispatchQueue.main.async {
                self.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            guard isActive else {
                super.keyDown(with: event)
                return
            }

            if event.keyCode == 53 {
                onCancel?()
                return
            }

            let result = NativeShortcutCaptureResult(
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            )
            onCapture?(result)
        }
    }
}
