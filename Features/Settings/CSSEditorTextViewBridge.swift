//
//  CSSEditorTextViewBridge.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftUI
import SwiftUIIntrospect
import UIKit

struct CSSEditorTextViewHandle {
    let selectedRange: () -> NSRange?
    let insertText: (String) -> String?
    let setCursorLocation: (Int) -> Void
}

extension View {
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
}
