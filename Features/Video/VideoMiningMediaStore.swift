#if HOSHI_VIDEO
import Foundation

struct VideoMiningMediaStore {
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

    func audioClipURL() -> URL {
        directory.appendingPathComponent("hoshi-video-\(UUID().uuidString).m4a")
    }

    func directMediaURL(filename: String, in ankiMediaDirectory: URL) -> URL {
        ankiMediaDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    func replaceMediaItem(at tempURL: URL, destination: URL) throws {
        do {
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
}
#endif
