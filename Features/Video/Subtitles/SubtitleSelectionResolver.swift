#if HOSHI_VIDEO
import Foundation

enum SubtitleSelectionResolver {
    static func lookupText(in sentence: String, utf16Offset: Int, scanLength: Int) -> String {
        let value = sentence as NSString
        guard utf16Offset >= 0, utf16Offset < value.length, scanLength > 0 else {
            return ""
        }
        let length = min(scanLength, value.length - utf16Offset)
        return value
            .substring(with: NSRange(location: utf16Offset, length: length))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
