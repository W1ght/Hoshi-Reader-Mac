#if HOSHI_VIDEO
import Foundation

struct VideoMiningHistoryDestination: Equatable {
    let videoURL: URL
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
        let videoURL: URL
        if let videoPath = item.videoPath {
            guard fileManager.fileExists(atPath: videoPath) else {
                return .missingVideo
            }
            videoURL = URL(fileURLWithPath: videoPath).standardizedFileURL
        } else {
            guard let currentVideoURL,
                  currentVideoURL.lastPathComponent == item.videoFileName else {
                return .legacySourceUnavailable
            }
            videoURL = currentVideoURL.standardizedFileURL
        }

        let subtitleURL: URL?
        if item.subtitleFormat == .embedded {
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
                videoURL: videoURL,
                subtitleURL: subtitleURL,
                embeddedSubtitleTrackID: item.embeddedSubtitleTrackID,
                seekTime: max(0, item.cueStart + subtitleDelay)
            )
        )
    }
}
#endif
