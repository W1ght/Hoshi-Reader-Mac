import AppKit
import Foundation

struct VideoMiningMediaStore {
    private static var directMediaInFlight: Set<String> = []

    let directory: URL

    init(fileManager: FileManager = .default) {
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("HoshiVideoMining", isDirectory: true)
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let expiration = Date().addingTimeInterval(-24 * 60 * 60)
        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files {
            let modified = try? file.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            if modified.map({ $0 < expiration }) == true {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    func screenshotURL() -> URL {
        directory.appendingPathComponent("hoshi-video-\(UUID().uuidString).png")
    }

    func animatedScreenshotURL() -> URL {
        directory.appendingPathComponent("hoshi-video-\(UUID().uuidString).avif")
    }

    func preparedScreenshot(
        at sourceURL: URL,
        compress: Bool,
        format: AnkiImageCompressionFormat = .jpeg,
        quality: Double = 0.80
    ) throws -> URL {
        guard compress else { return sourceURL }
        let source = try Data(contentsOf: sourceURL)
        let processed = AnkiMediaProcessor.image(
            data: source,
            sourceExtension: sourceURL.pathExtension,
            compress: true,
            format: format,
            quality: quality
        )
        guard processed.fileExtension == format.fileExtension else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let destination = sourceURL
            .deletingPathExtension()
            .appendingPathExtension(processed.fileExtension)
        try processed.data.write(to: destination, options: .atomic)
        try FileManager.default.removeItem(at: sourceURL)
        return destination
    }

    func audioClipURL() -> URL {
        directory.appendingPathComponent("hoshi-video-\(UUID().uuidString).wav")
    }

    func directMediaURL(filename: String, in ankiMediaDirectory: URL) -> URL {
        ankiMediaDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    func claimDirectMediaGeneration(at destination: URL) -> Bool {
        let path = destination.standardizedFileURL.path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: path),
              !Self.directMediaInFlight.contains(path) else {
            return false
        }
        Self.directMediaInFlight.insert(path)
        return true
    }

    func finishDirectMediaGeneration(at destination: URL) {
        Self.directMediaInFlight.remove(
            destination.standardizedFileURL.path(percentEncoded: false)
        )
    }

    func replaceMediaItem(at tempURL: URL, destination: URL) throws {
        do {
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
}
