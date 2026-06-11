//
//  CSSEditorTextViewBridge.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import SwiftUIIntrospect
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct CSSEditorTextViewHandle {
    let selectedRange: () -> NSRange?
    let insertText: (String) -> String?
    let setCursorLocation: (Int) -> Void
}

extension View {
    #if canImport(UIKit)
    func cssEditorTextView(handle: Binding<CSSEditorTextViewHandle?>) -> some View {
        introspect(.textEditor, on: .iOS(.v18, .v26)) { uiTextView in
            uiTextView.smartQuotesType = .no
            uiTextView.smartDashesType = .no
            handle.wrappedValue = CSSEditorTextViewHandle(
                selectedRange: { [weak uiTextView] in
                    uiTextView?.selectedRange
                },
                insertText: { [weak uiTextView] insertedText in
                    guard let uiTextView else {
                        return nil
                    }
                    uiTextView.insertText(insertedText)
                    uiTextView.becomeFirstResponder()
                    return uiTextView.text
                },
                setCursorLocation: { [weak uiTextView] cursorLocation in
                    guard let uiTextView else {
                        return
                    }
                    uiTextView.selectedRange = NSRange(location: cursorLocation, length: 0)
                    uiTextView.becomeFirstResponder()
                }
            )
        }
    }
    #else
    func cssEditorTextView(handle: Binding<CSSEditorTextViewHandle?>) -> some View {
        background(CSSEditorTextViewAccessor(handle: handle))
    }
    #endif
}

#if canImport(AppKit) && !canImport(UIKit)
private struct CSSEditorTextViewAccessor: NSViewRepresentable {
    @Binding var handle: CSSEditorTextViewHandle?

    func makeNSView(context: Context) -> AccessorView {
        let view = AccessorView()
        view.onResolve = { textView in
            configure(textView)
        }
        return view
    }

    func updateNSView(_ nsView: AccessorView, context: Context) {
        nsView.onResolve = { textView in
            configure(textView)
        }
        nsView.resolveSoon()
    }

    private func configure(_ textView: NSTextView) {
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        handle = CSSEditorTextViewHandle(
            selectedRange: { [weak textView] in
                textView?.selectedRange()
            },
            insertText: { [weak textView] insertedText in
                guard let textView else {
                    return nil
                }
                textView.insertText(insertedText, replacementRange: textView.selectedRange())
                textView.window?.makeFirstResponder(textView)
                return textView.string
            },
            setCursorLocation: { [weak textView] cursorLocation in
                guard let textView else {
                    return
                }
                textView.setSelectedRange(NSRange(location: cursorLocation, length: 0))
                textView.window?.makeFirstResponder(textView)
            }
        )
    }

    final class AccessorView: NSView {
        var onResolve: ((NSTextView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveSoon()
        }

        func resolveSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.resolve()
            }
        }

        private func resolve() {
            guard let textView = nearestTextView() else {
                return
            }
            onResolve?(textView)
        }

        private func nearestTextView() -> NSTextView? {
            var candidate: NSView? = self
            while let view = candidate {
                if let textView = view.firstDescendant(of: NSTextView.self) {
                    return textView
                }
                candidate = view.superview
            }
            return window?.contentView?.firstDescendant(of: NSTextView.self)
        }
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let matched = self as? T {
            return matched
        }
        for subview in subviews {
            if let matched = subview.firstDescendant(of: type) {
                return matched
            }
        }
        return nil
    }
}
#endif
