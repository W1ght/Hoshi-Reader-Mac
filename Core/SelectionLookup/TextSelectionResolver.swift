import Foundation

nonisolated struct TextLookupCandidate: Equatable, Sendable {
    let text: String
    let utf16Start: Int
}

nonisolated enum TextSelectionResolver {
    private static let englishScanDelimiters = Set(
        "\"“”„‟'‘’‚‛«»‹›!?—–-‐‑‒/\\|@#$%^&*_+=~`<>".utf16
    )
    private static let englishWordInternalDelimiters = Set("'’`-‐‑".utf16)
    private static let sharedScanDelimiters = Set(
        "。、！？…‥「」『』（）()【】〈〉《》〔〕｛｝{}［］[]・：；:;，,.─\n\r".utf16
    )

    static func lookupText(
        in sentence: String,
        utf16Offset: Int,
        scanLength: Int,
        contentLanguage: ContentLanguageProfile
    ) -> String {
        lookupCandidate(
            in: sentence,
            utf16Offset: utf16Offset,
            scanLength: scanLength,
            contentLanguage: contentLanguage
        )?.text ?? ""
    }

    static func lookupCandidate(
        in sentence: String,
        utf16Offset: Int,
        scanLength: Int,
        contentLanguage: ContentLanguageProfile
    ) -> TextLookupCandidate? {
        let value = sentence as NSString
        guard utf16Offset >= 0, utf16Offset < value.length, scanLength > 0 else {
            return nil
        }

        let candidateStart: Int
        switch contentLanguage {
        case .japanese:
            candidateStart = utf16Offset
        case .english:
            candidateStart = englishWordStart(in: value, from: utf16Offset)
        }

        let length = min(scanLength, value.length - candidateStart)
        let raw = value.substring(with: NSRange(location: candidateStart, length: length))
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let leadingOffset = (raw as NSString).range(of: text).location
        return TextLookupCandidate(
            text: text,
            utf16Start: candidateStart + max(0, leadingOffset)
        )
    }

    static func highlightRange(
        for candidate: TextLookupCandidate,
        matchedText: String
    ) -> NSRange? {
        let length = min(candidate.text.utf16.count, matchedText.utf16.count)
        guard length > 0 else { return nil }
        return NSRange(location: candidate.utf16Start, length: length)
    }

    private static func englishWordStart(in value: NSString, from utf16Offset: Int) -> Int {
        var offset = utf16Offset
        while offset > 0, !isEnglishHitBoundary(in: value, at: offset - 1) {
            offset -= 1
        }
        return offset
    }

    private static func isEnglishHitBoundary(in value: NSString, at offset: Int) -> Bool {
        let codeUnit = value.character(at: offset)
        if let scalar = UnicodeScalar(codeUnit), CharacterSet.whitespacesAndNewlines.contains(scalar) {
            return true
        }
        if sharedScanDelimiters.contains(codeUnit) {
            return true
        }
        guard englishScanDelimiters.contains(codeUnit) else {
            return false
        }
        return !isInternalEnglishWordDelimiter(in: value, at: offset)
    }

    private static func isInternalEnglishWordDelimiter(in value: NSString, at offset: Int) -> Bool {
        guard englishWordInternalDelimiters.contains(value.character(at: offset)),
              offset > 0,
              offset + 1 < value.length else {
            return false
        }
        return isASCIIAlphaNumeric(value.character(at: offset - 1))
            && isASCIIAlphaNumeric(value.character(at: offset + 1))
    }

    private static func isASCIIAlphaNumeric(_ codeUnit: unichar) -> Bool {
        (48...57).contains(codeUnit)
            || (65...90).contains(codeUnit)
            || (97...122).contains(codeUnit)
    }
}
