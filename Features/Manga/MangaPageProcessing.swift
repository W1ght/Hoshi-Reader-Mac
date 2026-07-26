import AppKit
import CoreGraphics
import Foundation
import ImageIO

nonisolated struct MangaPageAnalysis: Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    /// Normalized coordinates with a bottom-left origin.
    let whiteBorderContentRect: CGRect
}

nonisolated struct MangaPageTransform: Equatable, Sendable {
    /// Normalized coordinates with a bottom-left origin.
    let sourceRect: CGRect

    static let identity = MangaPageTransform(
        sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1)
    )
}

nonisolated struct MangaPresentationPage: Equatable, Identifiable, Sendable {
    let index: Int
    let sourcePageIndex: Int
    let sourcePath: String
    let transform: MangaPageTransform

    var id: Int { index }
}

nonisolated struct MangaPageProcessingOptions: Equatable, Sendable {
    let splitsWidePages: Bool
    let readingDirection: MangaReadingDirection
    let cropsWhiteBorders: Bool

    var requiresAnalysis: Bool {
        splitsWidePages || cropsWhiteBorders
    }
}

nonisolated enum MangaPageProcessingPreferences {
    static let splitsWidePagesKey = "mangaReaderSplitsWidePages"
    static let cropsWhiteBordersKey = "mangaReaderCropsWhiteBorders"

    static func splitsWidePages(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: splitsWidePagesKey)
    }

    static func cropsWhiteBorders(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: cropsWhiteBordersKey)
    }

    static func save(
        splitsWidePages: Bool,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(splitsWidePages, forKey: splitsWidePagesKey)
    }

    static func save(
        cropsWhiteBorders: Bool,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(cropsWhiteBorders, forKey: cropsWhiteBordersKey)
    }

}

nonisolated enum MangaPagePresentationResolver {
    static let widePageAspectRatio = 1.25

    static func unprocessedPages(
        sourcePaths: [String]
    ) -> [MangaPresentationPage] {
        sourcePaths.enumerated().map {
            MangaPresentationPage(
                index: $0.offset,
                sourcePageIndex: $0.offset,
                sourcePath: $0.element,
                transform: .identity
            )
        }
    }

    static func pages(
        sourcePaths: [String],
        analyses: [MangaPageAnalysis],
        options: MangaPageProcessingOptions
    ) -> [MangaPresentationPage] {
        guard sourcePaths.count == analyses.count else {
            return unprocessedPages(sourcePaths: sourcePaths)
        }

        var transforms: [
            (
                sourcePageIndex: Int,
                sourcePath: String,
                transform: MangaPageTransform
            )
        ] = []
        for (sourcePageIndex, sourcePath) in sourcePaths.enumerated() {
            let analysis = analyses[sourcePageIndex]
            let contentRect = options.cropsWhiteBorders
                ? clampedUnitRect(analysis.whiteBorderContentRect)
                : CGRect(x: 0, y: 0, width: 1, height: 1)
            let contentWidth = CGFloat(analysis.pixelWidth) * contentRect.width
            let contentHeight = CGFloat(analysis.pixelHeight) * contentRect.height
            let isWide = contentHeight > 0
                && contentWidth / contentHeight >= widePageAspectRatio

            if options.splitsWidePages, isWide {
                let left = CGRect(
                    x: contentRect.minX,
                    y: contentRect.minY,
                    width: contentRect.width / 2,
                    height: contentRect.height
                )
                let right = CGRect(
                    x: contentRect.midX,
                    y: contentRect.minY,
                    width: contentRect.maxX - contentRect.midX,
                    height: contentRect.height
                )
                let startsOnRight = options.readingDirection == .rightToLeft
                let orderedRects = startsOnRight ? [right, left] : [left, right]
                transforms.append(contentsOf: orderedRects.map {
                    (
                        sourcePageIndex,
                        sourcePath,
                        MangaPageTransform(sourceRect: $0)
                    )
                })
            } else {
                transforms.append(
                    (
                        sourcePageIndex,
                        sourcePath,
                        MangaPageTransform(sourceRect: contentRect)
                    )
                )
            }
        }

        return transforms.enumerated().map {
            MangaPresentationPage(
                index: $0.offset,
                sourcePageIndex: $0.element.sourcePageIndex,
                sourcePath: $0.element.sourcePath,
                transform: $0.element.transform
            )
        }
    }

    private static func clampedUnitRect(_ rect: CGRect) -> CGRect {
        let resolved = rect.standardized.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        guard !resolved.isNull,
              resolved.width > 0,
              resolved.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return resolved
    }
}

