#if HOSHI_VIDEO
import Foundation
import Observation

enum VideoMiningHistoryStatus: String, Codable, CaseIterable {
    case pending
    case added
    case duplicate
    case failed
}

struct VideoMiningHistoryItem: Codable, Equatable, Identifiable {
    let id: String
    let createdAt: Date
    var updatedAt: Date?
    var status: VideoMiningHistoryStatus
    var message: String?

    let expression: String
    let reading: String?
    let matched: String?
    let selectionText: String?
    let glossaryText: String?

    let subtitleText: String
    let previousSubtitleText: String?
    let nextSubtitleText: String?
    let videoFileName: String
    let cueStart: TimeInterval
    let cueEnd: TimeInterval
    let screenshotPath: String?
    let audioClipPath: String?
}

@Observable
@MainActor
final class VideoMiningHistoryStore {
    private(set) var items: [VideoMiningHistoryItem]

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let limit: Int
    @ObservationIgnored private let fileManager: FileManager

    init(
        fileURL: URL? = nil,
        limit: Int = 200,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.limit = max(0, limit)
        items = Self.loadItems(from: self.fileURL)
        pruneAndSave()
    }

    @discardableResult
    func recordPending(
        id: String = UUID().uuidString,
        content: [String: String],
        context: MiningContext,
        date: Date = Date()
    ) -> String? {
        guard let video = context.video else { return nil }

        let item = VideoMiningHistoryItem(
            id: id,
            createdAt: date,
            updatedAt: nil,
            status: .pending,
            message: nil,
            expression: content["expression"] ?? content["matched"] ?? content["popupSelectionText"] ?? "",
            reading: content["reading"].nilIfEmpty,
            matched: content["matched"].nilIfEmpty,
            selectionText: content["popupSelectionText"].nilIfEmpty,
            glossaryText: (content["glossaryFirst"] ?? content["glossary"]).nilIfEmpty,
            subtitleText: video.cueText,
            previousSubtitleText: video.previousCueText,
            nextSubtitleText: video.nextCueText,
            videoFileName: video.fileName,
            cueStart: video.cueStart,
            cueEnd: video.cueEnd,
            screenshotPath: video.screenshotURL?.path,
            audioClipPath: video.audioClipURL?.path
        )
        replaceOrAppend(item)
        return id
    }

    func update(
        id: String,
        status: VideoMiningHistoryStatus,
        message: String?,
        date: Date = Date()
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
        items[index].message = message
        items[index].updatedAt = date
        save()
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func replaceOrAppend(_ item: VideoMiningHistoryItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        pruneAndSave()
    }

    private func pruneAndSave() {
        items.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
        if limit == 0 {
            items.removeAll()
        } else if items.count > limit {
            items.removeFirst(items.count - limit)
        }
        save()
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // History is helpful context, not a source of truth for card creation.
        }
    }

    private static func loadItems(from fileURL: URL) -> [VideoMiningHistoryItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([VideoMiningHistoryItem].self, from: data) else {
            return []
        }
        return items
    }

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent("video_mining_history.json")
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        switch self?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case let value? where !value.isEmpty:
            value
        default:
            nil
        }
    }
}
#endif
