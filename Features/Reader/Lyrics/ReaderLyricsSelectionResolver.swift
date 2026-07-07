import Foundation

struct ReaderLyricsLookupCandidate: Equatable {
    let text: String
    let utf16Start: Int
}

enum ReaderLyricsSelectionResolver {
    static func lookupCandidate(
        in sentence: String,
        utf16Offset: Int,
        scanLength: Int
    ) -> ReaderLyricsLookupCandidate? {
        lookupCandidates(
            in: sentence,
            utf16Offset: utf16Offset,
            scanLength: scanLength,
            maxBackwardDistance: 0
        ).first
    }

    static func lookupCandidates(
        in sentence: String,
        utf16Offset: Int,
        scanLength: Int,
        maxBackwardDistance: Int = 6
    ) -> [ReaderLyricsLookupCandidate] {
        let value = sentence as NSString
        guard utf16Offset >= 0,
              utf16Offset < value.length,
              scanLength > 0 else {
            return []
        }

        var candidates: [ReaderLyricsLookupCandidate] = []
        var seen = Set<String>()

        func appendCandidate(startingAt offset: Int) {
            guard let candidate = lookupCandidateStartingAt(
                offset,
                in: value,
                scanLength: scanLength
            ) else { return }
            let key = "\(candidate.utf16Start):\(candidate.text)"
            guard seen.insert(key).inserted else { return }
            candidates.append(candidate)
        }

        appendCandidate(startingAt: utf16Offset)

        guard maxBackwardDistance > 0,
              let clickedIndex = stringIndex(forUTF16Offset: utf16Offset, in: sentence),
              isLookupFallbackCharacter(sentence[clickedIndex]) else {
            return candidates
        }

        var cursor = clickedIndex
        var distance = 0
        while distance < maxBackwardDistance, cursor > sentence.startIndex {
            let previous = sentence.index(before: cursor)
            guard isLookupFallbackCharacter(sentence[previous]) else { break }
            appendCandidate(startingAt: previous.utf16Offset(in: sentence))
            cursor = previous
            distance += 1
        }

        return candidates
    }

    private static func lookupCandidateStartingAt(
        _ utf16Offset: Int,
        in value: NSString,
        scanLength: Int
    ) -> ReaderLyricsLookupCandidate? {
        guard utf16Offset >= 0,
              utf16Offset < value.length,
              scanLength > 0 else {
            return nil
        }

        let length = min(scanLength, value.length - utf16Offset)
        let raw = value.substring(with: NSRange(location: utf16Offset, length: length))
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let leadingOffset = (raw as NSString).range(of: text).location
        return ReaderLyricsLookupCandidate(
            text: text,
            utf16Start: utf16Offset + max(0, leadingOffset)
        )
    }

    private static func stringIndex(
        forUTF16Offset utf16Offset: Int,
        in sentence: String
    ) -> String.Index? {
        let utf16 = sentence.utf16
        guard let utf16Index = utf16.index(
            utf16.startIndex,
            offsetBy: utf16Offset,
            limitedBy: utf16.endIndex
        ) else {
            return nil
        }
        return String.Index(utf16Index, within: sentence)
    }

    private static func isLookupFallbackCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter,
                 .lowercaseLetter,
                 .titlecaseLetter,
                 .modifierLetter,
                 .otherLetter,
                 .decimalNumber,
                 .letterNumber,
                 .otherNumber:
                return true
            default:
                return false
            }
        }
    }

    static func highlightRange(
        for candidate: ReaderLyricsLookupCandidate,
        matchedText: String
    ) -> NSRange? {
        let length = min(candidate.text.utf16.count, matchedText.utf16.count)
        guard length > 0 else { return nil }
        return NSRange(location: candidate.utf16Start, length: length)
    }
}
