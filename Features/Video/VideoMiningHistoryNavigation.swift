#if HOSHI_VIDEO
import Foundation

nonisolated enum VideoMiningHistoryMedia: Equatable, Sendable {
    case localFile(URL)
    case remote(RemoteVideoIdentity)
}

struct VideoMiningHistoryDestination: Equatable {
    let media: VideoMiningHistoryMedia
    let subtitleURL: URL?
    let embeddedSubtitleTrackID: Int?
    let seekTime: TimeInterval
}

enum VideoMiningHistoryNavigationResolution: Equatable {
    case ready(VideoMiningHistoryDestination)
    case missingVideo
    case missingSubtitle
    case legacySourceUnavailable
}

enum VideoMiningHistoryNavigationResolver {
    static func resolve(
        item: VideoMiningHistoryItem,
        currentVideoURL: URL?,
        subtitleDelay: TimeInterval,
        fileManager: FileManager = .default
    ) -> VideoMiningHistoryNavigationResolution {
        let media: VideoMiningHistoryMedia
        if let remoteIdentity = item.remoteVideoIdentity {
            media = .remote(remoteIdentity)
        } else if let videoPath = item.videoPath {
            guard fileManager.fileExists(atPath: videoPath) else {
                return .missingVideo
            }
            media = .localFile(URL(fileURLWithPath: videoPath).standardizedFileURL)
        } else {
            guard let currentVideoURL,
                  currentVideoURL.lastPathComponent == item.videoFileName else {
                return .legacySourceUnavailable
            }
            media = .localFile(currentVideoURL.standardizedFileURL)
        }

        let subtitleURL: URL?
        if item.remoteVideoIdentity != nil || item.subtitleFormat == .embedded {
            subtitleURL = nil
        } else if let subtitlePath = item.subtitleSourcePath {
            guard fileManager.fileExists(atPath: subtitlePath) else {
                return .missingSubtitle
            }
            subtitleURL = URL(fileURLWithPath: subtitlePath).standardizedFileURL
        } else if item.subtitleFormat != nil {
            return .missingSubtitle
        } else {
            subtitleURL = nil
        }

        return .ready(
            VideoMiningHistoryDestination(
                media: media,
                subtitleURL: subtitleURL,
                embeddedSubtitleTrackID: item.embeddedSubtitleTrackID,
                seekTime: max(0, item.cueStart + subtitleDelay)
            )
        )
    }
}
#endif
