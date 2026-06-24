#if HOSHI_VIDEO
import AppKit
import AVFoundation
import Foundation

protocol VideoThumbnailGenerating {
    func thumbnailPNGData(for url: URL) async throws -> Data
}

struct AVFoundationVideoThumbnailGenerator: VideoThumbnailGenerating {
    func thumbnailPNGData(for url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        let (cgImage, _) = try await generator.image(
            at: CMTime(seconds: 5, preferredTimescale: 600)
        )
        let image = NSImage(cgImage: cgImage, size: .zero)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw VideoThumbnailStoreError.encodingFailed
        }
        return pngData
    }
}

enum VideoThumbnailStoreError: Error {
    case encodingFailed
}

final class VideoThumbnailStore {
    private let cacheDirectory: URL
    private let generator: any VideoThumbnailGenerating
    private let fileManager: FileManager

    init(
        cacheDirectory: URL? = nil,
        generator: any VideoThumbnailGenerating = AVFoundationVideoThumbnailGenerator(),
        fileManager: FileManager = .default
    ) {
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory(fileManager: fileManager)
        self.generator = generator
        self.fileManager = fileManager
    }

    func thumbnailURL(for item: VideoLibraryItem) async -> URL? {
        let url = cacheURL(for: item)
        if fileManager.fileExists(atPath: url.path) {
            return url
        }
        guard fileManager.fileExists(atPath: item.url.path) else {
            return nil
        }
        do {
            let data = try await generator.thumbnailPNGData(for: item.url)
            try fileManager.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func cacheURL(for item: VideoLibraryItem) -> URL {
        cacheDirectory.appendingPathComponent("\(cacheKey(for: item)).png")
    }

    func invalidateThumbnail(for item: VideoLibraryItem) {
        try? fileManager.removeItem(at: cacheURL(for: item))
    }

    func cacheKey(for item: VideoLibraryItem) -> String {
        let modified = item.modifiedAt?.timeIntervalSince1970 ?? 0
        let identity = "\(item.path)|\(item.fileSize)|\(modified)"
        return Self.fnv1a64(identity)
    }

    private static func defaultCacheDirectory(fileManager: FileManager) -> URL {
        let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent("VideoThumbnails", isDirectory: true)
    }

    private static func fnv1a64(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
#endif
