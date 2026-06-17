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
}
#endif
