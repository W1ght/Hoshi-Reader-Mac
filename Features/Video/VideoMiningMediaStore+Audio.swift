import Foundation

extension VideoMiningMediaStore {
    func preparedAudioClip(
        at sourceURL: URL,
        format: AnkiAudioCompressionFormat,
        bitrateKbps: Int
    ) async throws -> URL {
        let destination = sourceURL
            .deletingPathExtension()
            .appendingPathExtension(format.fileExtension)
        _ = try await AnkiAudioCompressor.data(
            from: sourceURL,
            format: format,
            bitrateKbps: bitrateKbps,
            destinationURL: destination
        )
        try FileManager.default.removeItem(at: sourceURL)
        return destination
    }
}
