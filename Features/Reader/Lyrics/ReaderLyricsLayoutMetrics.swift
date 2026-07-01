import CoreGraphics

enum ReaderLyricsVisualSpec {
    static let firstLineStartingPosition: CGFloat = 60
    static let selectedLineAnchorY: CGFloat = 0.46
    static let defaultLineSpacing: CGFloat = 25
    static let backgroundVocalsTopSpacing: CGFloat = 15
    static let backgroundVocalsDeselectedScale: CGFloat = 0.9
    static let maxSelectedLines = 2
    static let compactFocusedFontSize: CGFloat = 28
    static let defaultFocusedFontSize: CGFloat = 34
    static let expandedFocusedFontSize: CGFloat = 48
    static let contextFontScale: CGFloat = 0.76
    static let deselectedLineScale: CGFloat = 0.98
    static let touchDownScale: CGFloat = 0.95
    static let highlightLabelAlpha: CGFloat = 0.85
    static let animationHeadstart: Double = 0.1
    static let glowRadius: CGFloat = 5
    static let lineProgressionGradientFeather: CGFloat = 40
    static let lineFitHorizontalMargin: CGFloat = 12
    static let minimumFocusedFittedFontSize: CGFloat = 24
    static let minimumContextFittedFontSize: CGFloat = 18
    static let syllableLift: CGFloat = 2
    static let vocalGroupWidthCoefficient: CGFloat = 0.85
    static let lineTapProgressFreezeDuration: Double = 0.1
    static let lineFinishProgressAnimationDuration: Double = 0.25
}

struct ReaderLyricsLayoutMetrics: Equatable {
    let size: CGSize

    static func fittedLineFontSize(
        baseFontSize: CGFloat,
        measuredTextWidth: CGFloat,
        availableWidth: CGFloat,
        minimumFontSize: CGFloat
    ) -> CGFloat {
        let safeBaseFontSize = max(baseFontSize, 1)
        let safeMeasuredTextWidth = max(measuredTextWidth, 0)
        let effectiveAvailableWidth = max(
            availableWidth - ReaderLyricsVisualSpec.lineFitHorizontalMargin * 2,
            1
        )
        guard safeMeasuredTextWidth > effectiveAvailableWidth else {
            return baseFontSize
        }

        let scaledFontSize = safeBaseFontSize * effectiveAvailableWidth / max(safeMeasuredTextWidth, 1)
        let boundedMinimumFontSize = min(max(minimumFontSize, 1), safeBaseFontSize)
        return min(safeBaseFontSize, max(scaledFontSize, boundedMinimumFontSize))
    }

    private var normalizedWidth: CGFloat { max(size.width, 1) }
    private var normalizedHeight: CGFloat { max(size.height, 1) }

    var chromeHorizontalPadding: CGFloat {
        min(max(normalizedWidth * 0.038, 22), 34)
    }

    var lyricsHorizontalPadding: CGFloat {
        min(max(normalizedWidth * 0.052, 22), 42)
    }

    var contentMaxWidth: CGFloat {
        min(max(normalizedWidth - lyricsHorizontalPadding * 2, 1), 920)
    }

    var headerTopPadding: CGFloat {
        min(max(normalizedHeight * 0.032, 14), 26)
    }

    var bottomPadding: CGFloat {
        min(max(normalizedHeight * 0.032, 16), 28)
    }

    var interSectionSpacing: CGFloat {
        min(max(normalizedHeight * 0.018, 8), 18)
    }

    var lineSpacing: CGFloat {
        ReaderLyricsVisualSpec.defaultLineSpacing
    }

    var focusedFontSize: CGFloat {
        min(
            max(
                min(normalizedHeight * 0.052, normalizedWidth * 0.058),
                ReaderLyricsVisualSpec.compactFocusedFontSize
            ),
            ReaderLyricsVisualSpec.expandedFocusedFontSize
        )
    }

    var contextFontSize: CGFloat {
        min(
            max(focusedFontSize * ReaderLyricsVisualSpec.contextFontScale, 21),
            ReaderLyricsVisualSpec.defaultFocusedFontSize
        )
    }

    var emptyStateFontSize: CGFloat {
        min(max(focusedFontSize * 0.82, 24), 34)
    }

    var focusedLineHeight: CGFloat {
        ceil(focusedFontSize * 1.58)
    }

    var contextLineHeight: CGFloat {
        ceil(contextFontSize * 1.52)
    }

    var playButtonDiameter: CGFloat {
        min(max(normalizedHeight * 0.07, 46), 54)
    }

    var secondaryButtonDiameter: CGFloat {
        min(max(normalizedHeight * 0.055, 36), 42)
    }

    var controlsHeight: CGFloat {
        playButtonDiameter + 108
    }

    var headerHeight: CGFloat {
        54
    }

    var headerReservedHeight: CGFloat {
        headerTopPadding + headerHeight + interSectionSpacing
    }

    var bottomControlsReservedHeight: CGFloat {
        controlsHeight + bottomPadding + interSectionSpacing
    }

    var availableLyricsHeight: CGFloat {
        max(
            focusedLineHeight,
            normalizedHeight
                - headerReservedHeight
                - bottomControlsReservedHeight
        )
    }

    var contextRadius: Int {
        let remaining = max(0, availableLyricsHeight - focusedLineHeight)
        let contextStride = max(contextLineHeight + lineSpacing, 1)
        let contextRows = Int(floor(remaining / contextStride))
        let fitRadius = max(contextRows / 2, 1)
        let heightCap: Int
        if normalizedHeight < 560 {
            heightCap = 1
        } else if normalizedHeight < 720 {
            heightCap = 2
        } else if normalizedHeight < 880 {
            heightCap = 3
        } else {
            heightCap = 4
        }
        return min(fitRadius, heightCap, 4)
    }

    var totalLyricsRowsHeight: CGFloat {
        let rowCount = contextRadius * 2 + 1
        let rows = focusedLineHeight + CGFloat(contextRadius * 2) * contextLineHeight
        let spacing = CGFloat(max(rowCount - 1, 0)) * lineSpacing
        return rows + spacing
    }

    var focusedGlowRadius: CGFloat {
        min(max(ReaderLyricsVisualSpec.glowRadius, focusedFontSize * 0.13), 7)
    }
}

enum ReaderLyricsPopupCoordinateSpace {
    static func popupRect(
        convertedRect: CGRect,
        contentBounds: CGRect,
        isContentViewFlipped: Bool,
        topSafeAreaInset: CGFloat
    ) -> CGRect {
        let x = convertedRect.minX - contentBounds.minX
        let rawY: CGFloat
        if isContentViewFlipped {
            rawY = convertedRect.minY - contentBounds.minY
        } else {
            rawY = contentBounds.maxY - convertedRect.maxY
        }
        let y = max(rawY - max(topSafeAreaInset, 0), 0)
        return CGRect(
            x: x,
            y: y,
            width: max(convertedRect.width, 1),
            height: max(convertedRect.height, 1)
        )
    }
}
