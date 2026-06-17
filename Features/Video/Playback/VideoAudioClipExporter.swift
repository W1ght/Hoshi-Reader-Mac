#if HOSHI_VIDEO
import AVFoundation
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
        outputURL: URL
    ) async throws {
        guard end > start else {
            throw VideoAudioClipExporterError.failed(
                "Unable to determine the video audio range."
            )
        }
        let asset = AVURLAsset(url: sourceURL)
        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw VideoAudioClipExporterError.failed(
                "This video format cannot export an audio clip."
            )
        }
        try? FileManager.default.removeItem(at: outputURL)
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: max(0, start), preferredTimescale: 600),
            end: CMTime(seconds: max(start, end), preferredTimescale: 600)
        )
        do {
            try await exporter.export(to: outputURL, as: .m4a)
        } catch {
            throw VideoAudioClipExporterError.failed(
                error.localizedDescription
            )
        }
    }
}
#endif
