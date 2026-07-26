import AppKit
import Foundation

@main
private enum MangaGoogleLensSmokeTest {
    static func main() async throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 900,
            pixelsHigh: 1_200,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw MangaOCRError.imageUnavailable
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 900, height: 1_200).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSString(string: "日本語を勉強します\n漫画を読みます").draw(
            in: NSRect(x: 60, y: 420, width: 780, height: 360),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 96, weight: .semibold),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
            ]
        )
        NSGraphicsContext.restoreGraphicsState()
        guard let jpeg = bitmap.representation(
            using: NSBitmapImageRep.FileType.jpeg,
            properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.92]
        ) else {
            throw MangaOCRError.imageUnavailable
        }

        let regions = try await MangaOCRService.shared.recognizeText(
            in: jpeg,
            key: MangaOCRCacheKey(
                itemID: "generated-google-lens-smoke-test",
                pageIndex: 0,
                pagePath: "generated.jpg",
                modifiedAt: nil
            ),
            pagePaths: ["generated.jpg"]
        )
        let blocks = Dictionary(grouping: regions) { region in region.blockID }
            .values
            .compactMap { $0.first?.sentence }
        print("Google Lens live smoke test passed: \(blocks.joined(separator: " / "))")
    }
}
