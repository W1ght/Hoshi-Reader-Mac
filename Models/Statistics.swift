//
//  Statistics.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  Copyright © 2026 ッツ Reader Authors.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum StatisticsAutostartMode: String, CaseIterable, Codable {
    case off = "Off"
    case pageturn = "Page Turn"
    case on = "On"
}

enum StatisticsSyncMode: String, CaseIterable, Codable {
    case merge = "Merge"
    case replace = "Replace"
}

nonisolated enum StatisticsResetTimePreference {
    static let resetTimeKey = "statisticsResetTime"
    static let minutesMigrationKey = "statisticsResetTimeMigratedToMinutes"

    static func load(from defaults: UserDefaults) -> Int {
        guard let storedValue = defaults.object(forKey: resetTimeKey) as? Int else {
            return 0
        }

        if defaults.bool(forKey: minutesMigrationKey) {
            let normalized = StatisticsDayBoundary.normalizedResetMinutes(storedValue)
            if normalized != storedValue {
                defaults.set(normalized, forKey: resetTimeKey)
            }
            return normalized
        }

        let legacyHours = min(max(storedValue, 0), 23)
        let migratedMinutes = legacyHours * 60
        defaults.set(migratedMinutes, forKey: resetTimeKey)
        defaults.set(true, forKey: minutesMigrationKey)
        return migratedMinutes
    }

    static func save(_ resetMinutes: Int, to defaults: UserDefaults) {
        defaults.set(
            StatisticsDayBoundary.normalizedResetMinutes(resetMinutes),
            forKey: resetTimeKey
        )
        defaults.set(true, forKey: minutesMigrationKey)
    }
}

nonisolated enum StatisticsDayBoundary {
    static let minutesPerDay = 24 * 60

    static func normalizedResetMinutes(_ resetMinutes: Int) -> Int {
        min(max(resetMinutes, 0), minutesPerDay - 1)
    }

    static func reportingDay(
        containing date: Date,
        resetMinutes: Int,
        calendar: Calendar = .current
    ) -> Date {
        let resetMinutes = normalizedResetMinutes(resetMinutes)
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let reportingDate: Date
        if minuteOfDay < resetMinutes {
            reportingDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        } else {
            reportingDate = date
        }
        return calendar.startOfDay(for: reportingDate)
    }

    static func dateKey(
        for date: Date,
        resetMinutes: Int,
        calendar: Calendar = .current
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withFullDate]
        return formatter.string(
            from: reportingDay(
                containing: date,
                resetMinutes: resetMinutes,
                calendar: calendar
            )
        )
    }
}

// https://github.com/ttu-ttu/ebook-reader/blob/2703b50ec52b2e4f70afcab725c0f47dd8a66bf4/apps/web/src/lib/data/database/books-db/versions/v6/books-db-v6.ts#L68
struct Statistics: Codable {
    let title: String
    let dateKey: String
    var charactersRead: Int
    var readingTime: Double
    var minReadingSpeed: Int
    var altMinReadingSpeed: Int
    var lastReadingSpeed: Int
    var maxReadingSpeed: Int
    var lastStatisticModified: Int
}

nonisolated enum StatisticsEditor {
    static func visibleStatistics(_ statistics: [Statistics]) -> [Statistics] {
        deduplicated(statistics)
            .filter { $0.charactersRead > 0 || $0.readingTime > 0 }
            .sorted { $0.dateKey < $1.dateKey }
    }

    static func updating(
        dateKey: String,
        title: String,
        charactersRead: Int,
        readingTime: Double,
        modifiedAt: Int,
        in statistics: [Statistics]
    ) -> [Statistics] {
        var records = deduplicated(statistics)
        let charactersRead = max(charactersRead, 0)
        let readingTime = max(readingTime, 0)
        let speed = readingTime > 0
            ? Int((Double(charactersRead) / readingTime) * 3600)
            : 0
        let existingTitle = records.first(where: { $0.dateKey == dateKey })?.title ?? title
        let record = Statistics(
            title: existingTitle,
            dateKey: dateKey,
            charactersRead: charactersRead,
            readingTime: readingTime,
            minReadingSpeed: speed,
            altMinReadingSpeed: speed,
            lastReadingSpeed: speed,
            maxReadingSpeed: speed,
            lastStatisticModified: modifiedAt
        )

        if let index = records.firstIndex(where: { $0.dateKey == dateKey }) {
            records[index] = record
        } else {
            records.append(record)
        }
        return records.sorted { $0.dateKey < $1.dateKey }
    }

    static func deleting(
        dateKey: String,
        title: String,
        modifiedAt: Int,
        from statistics: [Statistics]
    ) -> [Statistics] {
        updating(
            dateKey: dateKey,
            title: title,
            charactersRead: 0,
            readingTime: 0,
            modifiedAt: modifiedAt,
            in: statistics
        )
    }

    static func deletingAll(
        title: String,
        modifiedAt: Int,
        from statistics: [Statistics]
    ) -> [Statistics] {
        deduplicated(statistics)
            .map {
                Statistics(
                    title: $0.title.isEmpty ? title : $0.title,
                    dateKey: $0.dateKey,
                    charactersRead: 0,
                    readingTime: 0,
                    minReadingSpeed: 0,
                    altMinReadingSpeed: 0,
                    lastReadingSpeed: 0,
                    maxReadingSpeed: 0,
                    lastStatisticModified: modifiedAt
                )
            }
            .sorted { $0.dateKey < $1.dateKey }
    }

    static func deduplicated(_ statistics: [Statistics]) -> [Statistics] {
        var grouped: [String: Statistics] = [:]
        for statistic in statistics {
            if let existing = grouped[statistic.dateKey] {
                if statistic.lastStatisticModified > existing.lastStatisticModified {
                    grouped[statistic.dateKey] = statistic
                }
            } else {
                grouped[statistic.dateKey] = statistic
            }
        }
        return Array(grouped.values)
    }
}
