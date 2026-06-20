#if HOSHI_VIDEO
import Foundation

enum VideoAudioClipExporterError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
        }
    }
}

enum VideoAudioClipExporter {
    static func export(
        sourceURL: URL,
        from start: TimeInterval,
        to end: TimeInterval,
        audioTrackID: Int?,
        outputURL: URL
    ) async throws {
        guard end > start else {
            throw VideoAudioClipExporterError.failed(
                "Unable to determine the video audio range."
            )
        }
        let result: (Bool, String?) = await Task.detached(priority: .userInitiated) {
            var errorMessage: NSString?
            let succeeded = HSMpvAudioClipExporter.exportAudio(
                from: sourceURL,
                to: outputURL,
                startTime: start,
                endTime: end,
                audioTrackID: audioTrackID.map(NSNumber.init(value:)),
                errorMessage: &errorMessage
            )
            return (succeeded, errorMessage as String?)
        }.value
        guard result.0 else {
            throw VideoAudioClipExporterError.failed(
                result.1 ?? "The bundled audio encoder could not export this subtitle range."
            )
        }
    }
}
#endif
