import AppKit
import Foundation

enum PopupSystemSymbolRenderer {
    static let duplicateSymbolDataURL = pngDataURL(symbolName: "plus.square.on.square")
    static let viewNoteSymbolDataURL = pngDataURL(symbolName: "magnifyingglass")

    static func pngDataURL(
        symbolName: String,
        pointSize: CGFloat = 13,
        canvasPointSize: CGFloat = 28,
        pixelScale: Int = 3
    ) -> String? {
        guard pixelScale > 0,
              let baseImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil),
              let symbolImage = baseImage.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
              ),
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(canvasPointSize) * pixelScale,
                pixelsHigh: Int(canvasPointSize) * pixelScale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
              ) else {
            return nil
        }

        bitmap.size = NSSize(width: canvasPointSize, height: canvasPointSize)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: canvasPointSize, height: canvasPointSize).fill(using: .copy)
        NSColor.black.set()
        symbolImage.draw(
            at: NSPoint(
                x: (canvasPointSize - symbolImage.size.width) / 2,
                y: (canvasPointSize - symbolImage.size.height) / 2
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }
}
