//
//  DictionarySearchTextFieldBridge.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import AppKit

struct DictionarySearchTextFieldBridge: NSViewRepresentable {
    @Binding var searchText: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let searchField = DictionarySearchTextField()
        searchField.stringValue = searchText
        searchField.placeholderString = ""
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.usesSingleLineMode = true
        searchField.font = .systemFont(ofSize: NSFont.systemFontSize)
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.submit(_:))
        searchField.delegate = context.coordinator
        return searchField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        let wasFocused = context.coordinator.isFocused
        context.coordinator.updateSelf(searchText: $searchText, isFocused: $isFocused)

        if nsView.stringValue != searchText {
            nsView.stringValue = searchText
        }

        guard nsView.window != nil else { return }
        if isFocused {
            if nsView.window?.firstResponder !== nsView.currentEditor() {
                nsView.window?.makeFirstResponder(nsView)
            }
            if !wasFocused {
                nsView.currentEditor()?.selectAll(nil)
            }
        } else if nsView.window?.firstResponder === nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(searchText: $searchText, isFocused: $isFocused, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var searchText: String
        @Binding var isFocused: Bool
        let onSubmit: () -> Void

        init(searchText: Binding<String>, isFocused: Binding<Bool>, onSubmit: @escaping () -> Void) {
            self._searchText = searchText
            self._isFocused = isFocused
            self.onSubmit = onSubmit
        }

        @objc func submit(_ sender: NSTextField) {
            searchText = sender.stringValue
            isFocused = false
            onSubmit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            if let textField = control as? NSTextField {
                submit(textField)
            }
            return true
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            if !isFocused {
                isFocused = true
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            searchText = textField.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            searchText = textField.stringValue
            isFocused = false
        }

        func updateSelf(searchText: Binding<String>, isFocused: Binding<Bool>) {
            self._searchText = searchText
            self._isFocused = isFocused
        }
    }
}

private final class DictionarySearchTextField: NSTextField {
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: NSView.noIntrinsicMetric, height: size.height)
    }
}
