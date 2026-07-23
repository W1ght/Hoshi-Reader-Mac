import Foundation
import Observation

struct VideoMiningHistoryItem: Codable, Equatable, Identifiable {
    let id: String
    let createdAt: Date
    let subtitleText: String
    let videoFileName: String
    let videoTitle: String
    let videoPath: String?
    let remoteVideoIdentity: RemoteVideoIdentity?
    let subtitleSourceName: String
    let subtitleSourcePath: String?
    let subtitleFormat: SubtitleFormat?
    let embeddedSubtitleTrackID: Int?
    let cueStart: TimeInterval
    let cueEnd: TimeInterval

    init(
        id: String,
        createdAt: Date,
        subtitleText: String,
        videoFileName: String,
        videoTitle: String? = nil,
        videoPath: String?,
        remoteVideoIdentity: RemoteVideoIdentity? = nil,
        subtitleSourceName: String,
        subtitleSourcePath: String?,
        subtitleFormat: SubtitleFormat?,
        embeddedSubtitleTrackID: Int?,
        cueStart: TimeInterval,
        cueEnd: TimeInterval
    ) {
        self.id = id
        self.createdAt = createdAt
        self.subtitleText = subtitleText
        self.videoFileName = videoFileName
        self.videoTitle = videoTitle ?? videoFileName
        self.videoPath = videoPath
        self.remoteVideoIdentity = remoteVideoIdentity
        self.subtitleSourceName = subtitleSourceName
        self.subtitleSourcePath = subtitleSourcePath
        self.subtitleFormat = subtitleFormat
        self.embeddedSubtitleTrackID = embeddedSubtitleTrackID
        self.cueStart = cueStart
        self.cueEnd = cueEnd
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case subtitleText
        case videoFileName
        case videoTitle
        case videoPath
        case remoteVideoIdentity
        case subtitleSourceName
        case subtitleSourcePath
        case subtitleFormat
        case embeddedSubtitleTrackID
        case cueStart
        case cueEnd
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        subtitleText = try container.decode(String.self, forKey: .subtitleText)
        videoFileName = try container.decode(String.self, forKey: .videoFileName)
        videoTitle = try container.decodeIfPresent(String.self, forKey: .videoTitle)
            ?? videoFileName
        videoPath = try container.decodeIfPresent(String.self, forKey: .videoPath)
        remoteVideoIdentity = try container.decodeIfPresent(
            RemoteVideoIdentity.self,
            forKey: .remoteVideoIdentity
        )
        subtitleSourceName = try container.decodeIfPresent(
            String.self,
            forKey: .subtitleSourceName
        ) ?? videoFileName
        subtitleSourcePath = try container.decodeIfPresent(
            String.self,
            forKey: .subtitleSourcePath
        )
        subtitleFormat = try container.decodeIfPresent(
            SubtitleFormat.self,
            forKey: .subtitleFormat
        )
        embeddedSubtitleTrackID = try container.decodeIfPresent(
            Int.self,
            forKey: .embeddedSubtitleTrackID
        )
        cueStart = try container.decode(TimeInterval.self, forKey: .cueStart)
        cueEnd = try container.decode(TimeInterval.self, forKey: .cueEnd)
    }
}

@Observable
@MainActor
final class VideoMiningHistoryStore {
    private(set) var items: [VideoMiningHistoryItem]

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var limit: Int
    @ObservationIgnored private let fileManager: FileManager

    init(
        fileURL: URL? = nil,
        limit: Int = 25,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.limit = max(0, limit)
        items = Self.loadItems(from: self.fileURL)
        pruneAndSave()
    }

    @discardableResult
    func record(
        id: String = UUID().uuidString,
        cues: [SubtitleCue],
        document: SubtitleDocument,
        videoURL: URL,
        videoTitle: String? = nil,
        mediaIdentity: VideoMediaIdentity? = nil,
        remoteVideoIdentity: RemoteVideoIdentity? = nil,
        embeddedSubtitleTrackID: Int?,
        date: Date = Date()
    ) -> String? {
        guard limit > 0, !cues.isEmpty else { return nil }

        let sortedCues = cues.sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            if lhs.endTime != rhs.endTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.text < rhs.text
        }
        let subtitleText = sortedCues
            .map(\.text)
            .joined(separator: "\n")
        let isRemote = remoteVideoIdentity != nil || {
            guard let mediaIdentity else { return false }
            if case .remote = mediaIdentity { return true }
            return false
        }()
        let subtitleSourcePath = document.format == .embedded || isRemote
            ? nil
            : document.sourceURL.standardizedFileURL.path
        let localVideoURL = mediaIdentity?.localURL
            ?? (videoURL.isFileURL ? videoURL.standardizedFileURL : nil)
        let resolvedTitle = videoTitle ?? videoURL.lastPathComponent
        let item = VideoMiningHistoryItem(
            id: id,
            createdAt: date,
            subtitleText: subtitleText,
            videoFileName: resolvedTitle,
            videoTitle: resolvedTitle,
            videoPath: localVideoURL?.path,
            remoteVideoIdentity: remoteVideoIdentity,
            subtitleSourceName: document.sourceURL.lastPathComponent,
            subtitleSourcePath: subtitleSourcePath,
            subtitleFormat: document.format,
            embeddedSubtitleTrackID: document.format == .embedded
                ? embeddedSubtitleTrackID
                : nil,
            cueStart: sortedCues.map(\.startTime).min() ?? 0,
            cueEnd: sortedCues.map(\.endTime).max() ?? 0
        )
        items.append(item)
        pruneAndSave()
        return id
    }

    func updateLimit(_ limit: Int) {
        self.limit = max(0, limit)
        pruneAndSave()
    }

    func delete(id: String) {
        items.removeAll { $0.id == id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
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
            // History is optional context and must never block playback or mining.
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
