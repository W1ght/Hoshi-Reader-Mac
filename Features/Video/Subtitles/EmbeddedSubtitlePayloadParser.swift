#if HOSHI_VIDEO
import Foundation

enum EmbeddedSubtitlePayloadParser {
    nonisolated static func supportsText(codec: String?) -> Bool {
        guard let codec else { return false }
        switch codec.lowercased() {
        case "ass", "ssa", "subrip", "srt", "text", "webvtt", "mov_text":
            return true
        default:
            return false
        }
    }

    nonisolated static func text(from payload: String, codec: String?) -> String {
        var text = payload
        if let codec, codec.lowercased() == "ass" || codec.lowercased() == "ssa" {
            var commaCount = 0
            if let textStart = text.indices.first(where: { index in
                guard text[index] == "," else { return false }
                commaCount += 1
                return commaCount == 8
            }) {
                text = String(text[text.index(after: textStart)...])
            }
            text = text.replacing(#/\{[^}]*\}/#, with: "")
        }
        return text
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")
            .replacing(#/<[^>]+>/#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
