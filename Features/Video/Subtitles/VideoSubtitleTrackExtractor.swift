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

nonisolated struct ExtractedSubtitleTrack: Hashable, Sendable {
    let sourceURL: URL
    let codec: String?
    let codecPrivate: Data?
    let packets: [EmbeddedSubtitlePacketRecord]
    let cues: [VideoEmbeddedSubtitleCue]

    var reconstructedASSData: Data? {
        EmbeddedSubtitlePayloadParser.reconstructedASSData(
            codecPrivate: codecPrivate,
            packets: packets,
            codec: codec
        )
    }

    nonisolated func reconstructedASSData(
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> Data? {
        try EmbeddedSubtitlePayloadParser.reconstructedASSData(
            codecPrivate: codecPrivate,
            packets: packets,
            codec: codec,
            isCancelled: isCancelled
        )
    }
}

enum VideoSubtitleTrackExtractor {
    nonisolated static func extract(
        videoURL: URL,
        track: VideoTrack,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws -> ExtractedSubtitleTrack {
        if isCancelled() {
            throw CancellationError()
        }
        guard !track.isImage,
              EmbeddedSubtitlePayloadParser.supportsText(codec: track.codec) else {
            throw VideoSubtitleTrackExtractionError.unsupportedTrack
        }
        guard let streamIndex = track.ffIndex else {
            throw VideoSubtitleTrackExtractionError.missingStreamIndex
        }
        let sourceURL = track.externalFilename.map(URL.init(fileURLWithPath:)) ?? videoURL
        let rawTrack: HSExtractedSubtitleTrack
        do {
            rawTrack = try HSSubtitleTrackExtractor.extractTextSubtitle(
                from: sourceURL,
                streamIndex: streamIndex,
                isCancelled: isCancelled
            )
        } catch {
            if isCancelled() {
                throw CancellationError()
            }
            throw error
        }

        let rawCues = rawTrack.packets
        var packets: [EmbeddedSubtitlePacketRecord] = []
        packets.reserveCapacity(rawCues.count)
        for cue in rawCues {
            if isCancelled() {
                throw CancellationError()
            }
            packets.append(EmbeddedSubtitlePacketRecord(
                rawPayload: cue.rawPayload as Data,
                presentationTimestamp: cue.presentationTimestamp,
                decodingTimestamp: cue.decodingTimestamp,
                packetDuration: cue.packetDuration,
                timeBaseNumerator: cue.timeBaseNumerator,
                timeBaseDenominator: cue.timeBaseDenominator,
                packetFlags: cue.packetFlags,
                filePosition: cue.filePosition,
                startTime: cue.startTime,
                endTime: max(cue.startTime, cue.endTime)
            ))
        }
        var result: [VideoEmbeddedSubtitleCue] = []
        result.reserveCapacity(rawCues.count)
        for (index, cue) in rawCues.enumerated() {
            if isCancelled() {
                throw CancellationError()
            }
            let text = EmbeddedSubtitlePayloadParser.text(from: cue.text, codec: track.codec)
            guard !text.isEmpty else { continue }
            result.append(VideoEmbeddedSubtitleCue(
                id: "track-\(track.id)-\(index)-\(cue.startTime)",
                startTime: cue.startTime,
                endTime: max(cue.startTime, cue.endTime),
                text: text
            ))
        }
        return ExtractedSubtitleTrack(
            sourceURL: sourceURL,
            codec: track.codec,
            codecPrivate: rawTrack.codecPrivateData.map { $0 as Data },
            packets: packets,
            cues: result
        )
    }
}
#endif
