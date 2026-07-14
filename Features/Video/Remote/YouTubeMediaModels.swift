#if HOSHI_VIDEO
import Foundation

nonisolated struct YouTubeMediaStreamDescriptor: Equatable, Sendable {
    let url: URL
    let formatID: String
    let height: Int?
    let hasVideo: Bool
    let hasAudio: Bool
    let bitrate: Int
    let fileExtension: String
    let prefersNativeCodec: Bool
}

nonisolated struct YouTubeLoadedMedia: Equatable, Sendable {
    let title: String
    let thumbnailURL: URL?
    let streams: [YouTubeMediaStreamDescriptor]
}

nonisolated enum YouTubeMediaLoaderError: Error, Equatable, Sendable {
    case contentUnavailable
    case signInRequired
    case regionRestricted
    case cancelled
    case timedOut
    case resolutionFailed
}

typealias YouTubeMediaLoading = @Sendable (URL) async throws -> YouTubeLoadedMedia
typealias YouTubePageMetadataLoading = @Sendable (String) async throws -> YouTubeResolvedPageMetadata

nonisolated struct YouTubeResolvedPageMetadata: Equatable, Sendable {
    let duration: TimeInterval?
    let subtitleOptions: [RemoteVideoSubtitleOption]

    static let empty = YouTubeResolvedPageMetadata(
        duration: nil,
        subtitleOptions: []
    )
}

nonisolated struct RemoteVideoStreamSelection: Equatable, Sendable {
    let playback: RemoteVideoStream
    let externalAudio: RemoteVideoStream?
    let muxedFallback: RemoteVideoStream?
    let mining: RemoteVideoStream?
    let qualityOptions: [RemoteVideoQualityOption]
}
#endif
