#if HOSHI_VIDEO
import Foundation

struct SubtitleLookupCandidate: Equatable {
    let text: String
    let utf16Start: Int
}

enum SubtitleSelectionResolver {
    static func lookupText(in sentence: String, utf16Offset: Int, scanLength: Int) -> String {
        lookupCandidate(in: sentence, utf16Offset: utf16Offset, scanLength: scanLength)?.text ?? ""
    }

    static func lookupCandidate(
        in sentence: String,
        utf16Offset: Int,
        scanLength: Int
    ) -> SubtitleLookupCandidate? {
        let value = sentence as NSString
        guard utf16Offset >= 0, utf16Offset < value.length, scanLength > 0 else {
            return nil
        }
        let length = min(scanLength, value.length - utf16Offset)
        let raw = value.substring(with: NSRange(location: utf16Offset, length: length))
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let leadingOffset = (raw as NSString).range(of: text).location
        return SubtitleLookupCandidate(
            text: text,
            utf16Start: utf16Offset + max(0, leadingOffset)
        )
    }

    static func highlightRange(
        for candidate: SubtitleLookupCandidate,
        matchedText: String
    ) -> NSRange? {
        let length = min(candidate.text.utf16.count, matchedText.utf16.count)
        guard length > 0 else { return nil }
        return NSRange(location: candidate.utf16Start, length: length)
    }
}
#endif
