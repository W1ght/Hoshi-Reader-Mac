//
//  CSSEditorView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct CSSEditorView: View {
    let dictionaryManager = DictionaryManager.shared
    let fontManager = FontManager.shared
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @State private var textViewHandle: CSSEditorTextViewHandle?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .focused($isFocused)
                .cssEditorTextView(handle: $textViewHandle)
        }
    }

    private var toolbar: some View {
        HStack {
            fontMenu
                .conditionalGlassEffect()
            dictionaryMenu
                .conditionalGlassEffect()
            Spacer()
            if isFocused {
                Button {
                    isFocused = false
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .conditionalGlassEffect()
            }
        }
        .padding(8)
    }

    private var fontMenu: some View {
        Menu {
            ForEach(fontManager.allFonts, id: \.self) { fontName in
                Button(fontName) {
                    let cssFontName = fontManager.cssFontName(name: fontName)
                    insertText("font-family: \"\(cssFontName)\" !important;")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "textformat.size.larger.ja")
                Text("Font")
            }
            .font(.system(size: 16))
            .foregroundStyle(.primary)
            .frame(height: 44)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private var dictionaryMenu: some View {
        Menu {
            ForEach(dictionaryManager.termDictionaries) { dict in
                Button(dict.index.title) {
                    insertSelector(for: dict.index.title)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "character.book.closed.ja")
                Text("Insert Selector")
            }
            .font(.system(size: 16))
            .foregroundStyle(.primary)
            .frame(height: 44)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
    }

    private func insertText(_ insertedText: String) {
        guard let updatedText = textViewHandle?.insertText(insertedText) else {
            text += insertedText
            return
        }

        text = updatedText
        isFocused = true
    }

    private func insertSelector(for dictionaryTitle: String) {
        let snippet = CSSEditorSnippet.selector(for: dictionaryTitle)
        let selectedRange = validSelectedRange() ?? NSRange(location: text.utf16.count, length: 0)

        if let range = Range(selectedRange, in: text) {
            text.replaceSubrange(range, with: snippet.text)
        } else {
            text += snippet.text
        }

        let cursorLocation = selectedRange.location + snippet.cursorOffset
        DispatchQueue.main.async {
            textViewHandle?.setCursorLocation(cursorLocation)
            isFocused = true
        }
    }

    private func validSelectedRange() -> NSRange? {
        guard let selectedRange = textViewHandle?.selectedRange(),
              selectedRange.location != NSNotFound,
              selectedRange.location <= text.utf16.count,
              selectedRange.location + selectedRange.length <= text.utf16.count else {
            return nil
        }
        return selectedRange
    }
}
