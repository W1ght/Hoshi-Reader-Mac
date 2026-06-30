import Foundation

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message). expected=\(expected) actual=\(actual)\n", stderr)
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct StatisticsDashboardCalculationTests {
static func main() throws {
let calendar = Calendar(identifier: .gregorian)
let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
let monday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 29))!
let june24 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 24))!
let june25 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 25))!
let june26 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 26))!
let june30 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 30))!

let settings = StatisticsTargetSettings(
    dailyTargetType: .characters,
    dailyCharacterTarget: 5_000,
    dailyDurationTargetMinutes: 30,
    weeklyTargetDays: 2
)

let firstBook = StatisticsBookContribution(
    bookID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
    title: "Alpha",
    coverPath: "/covers/alpha.jpg",
    characters: 4_000,
    readingTime: 1_800
)
let firstBookJune25 = StatisticsBookContribution(
    bookID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
    title: "Alpha",
    coverPath: "/covers/alpha.jpg",
    characters: 5_200,
    readingTime: 2_600
)
let firstBookJune26 = StatisticsBookContribution(
    bookID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
    title: "Alpha",
    coverPath: "/covers/alpha.jpg",
    characters: 5_100,
    readingTime: 2_400
)
let secondBook = StatisticsBookContribution(
    bookID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
    title: "Beta",
    coverPath: nil,
    characters: 2_000,
    readingTime: 900
)
let secondBookToday = StatisticsBookContribution(
    bookID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
    title: "Beta",
    coverPath: nil,
    characters: 3_500,
    readingTime: 1_800
)

let days = [
    StatisticsDayAggregate(date: june24, characters: 4_000, readingTime: 1_800, bookContributions: [firstBook]),
    StatisticsDayAggregate(date: june25, characters: 5_200, readingTime: 2_600, bookContributions: [firstBookJune25]),
    StatisticsDayAggregate(date: june26, characters: 5_100, readingTime: 2_400, bookContributions: [firstBookJune26]),
    StatisticsDayAggregate(date: june30, characters: 6_000, readingTime: 2_700, bookContributions: [firstBook, secondBook]),
    StatisticsDayAggregate(date: today, characters: 3_500, readingTime: 1_800, bookContributions: [secondBookToday])
]

let recentWindow = StatisticsDateRange.recentYear(endingAt: today, calendar: calendar)
assertEqual(recentWindow.start, calendar.date(from: DateComponents(year: 2025, month: 7, day: 2))!, "recent year starts one year plus one day before today")
assertEqual(recentWindow.end, today, "recent year ends today")
assertEqual(StatisticsDateRange.fixedYear(2026, today: today, calendar: calendar).end, today, "current fixed year clips to today")
assertEqual(StatisticsDateRange.fixedYear(2025, today: today, calendar: calendar).end, calendar.date(from: DateComponents(year: 2025, month: 12, day: 31))!, "past fixed year ends on Dec 31")
assertEqual(StatisticsDateRange.mondayStartOfWeek(for: today, calendar: calendar), monday, "week starts on Monday")

let weekRange = StatisticsDateRange.selectedRange(mode: .week, anchor: today, window: recentWindow, calendar: calendar)
assertEqual(weekRange.start, monday, "week selection starts Monday")
assertEqual(weekRange.end, today, "week selection clips to the current statistics window")

let snapshot = StatisticsDashboardSnapshot(days: days, skippedCorruptBookIDs: [UUID()])
let todaySummary = StatisticsDashboardCalculator.todaySummary(snapshot: snapshot, today: today, settings: settings, calendar: calendar)
assertEqual(todaySummary.characters, 3_500, "today characters")
assertEqual(todaySummary.readingTime, 1_800, "today reading time")
assertEqual(todaySummary.targetPercent, 70, "today target percent")
assertEqual(todaySummary.dailyStreakDays, 1, "daily streak falls back to previous completed days when today is incomplete")

