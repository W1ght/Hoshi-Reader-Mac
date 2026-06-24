#if HOSHI_VIDEO
import Foundation
import Observation

@Observable
@MainActor
final class VideoSubtitleController {
    private(set) var document: SubtitleDocument?
    private(set) var currentCues: [SubtitleCue] = []
    private(set) var transcript = SubtitleTranscript(primary: nil, secondary: nil)
    private(set) var isTranscriptLoading = false
    private(set) var transcriptErrorMessage: String?
    var errorMessage: String?

    private var store: SubtitleCueStore?
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var transcriptGeneration = 0
    @ObservationIgnored private var activeEmbeddedTrackID: Int?

    @discardableResult
    func load(_ url: URL) -> Task<Void, Never> {
        loadGeneration += 1
        let generation = loadGeneration
        let task = Task.detached(priority: .userInitiated) {
            Self.prepareExternalSubtitle(url, generation: generation)
        }
        return Task { @MainActor in
            let result = await task.value
            applyPrimarySubtitleLoad(result, generation: generation)
        }
    }

    nonisolated private static func prepareExternalSubtitle(
        _ url: URL,
        generation: Int
    ) -> Result<PreparedSubtitleLoad, Error> {
        parseExternalSubtitle(url).map { document in
            PreparedSubtitleLoad(
                document: document,
                store: SubtitleCueStore(document: document),
                transcript: SubtitleTranscript(
                    primary: document,
                    secondary: nil,
                    generation: generation
                )
            )
        }
    }

