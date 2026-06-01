//
//  ShortcutKeyCaptureView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
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