let weekSummary = StatisticsDashboardCalculator.weekSummary(snapshot: snapshot, today: today, settings: settings, calendar: calendar)
assertEqual(weekSummary.range.start, monday, "week summary starts Monday")
assertEqual(weekSummary.characters, 9_500, "week summary sums elapsed/future week dates")
assertEqual(weekSummary.metTargetDays, 1, "week summary counts met target days")
assertEqual(weekSummary.weeklyStreakWeeks, 1, "weekly streak includes previous completed week when current week incomplete")

let rangeSummary = StatisticsDashboardCalculator.rangeSummary(days: days, range: StatisticsDateRange(start: june24, end: today), settings: settings, calendar: calendar)
assertEqual(rangeSummary.characters, 23_800, "range summary sums characters")
assertEqual(rangeSummary.readingTime, 11_300, "range summary sums time")
assertEqual(rangeSummary.averageSpeedPerHour, 7_582, "range summary calculates hourly speed")
assertEqual(rangeSummary.targetDays, 3, "range summary counts target days")

let trend = StatisticsDashboardCalculator.trendPoints(mode: .week, range: weekRange, days: days, calendar: calendar)
assertEqual(trend.count, 3, "week trend includes clipped selected range days")
assertEqual(trend[0].characters, 0, "week trend fills missing Monday with zero")
assertEqual(trend[1].characters, 6_000, "week trend includes Tuesday data")
assertEqual(trend[2].characters, 3_500, "week trend includes Wednesday data")

let distribution = StatisticsDashboardCalculator.distributionRows(days: days, range: StatisticsDateRange(start: june24, end: today), targetType: .characters)
assertEqual(distribution.count, 2, "distribution groups by book")
assertEqual(distribution[0].title, "Alpha", "distribution sorts by selected metric")
assertEqual(distribution[0].percent, 77, "distribution calculates character percentage")
assertEqual(distribution[1].percent, 23, "distribution calculates second percentage")

let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hoshi-statistics-dashboard-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempRoot) }

let validBookID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
let invalidBookID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
let validBook = BookMetadata(id: validBookID, title: "Valid Book", cover: "cover.jpg", folder: "valid", lastAccess: today)
let invalidBook = BookMetadata(id: invalidBookID, title: "Broken Book", cover: nil, folder: "broken", lastAccess: today)
let validRoot = tempRoot.appendingPathComponent(validBook.folder)
let invalidRoot = tempRoot.appendingPathComponent(invalidBook.folder)
try FileManager.default.createDirectory(at: validRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: true)
let validStats = [
    Statistics(title: "Ignored Title", dateKey: "2026-07-01", charactersRead: 1_200, readingTime: 600, minReadingSpeed: 0, altMinReadingSpeed: 0, lastReadingSpeed: 7_200, maxReadingSpeed: 7_200, lastStatisticModified: 1)
]
let encoded = try JSONEncoder().encode(validStats)
try encoded.write(to: validRoot.appendingPathComponent("statistics.json"))
try Data("{not-json".utf8).write(to: invalidRoot.appendingPathComponent("statistics.json"))

let loaded = StatisticsDashboardRepository.loadSnapshot(books: [validBook, invalidBook], booksDirectory: tempRoot, calendar: calendar)
assertEqual(loaded.days.count, 1, "repository loads valid statistics")
assertEqual(loaded.days[0].characters, 1_200, "repository preserves characters")
assertEqual(loaded.days[0].bookContributions[0].title, "Valid Book", "repository prefers current display title")
assertEqual(loaded.days[0].bookContributions[0].coverPath, validRoot.appendingPathComponent("cover.jpg").path(percentEncoded: false), "repository resolves relative cover paths from the book root")
assertEqual(loaded.skippedCorruptBookIDs, [invalidBookID], "repository reports corrupt statistics")

print("statistics dashboard calculation tests passed")
}
}
