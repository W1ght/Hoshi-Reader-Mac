import Foundation
@preconcurrency import YouTubeKit

struct YouTubeKitMediaLoader: Sendable {
    func load(url: URL) async throws -> YouTubeLoadedMedia {
        do {
            let youtube = YouTube(url: url, methods: [.local])
            let streams = try await youtube.streams
            let metadata = try await youtube.metadata
            return YouTubeLoadedMedia(
                title: metadata?.title ?? "",
                thumbnailURL: metadata?.thumbnail?.url,
                streams: streams.enumerated().map { index, stream in
                    descriptor(stream, index: index)
                }
            )
        } catch is CancellationError {
            throw YouTubeMediaLoaderError.cancelled
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw YouTubeMediaLoaderError.cancelled
            case .timedOut:
                throw YouTubeMediaLoaderError.timedOut
            default:
                throw YouTubeMediaLoaderError.resolutionFailed
            }
        } catch let error as YouTubeKitError {
            throw map(error)
        } catch {
            throw YouTubeMediaLoaderError.resolutionFailed
        }
    }

    private func descriptor(
        _ stream: YouTubeKit.Stream,
        index: Int
    ) -> YouTubeMediaStreamDescriptor {
        YouTubeMediaStreamDescriptor(
            url: stream.url,
            formatID: formatID(for: stream.url, index: index),
            height: stream.videoResolution,
            hasVideo: stream.includesVideoTrack,
            hasAudio: stream.includesAudioTrack,
            bitrate: stream.averageBitrate ?? stream.bitrate ?? 0,
            fileExtension: stream.fileExtension.rawValue,
            prefersNativeCodec: stream.isNativelyPlayable
        )
    }

    private func formatID(for url: URL, index: Int) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "itag" })?
            .value
            ?? "stream-\(index)"
    }

    private func map(_ error: YouTubeKitError) -> YouTubeMediaLoaderError {
        switch error {
        case .videoUnavailable, .videoPrivate, .recordingUnavailable:
            .contentUnavailable
        case .videoAgeRestricted, .membersOnly:
            .signInRequired
        case .videoRegionBlocked:
            .regionRestricted
        default:
            .resolutionFailed
        }
    }
}
extension YouTubeKitRemoteVideoResolver {
    init() {
        let mediaLoader = YouTubeKitMediaLoader()
        let pageLoader = YouTubePageMetadataLoader()
        self.init(
            mediaLoader: { url in
                try await mediaLoader.load(url: url)
            },
            pageMetadataLoader: { videoID in
                try await pageLoader.load(videoID: videoID)
            }
        )
    }
}
