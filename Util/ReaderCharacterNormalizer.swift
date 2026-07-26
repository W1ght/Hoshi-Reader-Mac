//
//  ReaderCharacterNormalizer.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

nonisolated enum ReaderCharacterNormalizer {
    private static let numericCharacterReferenceRegex = try! NSRegularExpression(
        pattern: #"&#(?:([0-9]+)|[xX]([0-9A-Fa-f]+));"#
    )

    static func filteredText(from markup: String) -> String {
        var text = markup
        if let bodyRange = text.range(of: "(?s)<body.*?</body>", options: .regularExpression) {
            text = String(text[bodyRange])
        }
        text = text.replacingOccurrences(of: "(?s)<rt[^>]*>.*?</rt>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodedCharacterReferences(in: text)
        text = text.replacingOccurrences(
            of: "[^0-9A-Za-z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚａ-ｚｦ-ﾝ\\p{Radical}\\p{Unified_Ideograph}]",
            with: "",
            options: .regularExpression
        )
        return text
    }

    static func readableCharacterCount(in text: String) -> Int {
        filteredText(from: text).count
    }

    static func decodedCharacterReferences(in text: String) -> String {
        let source = text as NSString
        let matches = numericCharacterReferenceRegex.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        let result = NSMutableString(string: text)
        for match in matches.reversed() {
            let decimalRange = match.range(at: 1)
            let hexadecimalRange = match.range(at: 2)
            let value: UInt32?
            if decimalRange.location != NSNotFound {
                value = UInt32(source.substring(with: decimalRange), radix: 10)
            } else if hexadecimalRange.location != NSNotFound {
                value = UInt32(source.substring(with: hexadecimalRange), radix: 16)
            } else {
                value = nil
            }
            let replacement = value
                .flatMap(UnicodeScalar.init)
                .map(String.init)
                ?? ""
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return (result as String)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
