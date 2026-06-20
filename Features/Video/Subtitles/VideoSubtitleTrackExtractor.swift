#if HOSHI_VIDEO
import Foundation

enum VideoSubtitleTrackExtractionError: LocalizedError {
    case unsupportedTrack
    case missingStreamIndex

    var errorDescription: String? {
        switch self {
        case .unsupportedTrack:
            String(localized: "This subtitle track cannot be shown as text.")
        case .missingStreamIndex:
            String(localized: "The selected subtitle track could not be read.")
        }
    }
}

enum VideoSubtitleTrackExtractor {
    nonisolated static func extract(
        videoURL: URL,
        track: VideoTrack
    ) throws -> [VideoEmbeddedSubtitleCue] {
        guard !track.isImage,
              EmbeddedSubtitlePayloadParser.supportsText(codec: track.codec) else {
            throw VideoSubtitleTrackExtractionError.unsupportedTrack
        }
        guard let streamIndex = track.ffIndex else {
            throw VideoSubtitleTrackExtractionError.missingStreamIndex
        }
        let sourceURL = track.externalFilename.map(URL.init(fileURLWithPath:)) ?? videoURL
        let rawCues = try HSSubtitleTrackExtractor.extractTextSubtitle(
            from: sourceURL,
            streamIndex: streamIndex
        )
        return rawCues.enumerated().compactMap { index, cue in
            let text = EmbeddedSubtitlePayloadParser.text(from: cue.text, codec: track.codec)
            guard !text.isEmpty else { return nil }
            return VideoEmbeddedSubtitleCue(
                id: "track-\(track.id)-\(index)-\(cue.startTime)",
                startTime: cue.startTime,
                endTime: max(cue.startTime, cue.endTime),
                text: text
            )
        }
    }
}
#endif
