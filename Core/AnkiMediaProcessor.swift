import AppKit
import Foundation

struct AnkiProcessedImage {
    let data: Data
    let fileExtension: String
}

enum AnkiMediaProcessor {
    static func image(
        data: Data,
        sourceExtension: String,
        compress: Bool,
        quality: Double = 0.80
    ) -> AnkiProcessedImage {
        let fallbackExtension = sourceExtension.isEmpty ? "png" : sourceExtension.lowercased()
        guard compress,
              let bitmap = NSBitmapImageRep(data: data),
              let jpeg = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: min(0.95, max(0.40, quality))]
              )
        else {
            return AnkiProcessedImage(data: data, fileExtension: fallbackExtension)
        }
        return AnkiProcessedImage(data: jpeg, fileExtension: "jpg")
    }
}
