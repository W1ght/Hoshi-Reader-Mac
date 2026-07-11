import AppKit
import Foundation

private func expect(_ c: @autoclosure () -> Bool, _ m: String) {
    guard c() else { fputs("FAIL: \(m)\\n", stderr); exit(1) }
}

@main
private struct VideoScreenshotCompressionTests {
    static func main() throws {
        let json = #"{"selectedDeck":null,"selectedNoteType":null,"allowDupes":false,"compactGlossaries":false,"embedMedia":false,"fieldMappings":{},"tags":"","duplicateScope":"collection","checkAllModels":false}"#
        let profile = try JSONDecoder().decode(AnkiProfileConfig.self, from: Data(json.utf8))
        expect(profile.effectiveCompressVideoScreenshots, "legacy profile defaults compression on")
        let names = VideoMiningContext.deterministicMediaFilenames(
            videoURL: URL(fileURLWithPath: "/tmp/episode.mkv"),
            cueStart: 1, cueEnd: 2, audioStart: 1, audioEnd: 2,
            screenshotFormat: .jpeg
        )
        expect(names.screenshot.hasSuffix(".jpg"), "JPEG names use .jpg")

        let store = VideoMiningMediaStore()
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 16,
            pixelsHigh: 16,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        memset(bitmap.bitmapData!, 0x7f, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let source = store.screenshotURL()
        try bitmap.representation(using: .png, properties: [:])!.write(to: source)
        let jpeg = try store.preparedScreenshot(at: source, compress: true)
        expect(jpeg.pathExtension == "jpg", "compressed output is .jpg")
        let jpegData = try Data(contentsOf: jpeg)
        expect(
            jpegData.starts(with: [0xFF, 0xD8]),
            "JPEG magic bytes"
        )

        let png = store.screenshotURL()
        try bitmap.representation(using: .png, properties: [:])!.write(to: png)
        let retained = try store.preparedScreenshot(at: png, compress: false)
        expect(retained.pathExtension == "png", "opt-out retains .png")
        let pngData = try Data(contentsOf: retained)
        expect(
            pngData.starts(with: [0x89, 0x50, 0x4E, 0x47]),
            "PNG magic bytes"
        )
        print("Video screenshot compression tests passed")
    }
}