nonisolated final class MangaRenderedPageImage: @unchecked Sendable {
    let image: NSImage

    init(image: NSImage) {
        self.image = image
    }
}

nonisolated enum MangaPageProcessorError: LocalizedError {
    case imageUnavailable

    var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            String(localized: "The manga page could not be loaded.")
        }
    }
}

nonisolated enum MangaPageProcessor {
    private static let analysisMaximumDimension = 512
    private static let maximumTrimFraction = 0.20
    private static let whitePixelRatio = 0.985

    static func analyze(_ data: Data) throws -> MangaPageAnalysis {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let rawWidth = number(properties[kCGImagePropertyPixelWidth]),
              let rawHeight = number(properties[kCGImagePropertyPixelHeight]),
              rawWidth > 0,
              rawHeight > 0,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: analysisMaximumDimension,
                  ] as CFDictionary
              ) else {
            throw MangaPageProcessorError.imageUnavailable
        }

        let orientation = number(properties[kCGImagePropertyOrientation]) ?? 1
        let swapsDimensions = [5, 6, 7, 8].contains(orientation)
        return MangaPageAnalysis(
            pixelWidth: swapsDimensions ? rawHeight : rawWidth,
            pixelHeight: swapsDimensions ? rawWidth : rawHeight,
            whiteBorderContentRect: detectWhiteBorderContentRect(in: thumbnail)
        )
    }

    static func renderedImage(
        from data: Data,
        transform: MangaPageTransform
    ) throws -> MangaRenderedPageImage {
        if transform == .identity, let image = NSImage(data: data) {
            return MangaRenderedPageImage(image: image)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let rawWidth = number(properties[kCGImagePropertyPixelWidth]),
              let rawHeight = number(properties[kCGImagePropertyPixelHeight]) else {
            throw MangaPageProcessorError.imageUnavailable
        }
        let maximumDimension = max(rawWidth, rawHeight)
        guard maximumDimension > 0,
              let orientedImage = CGImageSourceCreateThumbnailAtIndex(
                  source,
                  0,
                  [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                  ] as CFDictionary
              ),
              let croppedImage = crop(
                  orientedImage,
                  to: transform.sourceRect
              ) else {
            throw MangaPageProcessorError.imageUnavailable
        }

        return MangaRenderedPageImage(
            image: NSImage(
                cgImage: croppedImage,
                size: NSSize(
                    width: croppedImage.width,
                    height: croppedImage.height
                )
            )
        )
    }

    static func regions(
        _ regions: [MangaOCRTextRegion],
        for page: MangaPresentationPage
    ) -> [MangaOCRTextRegion] {
        let sourceRect = page.transform.sourceRect
        guard sourceRect.width > 0, sourceRect.height > 0 else { return [] }

        return regions.compactMap { region in
            let bounds = region.normalizedBounds
            guard sourceRect.contains(
                CGPoint(x: bounds.midX, y: bounds.midY)
            ) else {
                return nil
            }
            let clipped = bounds.intersection(sourceRect)
            guard !clipped.isNull,
                  clipped.width > 0,
                  clipped.height > 0 else {
                return nil
            }
            let local = CGRect(
                x: (clipped.minX - sourceRect.minX) / sourceRect.width,
                y: (clipped.minY - sourceRect.minY) / sourceRect.height,
                width: clipped.width / sourceRect.width,
                height: clipped.height / sourceRect.height
            )
            let suffix = "-presentation-\(page.index)"
            return MangaOCRTextRegion(
                id: region.id + suffix,
                pageIndex: region.pageIndex,
                blockID: region.blockID + suffix,
                lineID: region.lineID + suffix,
                sentence: region.sentence,
                utf16Offset: region.utf16Offset,
                isVertical: region.isVertical,
                normalizedBounds: local
            )
        }
    }

    private static func number(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func crop(
        _ image: CGImage,
        to normalizedRect: CGRect
    ) -> CGImage? {
        let rect = normalizedRect.standardized.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let minX = floor(rect.minX * width)
        let maxX = ceil(rect.maxX * width)
        let minYFromTop = floor((1 - rect.maxY) * height)
        let maxYFromTop = ceil((1 - rect.minY) * height)
        let pixelRect = CGRect(
            x: minX,
            y: minYFromTop,
            width: maxX - minX,
            height: maxYFromTop - minYFromTop
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard pixelRect.width >= 1, pixelRect.height >= 1 else { return nil }
        return image.cropping(to: pixelRect)
    }

    private static func detectWhiteBorderContentRect(
        in image: CGImage
    ) -> CGRect {
        let width = image.width
        let height = image.height
        guard width > 2, height > 2 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        let maximumHorizontalTrim = max(
            1,
            Int(CGFloat(width) * maximumTrimFraction)
        )
        let maximumVerticalTrim = max(
            1,
            Int(CGFloat(height) * maximumTrimFraction)
        )
        var left = 0
        while left < maximumHorizontalTrim,
              whiteRatioInColumn(
                  left,
                  pixels: pixels,
                  width: width,
                  height: height
              ) >= whitePixelRatio {
            left += 1
        }
        var right = width - 1
        while width - 1 - right < maximumHorizontalTrim,
              right > left,
              whiteRatioInColumn(
                  right,
                  pixels: pixels,
                  width: width,
                  height: height
              ) >= whitePixelRatio {
            right -= 1
        }
        var top = 0
        while top < maximumVerticalTrim,
              whiteRatioInRow(
                  top,
                  pixels: pixels,
                  width: width
              ) >= whitePixelRatio {
            top += 1
        }
        var bottom = height - 1
        while height - 1 - bottom < maximumVerticalTrim,
              bottom > top,
              whiteRatioInRow(
                  bottom,
                  pixels: pixels,
                  width: width
              ) >= whitePixelRatio {
            bottom -= 1
        }

        let contentWidth = right - left + 1
        let contentHeight = bottom - top + 1
        guard contentWidth >= Int(CGFloat(width) * 0.60),
              contentHeight >= Int(CGFloat(height) * 0.60) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(
            x: CGFloat(left) / CGFloat(width),
            y: CGFloat(height - 1 - bottom) / CGFloat(height),
            width: CGFloat(contentWidth) / CGFloat(width),
            height: CGFloat(contentHeight) / CGFloat(height)
        )
    }

    private static func whiteRatioInColumn(
        _ x: Int,
        pixels: [UInt8],
        width: Int,
        height: Int
    ) -> Double {
        var whiteCount = 0
        for y in 0..<height where isWhitePixel(
            at: (y * width + x) * 4,
            pixels: pixels
        ) {
            whiteCount += 1
        }
        return Double(whiteCount) / Double(height)
    }

    private static func whiteRatioInRow(
        _ y: Int,
        pixels: [UInt8],
        width: Int
    ) -> Double {
        var whiteCount = 0
        let rowStart = y * width * 4
        for x in 0..<width where isWhitePixel(
            at: rowStart + x * 4,
            pixels: pixels
        ) {
            whiteCount += 1
        }
        return Double(whiteCount) / Double(width)
    }

    private static func isWhitePixel(
        at offset: Int,
        pixels: [UInt8]
    ) -> Bool {
        let red = Double(pixels[offset]) / 255
        let green = Double(pixels[offset + 1]) / 255
        let blue = Double(pixels[offset + 2]) / 255
        if pixels[offset + 3] < 16 {
            return true
        }
        let luminance = red * 0.299 + green * 0.587 + blue * 0.114
        let chroma = max(red, green, blue) - min(red, green, blue)
        return luminance >= 0.90 && chroma <= 0.18
    }
}
