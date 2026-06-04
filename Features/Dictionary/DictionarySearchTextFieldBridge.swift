//
//  DictionarySearchTextFieldBridge.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
#if canImport(UIKit)
import UIKit

struct DictionarySearchTextFieldBridge: UIViewRepresentable {
    @Binding var searchText: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let searchField = DictionarySearchTextField()
        searchField.text = searchText
        searchField.targetLanguage = "ja"
        searchField.autocapitalizationType = .none
        searchField.autocorrectionType = .no
        searchField.returnKeyType = .search
        searchField.setContentHuggingPriority(.defaultHigh, for: .vertical)
        searchField.delegate = context.coordinator
        searchField.onTransitionComplete = { [weak searchField] in
            if context.coordinator.isFocused {
                searchField?.becomeFirstResponder()
            }
        }
        return searchField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.updateSelf(searchText: $searchText, isFocused: $isFocused)

        if uiView.window != nil {
            if isFocused {
                if !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                }
                uiView.selectAll(nil)
            } else {
                uiView.resignFirstResponder()
            }
        }

        if uiView.text != searchText {
            uiView.text = searchText
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(searchText: $searchText, isFocused: $isFocused, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var searchText: String
        @Binding var isFocused: Bool
        let onSubmit: () -> Void
        private var shouldSubmit = false

        init(searchText: Binding<String>, isFocused: Binding<Bool>, onSubmit: @escaping () -> Void) {
            self._searchText = searchText
            self._isFocused = isFocused
            self.onSubmit = onSubmit
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !isFocused {
                isFocused = true
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            shouldSubmit = true
            textField.resignFirstResponder()
            isFocused = false
            return true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            searchText = textField.text ?? ""
            isFocused = false
            if shouldSubmit {
                shouldSubmit = false
                onSubmit()
            }
        }

        func updateSelf(searchText: Binding<String>, isFocused: Binding<Bool>) {
            self._searchText = searchText
            self._isFocused = isFocused
        }
    }
}

private final class DictionarySearchTextField: UITextField {
    var targetLanguage: String?
    var onTransitionComplete: (() -> Void)?

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: UIView.noIntrinsicMetric, height: size.height)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        let transitionCoordinator = parentViewController?.transitionCoordinator
        if let transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { _ in
                self.onTransitionComplete?()
            }
        } else {
            onTransitionComplete?()
        }
    }

    override var textInputMode: UITextInputMode? {
        guard let targetLanguage else {
            return super.textInputMode
        }

        for inputMode in UITextInputMode.activeInputModes {
            if let lang = inputMode.primaryLanguage, lang.hasPrefix(targetLanguage) {
                return inputMode
            }
        }

        return super.textInputMode
    }
}

private extension UIView {
    var parentViewController: UIViewController? {
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController
            }
            responder = currentResponder.next
        }
        return nil
    }
}
#elseif canImport(AppKit)
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
#endif
