import AppKit
import Foundation
import ImageIO

struct AnkiProcessedImage {
    let data: Data
    let fileExtension: String
}

enum AnkiMediaProcessor {
    static func image(
        data: Data,
        sourceExtension: String,
        compress: Bool,
        format: AnkiImageCompressionFormat = .jpeg,
        quality: Double = 0.80
    ) -> AnkiProcessedImage {
        let fallbackExtension = sourceExtension.isEmpty ? "png" : sourceExtension.lowercased()
        guard compress, let bitmap = NSBitmapImageRep(data: data) else {
            return AnkiProcessedImage(data: data, fileExtension: fallbackExtension)
        }

        let clampedQuality = min(0.95, max(0.40, quality))
        switch format {
        case .jpeg:
            guard let jpeg = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: clampedQuality]
            ) else {
                return AnkiProcessedImage(data: data, fileExtension: fallbackExtension)
            }
            return AnkiProcessedImage(data: jpeg, fileExtension: format.fileExtension)
        case .avif:
            guard let cgImage = bitmap.cgImage else {
                return AnkiProcessedImage(data: data, fileExtension: fallbackExtension)
            }
            let destinationData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                destinationData,
                "public.avif" as CFString,
                1,
                nil
            ) else {
                return AnkiProcessedImage(data: data, fileExtension: fallbackExtension)
            }
            CGImageDestinationAddImage(
                destination,
                cgImage,
                [kCGImageDestinationLossyCompressionQuality: clampedQuality] as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else {
                return AnkiProcessedImage(data: data, fileExtension: fallbackExtension)
            }
            return AnkiProcessedImage(data: destinationData as Data, fileExtension: format.fileExtension)
        }
    }
}
