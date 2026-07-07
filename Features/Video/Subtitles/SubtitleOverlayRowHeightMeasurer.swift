#if HOSHI_VIDEO
import AppKit

enum SubtitleOverlayRowHeightMeasurer {
    nonisolated static func height(
        for text: String,
        availableWidth: CGFloat,
        fontFamily: String,
        fontSize: Double,
        fontWeight: Int,
        shadowRadius: Double
    ) -> CGFloat {
        let font = subtitleFont(
            family: fontFamily,
            size: normalizedFontSize(fontSize),
            weight: normalizedFontWeight(fontWeight)
        )
        let constrainedWidth = max(availableWidth, 1)
        let textStorage = NSTextStorage(string: text.isEmpty ? " " : text)
        textStorage.addAttribute(
            .font,
            value: font,
            range: NSRange(location: 0, length: textStorage.length)
        )

        let textContainer = NSTextContainer(
            size: NSSize(width: constrainedWidth, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let fontLineHeight = ceil(font.ascender - font.descender + font.leading)
        let shadowAllowance = min(max(CGFloat(shadowRadius), 0), 10) * 2
        return max(32, ceil(max(usedHeight, fontLineHeight) + shadowAllowance + 2))
    }

    private nonisolated static func subtitleFont(
        family: String,
        size: CGFloat,
        weight: Int
    ) -> NSFont {
        let trimmedFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFamily.isEmpty,
           let font = NSFontManager.shared.font(
                withFamily: trimmedFamily,
                traits: [],
                weight: fontManagerWeight(weight),
                size: size
           ) {
            return font
        }
        return .systemFont(ofSize: size, weight: nsFontWeight(weight))
    }

    private nonisolated static func normalizedFontSize(_ size: Double) -> CGFloat {
        CGFloat(min(max(size, 12), 72))
    }

    private nonisolated static func normalizedFontWeight(_ weight: Int) -> Int {
        min(max(weight, 100), 900)
    }

    private nonisolated static func nsFontWeight(_ weight: Int) -> NSFont.Weight {
        switch normalizedFontWeight(weight) {
        case 100: .ultraLight
        case 200: .thin
        case 300: .light
        case 400: .regular
        case 500: .medium
        case 600: .semibold
        case 700: .bold
        case 800: .heavy
        default: .black
        }
    }

    private nonisolated static func fontManagerWeight(_ weight: Int) -> Int {
        switch normalizedFontWeight(weight) {
        case 100: 2
        case 200: 3
        case 300: 4
        case 400: 5
        case 500: 6
        case 600: 8
        case 700: 9
        case 800: 12
        default: 14
        }
    }
}
#endif
