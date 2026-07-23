import AVFAudio
import AudioToolbox
import Foundation
import SwiftLAME

enum AnkiAudioCompressor {
    static func data(
        from sourceURL: URL,
        format: AnkiAudioCompressionFormat,
        bitrateKbps: Int,
        destinationURL: URL
    ) async throws -> Data {
        try? FileManager.default.removeItem(at: destinationURL)

        let bitrate = min(192, max(32, bitrateKbps))
        switch format {
        case .aac:
            try await Task.detached(priority: .userInitiated) {
                try encodeAAC(
                    from: sourceURL,
                    bitrateKbps: bitrate,
                    destinationURL: destinationURL
                )
            }.value
        case .mp3:
            let encoder = try SwiftLameEncoder(
                sourceUrl: sourceURL,
                configuration: .init(
                    sampleRate: .default,
                    bitrateMode: .constant(Int32(bitrate)),
                    quality: .nearBest
                ),
                destinationUrl: destinationURL
            )
            try await encoder.encode(priority: .userInitiated)
        }
        return try Data(contentsOf: destinationURL)
    }

    nonisolated private static func encodeAAC(
        from sourceURL: URL,
        bitrateKbps: Int,
        destinationURL: URL
    ) throws {
        let source = try AVAudioFile(forReading: sourceURL)
        let sourceFormat = source.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sourceFormat.sampleRate,
            AVNumberOfChannelsKey: sourceFormat.channelCount,
            AVEncoderBitRateKey: bitrateKbps * 1_000
        ]
        let destination = try AVAudioFile(
            forWriting: destinationURL,
            settings: settings,
            commonFormat: sourceFormat.commonFormat,
            interleaved: sourceFormat.isInterleaved
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: 8_192
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        while source.framePosition < source.length {
            try source.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try destination.write(from: buffer)
        }
    }
}
