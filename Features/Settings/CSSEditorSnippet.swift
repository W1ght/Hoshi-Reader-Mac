//
//  CSSEditorSnippet.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum CSSEditorSnippet {
    static func selector(for dictionaryTitle: String) -> (text: String, cursorOffset: Int) {
        let prefix = "[data-dictionary=\"\(cssStringEscaped(dictionaryTitle))\"] {\n    "
        let suffix = "\n}\n\n"
        return (prefix + suffix, prefix.utf16.count)
    }

    private static func cssStringEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
