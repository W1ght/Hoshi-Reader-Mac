#if HOSHI_VIDEO
import Foundation

struct YouTubeKitRemoteVideoResolver: RemoteVideoResolving {
    let provider: RemoteVideoProvider = .youtube

    private let mediaLoader: YouTubeMediaLoading
    private let pageMetadataLoader: YouTubePageMetadataLoading
    private let now: @Sendable () -> Date

    init(
        mediaLoader: @escaping YouTubeMediaLoading,
        pageMetadataLoader: @escaping YouTubePageMetadataLoading,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.mediaLoader = mediaLoader
        self.pageMetadataLoader = pageMetadataLoader
        self.now = now
    }

    func canResolve(url: URL) -> Bool {
        YouTubeURLParser.isYouTubeURL(url)
    }

    func resolve(
        url: URL,
        preferredSubtitleLanguages: [String]
    ) async throws -> ResolvedRemoteVideoSource {
        guard let videoID = YouTubeURLParser.videoID(from: url) else {
            throw RemoteVideoResolverError.unsupportedURL
        }

        async let pageResult: YouTubeResolvedPageMetadata? = try? pageMetadataLoader(videoID)
        let media: YouTubeLoadedMedia
        do {
            media = try await mediaLoader(url)
        } catch {
            throw mapMediaError(error)
        }
        let loadedPageMetadata = await pageResult
        let pageMetadata = loadedPageMetadata ?? .empty
        let hasDegradedPageMetadata = loadedPageMetadata == nil
            || (pageMetadata.duration == nil && pageMetadata.subtitleOptions.isEmpty)
        let streams = try YouTubeStreamSelector.select(from: media.streams)
        let resolvedAt = now()
        let identity = RemoteVideoIdentity(
            provider: provider,
            remoteID: videoID,
            originalURL: url,
            canonicalURL: YouTubeURLParser.canonicalURL(for: videoID),
            title: media.title.isEmpty
                ? String(localized: "YouTube Video")
                : media.title,
            thumbnailURL: media.thumbnailURL,
            duration: pageMetadata.duration
        )

        let source = ResolvedRemoteVideoSource(
            identity: identity,
            playbackStream: streams.playback,
            audioStream: streams.externalAudio,
            muxedFallbackStream: streams.muxedFallback,
            miningStream: streams.mining,
            subtitleOptions: pageMetadata.subtitleOptions,
            selectedSubtitleLanguage: nil,
            resolvedAt: resolvedAt,
            expiresAt: resolvedAt.addingTimeInterval(
                hasDegradedPageMetadata ? 60 : 5 * 60 * 60
            ),
            qualityOptions: streams.qualityOptions
        )
        let selectedSubtitle = source.preferredSubtitle(
            preferredLanguages: preferredSubtitleLanguages
        )
        return ResolvedRemoteVideoSource(
            identity: source.identity,
            playbackStream: source.playbackStream,
            audioStream: source.audioStream,
            muxedFallbackStream: source.muxedFallbackStream,
            miningStream: source.miningStream,
            subtitleOptions: source.subtitleOptions,
            selectedSubtitleLanguage: selectedSubtitle?.language,
            resolvedAt: source.resolvedAt,
            expiresAt: source.expiresAt,
            qualityOptions: source.qualityOptions
        )
    }

    private func mapMediaError(_ error: any Error) -> RemoteVideoResolverError {
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return .cancelled
            case .timedOut:
                return .timedOut
            default:
                return .resolutionFailed
            }
        }
        guard let error = error as? YouTubeMediaLoaderError else {
            return .resolutionFailed
        }
        switch error {
        case .contentUnavailable:
            return .contentUnavailable
        case .signInRequired:
            return .signInRequired
        case .regionRestricted:
            return .regionRestricted
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timedOut
        case .resolutionFailed:
            return .resolutionFailed
        }
    }
}
#endif
