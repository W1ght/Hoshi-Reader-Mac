#if HOSHI_VIDEO
import Foundation

nonisolated enum YouTubeStreamSelector {
    private static let maximumVideoHeight = 1080

    static func select(
        from descriptors: [YouTubeMediaStreamDescriptor]
    ) throws -> RemoteVideoStreamSelection {
        let audio = descriptors
            .filter { !$0.hasVideo && $0.hasAudio }
            .sorted(by: preferAudio)
            .first
            .map(remoteStream)

        let progressive = descriptors
            .filter {
                $0.hasVideo
                    && $0.hasAudio
                    && ($0.height.map { $0 <= maximumVideoHeight } ?? true)
            }
            .sorted(by: preferVideo)
            .first
            .map(remoteStream)

        var qualityOptions: [RemoteVideoQualityOption] = []
        if let audio {
            let videoOnly = descriptors.filter {
                $0.hasVideo
                    && !$0.hasAudio
                    && ($0.height.map { (1...maximumVideoHeight).contains($0) } ?? false)
            }
            for (height, candidates) in Dictionary(grouping: videoOnly, by: { $0.height! }) {
                guard let best = candidates.sorted(by: preferVideo).first else { continue }
                qualityOptions.append(
                    RemoteVideoQualityOption(
                        id: best.formatID,
                        height: height,
                        playbackStream: remoteStream(best),
                        audioStream: audio
                    )
                )
            }
        }

        let coveredHeights = Set(qualityOptions.map(\.height))
        let progressiveByHeight = Dictionary(
            grouping: descriptors.filter {
                $0.hasVideo
                    && $0.hasAudio
                    && ($0.height.map {
                        (1...maximumVideoHeight).contains($0)
                            && !coveredHeights.contains($0)
                    } ?? false)
            },
            by: { $0.height! }
        )
        for (height, candidates) in progressiveByHeight {
            guard let best = candidates.sorted(by: preferVideo).first else { continue }
            qualityOptions.append(
                RemoteVideoQualityOption(
                    id: best.formatID,
                    height: height,
                    playbackStream: remoteStream(best),
                    audioStream: nil
                )
            )
        }
        qualityOptions.sort { lhs, rhs in
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            return lhs.id < rhs.id
        }

        if let selected = qualityOptions.first {
            return RemoteVideoStreamSelection(
                playback: selected.playbackStream,
                externalAudio: selected.audioStream,
                muxedFallback: selected.audioStream == nil ? nil : progressive,
                mining: progressive ?? selected.playbackStream,
                qualityOptions: qualityOptions
            )
        }

        if let progressive {
            return RemoteVideoStreamSelection(
                playback: progressive,
                externalAudio: nil,
                muxedFallback: nil,
                mining: progressive,
                qualityOptions: []
            )
        }

        throw RemoteVideoResolverError.noPlayableStream
    }

    private static func preferAudio(
        _ lhs: YouTubeMediaStreamDescriptor,
        _ rhs: YouTubeMediaStreamDescriptor
    ) -> Bool {
        let lhsM4A = lhs.fileExtension.lowercased() == "m4a"
        let rhsM4A = rhs.fileExtension.lowercased() == "m4a"
        if lhsM4A != rhsM4A { return lhsM4A }
        if lhs.prefersNativeCodec != rhs.prefersNativeCodec {
            return lhs.prefersNativeCodec
        }
        return lhs.bitrate > rhs.bitrate
    }

    private static func preferVideo(
        _ lhs: YouTubeMediaStreamDescriptor,
        _ rhs: YouTubeMediaStreamDescriptor
    ) -> Bool {
        let lhsHeight = lhs.height ?? 0
        let rhsHeight = rhs.height ?? 0
        if lhsHeight != rhsHeight { return lhsHeight > rhsHeight }
        if lhs.prefersNativeCodec != rhs.prefersNativeCodec {
            return lhs.prefersNativeCodec
        }
        return lhs.bitrate > rhs.bitrate
    }

    private static func remoteStream(
        _ descriptor: YouTubeMediaStreamDescriptor
    ) -> RemoteVideoStream {
        RemoteVideoStream(
            url: descriptor.url,
            formatID: descriptor.formatID,
            height: descriptor.height,
            hasVideo: descriptor.hasVideo,
            hasAudio: descriptor.hasAudio
        )
    }
}
#endif