    nonisolated private static func parseExternalSubtitle(
        _ url: URL
    ) -> Result<SubtitleDocument, Error> {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let document = try SubtitleParser.parse(data: Data(contentsOf: url), sourceURL: url)
            return .success(document)
        } catch {
            return .failure(error)
        }
    }

    private func applyPrimarySubtitleLoad(
        _ result: Result<PreparedSubtitleLoad, Error>,
        generation: Int
    ) {
        guard generation == loadGeneration else { return }
        switch result {
        case .success(let load):
            activeEmbeddedTrackID = nil
            self.document = load.document
            store = load.store
            currentCues = []
            transcriptGeneration = generation
            transcript = load.transcript
            isTranscriptLoading = false
            transcriptErrorMessage = nil
            errorMessage = nil
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func loadEmbedded(
        _ cues: [VideoEmbeddedSubtitleCue],
        sourceURL: URL
    ) {
        if let format = document?.format, format != .embedded {
            return
        }
        guard !cues.isEmpty else {
            currentCues = []
            return
        }
        let existingCues = document?.format == .embedded ? document?.cues ?? [] : []
        let incomingCues = cues.map(Self.makeSubtitleCue)
        let document = SubtitleDocument(
            sourceURL: sourceURL,
            format: .embedded,
            cues: Self.deduplicatedSortedCues(existingCues + incomingCues),
            warnings: []
        )
        self.document = document
        store = SubtitleCueStore(document: document)
        currentCues = []
        rebuildTranscript()
        errorMessage = nil
    }

    func beginEmbeddedTrack(trackID: Int, sourceURL: URL) {
        loadGeneration += 1
        activeEmbeddedTrackID = trackID
        let document = SubtitleDocument(
            sourceURL: sourceURL,
            format: .embedded,
            cues: [],
            warnings: []
        )
        self.document = document
        store = SubtitleCueStore(document: document)
        currentCues = []
        rebuildTranscript()
        isTranscriptLoading = true
        transcriptErrorMessage = nil
        errorMessage = nil
    }

    func failEmbeddedTranscript(
        _ message: String,
        trackID: Int
    ) {
        guard activeEmbeddedTrackID == trackID else { return }
        isTranscriptLoading = false
        transcriptErrorMessage = message
    }

    func replaceEmbeddedTranscript(
        _ cues: [VideoEmbeddedSubtitleCue],
        sourceURL: URL,
        trackID: Int
    ) {
        guard activeEmbeddedTrackID == trackID else { return }
        let document = SubtitleDocument(
            sourceURL: sourceURL,
            format: .embedded,
            cues: Self.deduplicatedSortedCues(cues.map(Self.makeSubtitleCue)),
            warnings: []
        )
        self.document = document
        store = SubtitleCueStore(document: document)
        currentCues = []
        rebuildTranscript()
        isTranscriptLoading = false
        transcriptErrorMessage = nil
        errorMessage = nil
    }

    func update(time: TimeInterval, subtitleDelay: TimeInterval = 0) {
        let nextCurrentCues = store?.cues(
            atPlaybackTime: time,
            subtitleDelay: subtitleDelay
        ) ?? []
        if nextCurrentCues != currentCues {
            currentCues = nextCurrentCues
        }
    }

    func clear() {
        clearPrimary()
        errorMessage = nil
    }

    func clearPrimary() {
        loadGeneration += 1
        activeEmbeddedTrackID = nil
        document = nil
        store = nil
        currentCues = []
        rebuildTranscript()
        isTranscriptLoading = false
        transcriptErrorMessage = nil
        errorMessage = nil
    }

    private func rebuildTranscript() {
        transcriptGeneration += 1
        transcript = SubtitleTranscript(
            primary: document,
            secondary: nil,
            generation: transcriptGeneration
        )
    }

    private static func makeSubtitleCue(
        _ cue: VideoEmbeddedSubtitleCue
    ) -> SubtitleCue {
        SubtitleCue(
            id: cue.id,
            startTime: cue.startTime,
            endTime: cue.endTime,
            text: cue.text
        )
    }

    private static func deduplicatedSortedCues(
        _ cues: [SubtitleCue]
    ) -> [SubtitleCue] {
        var seenIDs = Set<String>()
        var seenContent = Set<String>()
        var uniqueCues: [SubtitleCue] = []

        for cue in cues.sorted(by: compareCueOrder) {
            let id = cue.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let contentKey = semanticDeduplicationKey(for: cue)
            if (!id.isEmpty && seenIDs.contains(id))
                || seenContent.contains(contentKey) {
                continue
            }
            if uniqueCues.contains(where: { isMergedSubtitleDuplicate($0, cue) }) {
                continue
            }
            if !id.isEmpty {
                seenIDs.insert(id)
            }
            seenContent.insert(contentKey)
            uniqueCues.append(cue)
        }
        return uniqueCues
    }

    private static func compareCueOrder(
        _ left: SubtitleCue,
        _ right: SubtitleCue
    ) -> Bool {
        if left.startTime != right.startTime {
            return left.startTime < right.startTime
        }
        if left.endTime != right.endTime {
            return left.endTime < right.endTime
        }
        let leftText = normalizedText(left.text)
        let rightText = normalizedText(right.text)
        if leftText.count != rightText.count {
            return leftText.count < rightText.count
        }
        return left.text < right.text
    }

    private static func isMergedSubtitleDuplicate(
        _ existing: SubtitleCue,
        _ incoming: SubtitleCue
    ) -> Bool {
        guard sameTiming(existing, incoming) else { return false }
        let existingText = normalizedText(existing.text)
        let incomingText = normalizedText(incoming.text)
        guard !existingText.isEmpty,
              !incomingText.isEmpty,
              existingText != incomingText else {
            return false
        }
        return normalizedLines(incoming.text).contains(existingText)
    }

    private static func sameTiming(
        _ left: SubtitleCue,
        _ right: SubtitleCue
    ) -> Bool {
        Int((left.startTime * 1000).rounded())
            == Int((right.startTime * 1000).rounded())
            && Int((left.endTime * 1000).rounded())
                == Int((right.endTime * 1000).rounded())
    }

    private static func semanticDeduplicationKey(for cue: SubtitleCue) -> String {
        let start = Int((cue.startTime * 1000).rounded())
        let end = Int((cue.endTime * 1000).rounded())
        let text = normalizedText(cue.text)
        return "\(start)|\(end)|\(text)"
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func normalizedLines(_ text: String) -> Set<String> {
        Set(
            text
                .split(whereSeparator: \.isNewline)
                .map { normalizedText(String($0)) }
                .filter { !$0.isEmpty }
        )
    }

    private struct PreparedSubtitleLoad: Sendable {
        let document: SubtitleDocument
        let store: SubtitleCueStore
        let transcript: SubtitleTranscript
    }
}
#endif
