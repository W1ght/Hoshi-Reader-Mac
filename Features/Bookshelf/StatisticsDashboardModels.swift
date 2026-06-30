//
//  StatisticsDashboardModels.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum StatisticsRangeMode: String, CaseIterable, Identifiable {
    case year
    case month
    case week
    case day

    var id: String { rawValue }
}

enum DailyTargetType: String, CaseIterable, Codable, Identifiable {
    case characters
    case duration

    var id: String { rawValue }
}

struct StatisticsTargetSettings: Equatable {
    var dailyTargetType: DailyTargetType = .characters
    var dailyCharacterTarget: Int = 5_000
    var dailyDurationTargetMinutes: Int = 30
    var weeklyTargetDays: Int = 4

    static let characterTargetRange = 500...20_000
    static let characterTargetStep = 500
    static let durationTargetMinutesRange = 5...240
    static let durationTargetMinutesStep = 5
    static let weeklyTargetDaysRange = 1...7

    func clamped() -> StatisticsTargetSettings {
        StatisticsTargetSettings(
            dailyTargetType: dailyTargetType,
            dailyCharacterTarget: Self.snapCharacterTarget(dailyCharacterTarget),
            dailyDurationTargetMinutes: Self.snapDurationTarget(dailyDurationTargetMinutes),
            weeklyTargetDays: min(max(weeklyTargetDays, Self.weeklyTargetDaysRange.lowerBound), Self.weeklyTargetDaysRange.upperBound)
        )
    }

    static func snapCharacterTarget(_ value: Int) -> Int {
        snap(value, range: characterTargetRange, step: characterTargetStep)
    }

    static func snapDurationTarget(_ value: Int) -> Int {
        snap(value, range: durationTargetMinutesRange, step: durationTargetMinutesStep)
    }

    private static func snap(_ value: Int, range: ClosedRange<Int>, step: Int) -> Int {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let offset = clamped - range.lowerBound
        let snapped = range.lowerBound + ((offset + step / 2) / step) * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}

struct StatisticsDateRange: Equatable {
    let start: Date
    let end: Date

    init(start: Date, end: Date) {
        precondition(end >= start, "Statistics range end must be on or after start.")
        self.start = start
        self.end = end
    }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= start && day <= end
    }

    func coerce(_ date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        if day < start { return start }
        if day > end { return end }
        return day
    }

    func dayCount(calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day.map { $0 + 1 } ?? 1
    }

    static func recentYear(endingAt today: Date, calendar: Calendar) -> StatisticsDateRange {
        let end = calendar.startOfDay(for: today)
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: end) ?? end
        let start = calendar.date(byAdding: .day, value: 1, to: oneYearAgo) ?? oneYearAgo
        return StatisticsDateRange(start: start, end: end)
    }

    static func fixedYear(_ year: Int, today: Date, calendar: Calendar) -> StatisticsDateRange {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? calendar.startOfDay(for: today)
        let end: Date
        if calendar.component(.year, from: today) == year {
            end = calendar.startOfDay(for: today)
        } else {
            end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? start
        }
        return StatisticsDateRange(start: start, end: end)
    }

    static func mondayStartOfWeek(for date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    static func selectedRange(
        mode: StatisticsRangeMode,
        anchor: Date,
        window: StatisticsDateRange,
        calendar: Calendar
    ) -> StatisticsDateRange {
        let anchor = window.coerce(anchor, calendar: calendar)
        let unclipped: StatisticsDateRange
        switch mode {
        case .year:
            unclipped = window
        case .month:
            let components = calendar.dateComponents([.year, .month], from: anchor)
            let start = calendar.date(from: components) ?? anchor
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? start
            unclipped = StatisticsDateRange(start: start, end: end)
        case .week:
            let start = mondayStartOfWeek(for: anchor, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            unclipped = StatisticsDateRange(start: start, end: end)
        case .day:
            unclipped = StatisticsDateRange(start: anchor, end: anchor)
        }

        return StatisticsDateRange(
            start: max(unclipped.start, window.start),
            end: min(unclipped.end, window.end)
        )
    }
}

struct StatisticsBookContribution: Equatable {
    let bookID: UUID
    let title: String
    let coverPath: String?
    let characters: Int
    let readingTime: Double
}

struct StatisticsDayAggregate: Equatable {
    let date: Date
    let characters: Int
    let readingTime: Double
    let bookContributions: [StatisticsBookContribution]

    var activeBookCount: Int {
        bookContributions.filter { $0.characters > 0 || $0.readingTime > 0 }.count
    }

    func targetRatio(settings: StatisticsTargetSettings) -> Double {
        switch settings.dailyTargetType {
        case .characters:
            guard settings.dailyCharacterTarget > 0 else { return 0 }
            return Double(characters) / Double(settings.dailyCharacterTarget)
        case .duration:
            let targetSeconds = Double(settings.dailyDurationTargetMinutes * 60)
            guard targetSeconds > 0 else { return 0 }
            return readingTime / targetSeconds
        }
    }
}

struct StatisticsDashboardSnapshot: Equatable {
    var days: [StatisticsDayAggregate]
    var skippedCorruptBookIDs: [UUID] = []
}

struct StatisticsTodaySummary: Equatable {
    let date: Date
    let targetPercent: Int
    let characters: Int
    let readingTime: Double
    let averageSpeedPerHour: Int
    let dailyStreakDays: Int
}

struct StatisticsWeekDaySummary: Equatable {
    let date: Date
    let isToday: Bool
    let isFuture: Bool
    let percent: Int?
    let metTarget: Bool
}

struct StatisticsWeekSummary: Equatable {
    let range: StatisticsDateRange
    let elapsedDays: Int
    let characters: Int
    let readingTime: Double
    let averageSpeedPerHour: Int
    let targetDays: Int
    let metTargetDays: Int
    let dailyStreakDays: Int
    let weeklyStreakWeeks: Int
    let averageCharactersPerElapsedDay: Int
    let averageReadingTimePerElapsedDay: Double
    let days: [StatisticsWeekDaySummary]
}

struct StatisticsRangeSummary: Equatable {
    let characters: Int
    let readingTime: Double
    let averageSpeedPerHour: Int
    let targetDays: Int
    let targetProgressPercent: Int
}

struct StatisticsTrendPoint: Equatable, Identifiable {
    let id: String
    let label: String
    let characters: Int
    let readingTime: Double
}

struct StatisticsDistributionRow: Equatable, Identifiable {
    let id: UUID
    let title: String
    let coverPath: String?
    let characters: Int
    let readingTime: Double
    let percent: Int
}

enum StatisticsDashboardCalculator {
    static func todaySummary(
        snapshot: StatisticsDashboardSnapshot,
        today: Date,
        settings: StatisticsTargetSettings,
        calendar: Calendar
    ) -> StatisticsTodaySummary {
        let daysByDate = dictionaryByDate(snapshot.days, calendar: calendar)
        let today = calendar.startOfDay(for: today)
        let aggregate = daysByDate[today] ?? emptyDay(today)
        return StatisticsTodaySummary(
            date: today,
            targetPercent: percent(aggregate.targetRatio(settings: settings)),
            characters: aggregate.characters,
            readingTime: aggregate.readingTime,
            averageSpeedPerHour: averageSpeedPerHour(characters: aggregate.characters, readingTime: aggregate.readingTime),
            dailyStreakDays: dailyGoalStreak(daysByDate: daysByDate, today: today, settings: settings, calendar: calendar)
        )
    }

    static func weekSummary(
        snapshot: StatisticsDashboardSnapshot,
        today: Date,
        settings: StatisticsTargetSettings,
        calendar: Calendar
    ) -> StatisticsWeekSummary {
        let daysByDate = dictionaryByDate(snapshot.days, calendar: calendar)
        let today = calendar.startOfDay(for: today)
        let start = StatisticsDateRange.mondayStartOfWeek(for: today, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let range = StatisticsDateRange(start: start, end: end)
        let dates = dates(in: range, calendar: calendar)
        let aggregates = dates.map { daysByDate[$0] ?? emptyDay($0) }
        let summary = aggregateRange(aggregates, settings: settings)
        let elapsedDays = min(max(calendar.dateComponents([.day], from: start, to: today).day.map { $0 + 1 } ?? 1, 1), 7)

        return StatisticsWeekSummary(
            range: range,
            elapsedDays: elapsedDays,
            characters: summary.characters,
            readingTime: summary.readingTime,
            averageSpeedPerHour: summary.averageSpeedPerHour,
            targetDays: settings.weeklyTargetDays,
            metTargetDays: aggregates.filter { $0.targetRatio(settings: settings) >= 1 }.count,
            dailyStreakDays: dailyGoalStreak(daysByDate: daysByDate, today: today, settings: settings, calendar: calendar),
            weeklyStreakWeeks: weeklyGoalStreak(daysByDate: daysByDate, today: today, settings: settings, calendar: calendar),
            averageCharactersPerElapsedDay: Int((Double(summary.characters) / Double(elapsedDays)).rounded()),
            averageReadingTimePerElapsedDay: summary.readingTime / Double(elapsedDays),
            days: dates.map { date in
                let aggregate = daysByDate[date]
                let isFuture = date > today
                let ratio = aggregate?.targetRatio(settings: settings) ?? 0
                return StatisticsWeekDaySummary(
                    date: date,
                    isToday: date == today,
                    isFuture: isFuture,
                    percent: aggregate == nil || isFuture ? nil : percent(ratio),
                    metTarget: !isFuture && ratio >= 1
                )
            }
        )
    }

    static func rangeSummary(
        days: [StatisticsDayAggregate],
        range: StatisticsDateRange,
        settings: StatisticsTargetSettings,
        calendar: Calendar
    ) -> StatisticsRangeSummary {
        let rangeDays = dates(in: range, calendar: calendar)
        let daysByDate = dictionaryByDate(days, calendar: calendar)
        return aggregateRange(rangeDays.map { daysByDate[$0] ?? emptyDay($0) }, settings: settings)
    }

    static func trendPoints(
        mode: StatisticsRangeMode,
        range: StatisticsDateRange,
        days: [StatisticsDayAggregate],
        calendar: Calendar
    ) -> [StatisticsTrendPoint] {
        switch mode {
        case .day:
            return []
        case .year:
            let grouped = Dictionary(grouping: days.filter { range.contains($0.date, calendar: calendar) }) { day in
                calendar.dateComponents([.year, .month], from: day.date)
            }
            var result: [StatisticsTrendPoint] = []
            var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: range.start)) ?? range.start
            let endMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: range.end)) ?? range.end
            while cursor <= endMonth {
                let components = calendar.dateComponents([.year, .month], from: cursor)
                let groupedDays = grouped[components].orEmpty
                let month = components.month ?? 1
                result.append(
                    StatisticsTrendPoint(
                        id: "\(components.year ?? 0)-\(month)",
                        label: "\(month)",
                        characters: groupedDays.reduce(0) { $0 + $1.characters },
                        readingTime: groupedDays.reduce(0) { $0 + $1.readingTime }
                    )
                )
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? endMonth.addingTimeInterval(1)
            }
            return result
        case .month, .week:
            let daysByDate = dictionaryByDate(days, calendar: calendar)
            return dates(in: range, calendar: calendar).map { date in
                let day = daysByDate[date]
                return StatisticsTrendPoint(
                    id: Self.isoDateString(date, calendar: calendar),
                    label: "\(calendar.component(.day, from: date))",
                    characters: day?.characters ?? 0,
                    readingTime: day?.readingTime ?? 0
                )
            }
        }
    }

    static func distributionRows(
        days: [StatisticsDayAggregate],
        range: StatisticsDateRange,
        targetType: DailyTargetType
    ) -> [StatisticsDistributionRow] {
        var grouped: [UUID: [StatisticsBookContribution]] = [:]
        for day in days where range.contains(day.date, calendar: .current) {
            for contribution in day.bookContributions where contribution.characters > 0 || contribution.readingTime > 0 {
                grouped[contribution.bookID, default: []].append(contribution)
            }
        }

        let totals = grouped.compactMap { bookID, contributions -> StatisticsDistributionRow? in
            guard let first = contributions.first else { return nil }
            return StatisticsDistributionRow(
                id: bookID,
                title: first.title,
                coverPath: first.coverPath,
                characters: contributions.reduce(0) { $0 + $1.characters },
                readingTime: contributions.reduce(0) { $0 + $1.readingTime },
                percent: 0
            )
        }

        let base = totals.reduce(0.0) { partial, row in
            partial + metricValue(row, targetType: targetType)
        }

        return totals
            .map { row in
                StatisticsDistributionRow(
                    id: row.id,
                    title: row.title,
                    coverPath: row.coverPath,
                    characters: row.characters,
                    readingTime: row.readingTime,
                    percent: base > 0 ? percent(metricValue(row, targetType: targetType) / base) : 0
                )
            }
            .sorted {
                let left = metricValue($0, targetType: targetType)
                let right = metricValue($1, targetType: targetType)
                if left != right {
                    return left > right
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    static func dates(in range: StatisticsDateRange, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        var cursor = range.start
        while cursor <= range.end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    static func averageSpeedPerHour(characters: Int, readingTime: Double) -> Int {
        guard readingTime > 0 else { return 0 }
        return Int((Double(characters) / readingTime * 3_600).rounded())
    }

    private static func aggregateRange(_ days: [StatisticsDayAggregate], settings: StatisticsTargetSettings) -> StatisticsRangeSummary {
        let characters = days.reduce(0) { $0 + $1.characters }
        let readingTime = days.reduce(0) { $0 + $1.readingTime }
        return StatisticsRangeSummary(
            characters: characters,
            readingTime: readingTime,
            averageSpeedPerHour: averageSpeedPerHour(characters: characters, readingTime: readingTime),
            targetDays: days.filter { $0.targetRatio(settings: settings) >= 1 }.count,
            targetProgressPercent: days.count == 1 ? percent(days[0].targetRatio(settings: settings)) : 0
        )
    }

    private static func dailyGoalStreak(
        daysByDate: [Date: StatisticsDayAggregate],
        today: Date,
        settings: StatisticsTargetSettings,
        calendar: Calendar
    ) -> Int {
        var cursor = today
        if (daysByDate[today]?.targetRatio(settings: settings) ?? 0) < 1 {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        var streak = 0
        while (daysByDate[cursor]?.targetRatio(settings: settings) ?? 0) >= 1 {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return streak
    }

    private static func weeklyGoalStreak(
        daysByDate: [Date: StatisticsDayAggregate],
        today: Date,
        settings: StatisticsTargetSettings,
        calendar: Calendar
    ) -> Int {
        var weekStart = StatisticsDateRange.mondayStartOfWeek(for: today, calendar: calendar)
        if !weekMet(daysByDate: daysByDate, weekStart: weekStart, settings: settings, calendar: calendar) {
            weekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        }

        var streak = 0
        while weekMet(daysByDate: daysByDate, weekStart: weekStart, settings: settings, calendar: calendar) {
            streak += 1
            weekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        }
        return streak
    }

    private static func weekMet(
        daysByDate: [Date: StatisticsDayAggregate],
        weekStart: Date,
        settings: StatisticsTargetSettings,
        calendar: Calendar
    ) -> Bool {
        (0..<7).filter { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return false }
            return (daysByDate[date]?.targetRatio(settings: settings) ?? 0) >= 1
        }.count >= settings.weeklyTargetDays
    }

    private static func dictionaryByDate(_ days: [StatisticsDayAggregate], calendar: Calendar) -> [Date: StatisticsDayAggregate] {
        Dictionary(uniqueKeysWithValues: days.map { (calendar.startOfDay(for: $0.date), $0) })
    }

    private static func emptyDay(_ date: Date) -> StatisticsDayAggregate {
        StatisticsDayAggregate(date: date, characters: 0, readingTime: 0, bookContributions: [])
    }

    private static func metricValue(_ row: StatisticsDistributionRow, targetType: DailyTargetType) -> Double {
        switch targetType {
        case .characters:
            Double(row.characters)
        case .duration:
            row.readingTime
        }
    }

    private static func percent(_ ratio: Double) -> Int {
        Int((ratio * 100).rounded())
    }

    private static func isoDateString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

enum StatisticsDashboardRepository {
    private static let statisticsFileName = "statistics.json"

    static func loadSnapshot(
        books: [BookMetadata],
        booksDirectory: URL,
        calendar: Calendar
    ) -> StatisticsDashboardSnapshot {
        var skippedCorruptBookIDs: [UUID] = []
        var contributionsByDate: [Date: [StatisticsBookContribution]] = [:]
        let decoder = JSONDecoder()

        for book in books {
            let root = booksDirectory.appendingPathComponent(book.folder)
            let statisticsURL = root.appendingPathComponent(statisticsFileName)
            guard FileManager.default.fileExists(atPath: statisticsURL.path(percentEncoded: false)) else {
                continue
            }

            let statistics: [Statistics]
            do {
                let data = try Data(contentsOf: statisticsURL)
                statistics = try decoder.decode([Statistics].self, from: data)
            } catch {
                skippedCorruptBookIDs.append(book.id)
                continue
            }

            let coverPath = resolvedCoverPath(
                for: book,
                root: root,
                booksDirectory: booksDirectory
            )

            for statistic in deduplicateStatistics(statistics) where statistic.charactersRead > 0 || statistic.readingTime > 0 {
                guard let date = parseDateKey(statistic.dateKey, calendar: calendar) else { continue }
                let contribution = StatisticsBookContribution(
                    bookID: book.id,
                    title: book.displayTitle.isEmpty ? statistic.title : book.displayTitle,
                    coverPath: coverPath,
                    characters: statistic.charactersRead,
                    readingTime: statistic.readingTime
                )
                contributionsByDate[date, default: []].append(contribution)
            }
        }

        let days = contributionsByDate
            .map { date, contributions in
                StatisticsDayAggregate(
                    date: date,
                    characters: contributions.reduce(0) { $0 + $1.characters },
                    readingTime: contributions.reduce(0) { $0 + $1.readingTime },
                    bookContributions: contributions.sorted {
                        $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }
                )
            }
            .sorted { $0.date < $1.date }

        return StatisticsDashboardSnapshot(days: days, skippedCorruptBookIDs: skippedCorruptBookIDs)
    }

    private static func deduplicateStatistics(_ statistics: [Statistics]) -> [Statistics] {
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

    private static func parseDateKey(_ dateKey: String, calendar: Calendar) -> Date? {
        let parts = dateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            .map(calendar.startOfDay(for:))
    }

    private static func resolvedCoverPath(for book: BookMetadata, root: URL, booksDirectory: URL) -> String? {
        guard let cover = book.cover else { return nil }
        if cover.hasPrefix("/") {
            return cover
        }
        if cover.hasPrefix("Books/") {
            return booksDirectory
                .deletingLastPathComponent()
                .appendingPathComponent(cover)
                .path(percentEncoded: false)
        }
        return root.appendingPathComponent(cover).path(percentEncoded: false)
    }
}

private extension Optional where Wrapped == [StatisticsDayAggregate] {
    var orEmpty: [StatisticsDayAggregate] {
        self ?? []
    }
}
