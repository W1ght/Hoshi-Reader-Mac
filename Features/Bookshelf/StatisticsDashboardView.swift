//
//  StatisticsDashboardView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct StatisticsDashboardView: View {
    let books: [BookMetadata]

    @Environment(UserConfig.self) private var userConfig
    @State private var snapshot = StatisticsDashboardSnapshot(days: [])
    @State private var selectedMode: StatisticsRangeMode = .week
    @State private var selectedAnchor: Date?
    @State private var selectedTab: StatisticsDashboardRangeTab = .overview

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var targetSettings: StatisticsTargetSettings {
        StatisticsTargetSettings(
            dailyTargetType: userConfig.dailyStatisticsTargetType,
            dailyCharacterTarget: userConfig.dailyStatisticsCharacterTarget,
            dailyDurationTargetMinutes: userConfig.dailyStatisticsDurationTargetMinutes,
            weeklyTargetDays: userConfig.weeklyStatisticsTargetDays
        ).clamped()
    }
    private var windowRange: StatisticsDateRange {
        StatisticsDateRange.recentYear(endingAt: today, calendar: calendar)
    }
    private var anchorDate: Date {
        windowRange.coerce(
            selectedAnchor ?? snapshot.days.last?.date ?? today,
            calendar: calendar
        )
    }
    private var selectedRange: StatisticsDateRange {
        StatisticsDateRange.selectedRange(
            mode: selectedMode,
            anchor: anchorDate,
            window: windowRange,
            calendar: calendar
        )
    }
    private var todaySummary: StatisticsTodaySummary {
        StatisticsDashboardCalculator.todaySummary(
            snapshot: snapshot,
            today: today,
            settings: targetSettings,
            calendar: calendar
        )
    }
    private var weekSummary: StatisticsWeekSummary {
        StatisticsDashboardCalculator.weekSummary(
            snapshot: snapshot,
            today: today,
            settings: targetSettings,
            calendar: calendar
        )
    }
    private var rangeSummary: StatisticsRangeSummary {
        StatisticsDashboardCalculator.rangeSummary(
            days: snapshot.days,
            range: selectedRange,
            settings: targetSettings,
            calendar: calendar
        )
    }
    private var trendPoints: [StatisticsTrendPoint] {
        StatisticsDashboardCalculator.trendPoints(
            mode: selectedMode,
            range: selectedRange,
            days: snapshot.days,
            calendar: calendar
        )
    }
    private var distributionRows: [StatisticsDistributionRow] {
        StatisticsDashboardCalculator.distributionRows(
            days: snapshot.days,
            range: selectedRange,
            targetType: targetSettings.dailyTargetType
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    corruptStatisticsWarning
                    if snapshot.days.isEmpty {
                        ContentUnavailableView {
                            Label("No Reading Records", systemImage: "chart.xyaxis.line")
                        } description: {
                            Text("Start the Reader statistics timer to collect dashboard data.")
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                        .nativeGlassCardSurface(cornerRadius: 18)
                    } else {
                        dashboardLayout(width: max(proxy.size.width - 48, 0))
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { NativeGlassPageBackground() }
        .onAppear(perform: reloadSnapshot)
        .onChange(of: books) { _, _ in
            reloadSnapshot()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Statistics")
                .font(.largeTitle.weight(.bold))
            Text("Recent year")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dashboardLayout(width: CGFloat) -> some View {
        if width >= 1_260 {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 18) {
                    todaySection
                    weekSection
                    calendarSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(spacing: 18) {
                    selectedRangeSection
                    trendSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                distributionSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else if width >= 840 {
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 18) {
                    todaySection
                    weekSection
                    calendarSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(spacing: 18) {
                    selectedRangeSection
                    trendSection
                    distributionSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(spacing: 18) {
                todaySection
                weekSection
                calendarSection
                selectedRangeSection
                trendSection
                distributionSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var corruptStatisticsWarning: some View {
        if !snapshot.skippedCorruptBookIDs.isEmpty {
            Label("Some statistics are temporarily unavailable.", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nativeGlassCardSurface(cornerRadius: 14)
        }
    }

    private var todaySection: some View {
        StatisticsDashboardCard {
            HStack(alignment: .center, spacing: 20) {
                goalRing(percent: todaySummary.targetPercent)
                    .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(
                        title: "Today",
                        detail: String(
                            format: String(localized: "Goal: %@"),
                            dailyTargetText
                        )
                    )
                    metricGrid([
                        ("Duration", formatDuration(todaySummary.readingTime)),
                        ("Characters", formatCharacters(todaySummary.characters)),
                        ("Speed", formatSpeed(todaySummary.averageSpeedPerHour)),
                        ("Streak", String(format: String(localized: "%d days"), todaySummary.dailyStreakDays))
                    ])
                }
            }
        }
    }

    private var weekSection: some View {
        StatisticsDashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "This Week",
                    detail: String(format: String(localized: "%d/7 days"), weekSummary.metTargetDays)
                )
                metricGrid([
                    ("Duration", formatDuration(weekSummary.readingTime)),
                    ("Characters", formatCharacters(weekSummary.characters)),
                    ("Avg Characters", formatCharacters(weekSummary.averageCharactersPerElapsedDay)),
                    ("Speed", formatSpeed(weekSummary.averageSpeedPerHour))
                ])
                HStack(spacing: 8) {
                    ForEach(weekSummary.days, id: \.date) { day in
                        VStack(spacing: 4) {
                            Text(shortWeekday(day.date))
                                .font(.caption2.weight(.bold))
                            Text(day.percent.map { "\($0)%" } ?? "-")
                                .font(.caption2.monospacedDigit())
                        }
                        .foregroundStyle(day.metTarget ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(day.metTarget ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
                                .overlay {
                                    if day.isToday {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private var calendarSection: some View {
        StatisticsDashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    sectionHeader(title: "Reading Calendar", detail: selectedRangeTitle)
                    Spacer()
                    NativeGlassSegmentedPicker(
                        selection: $selectedMode,
                        values: StatisticsRangeMode.allCases,
                        minSegmentWidth: 50
                    ) { mode in
                        rangeModeText(mode)
                    }
                    .onChange(of: selectedMode) { _, mode in
                        if mode == .day, selectedTab == .trend {
                            selectedTab = .overview
                        }
                    }
                }
                heatmap
                HStack {
                    Text("Selected: \(selectedRangeTitle)")
                    Spacer()
                    Text(String(format: String(localized: "%d days"), selectedRange.dayCount(calendar: calendar)))
                        .monospacedDigit()
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var heatmap: some View {
        let dates = StatisticsDashboardCalculator.dates(in: windowRange, calendar: calendar)
        let daysByDate = Dictionary(uniqueKeysWithValues: snapshot.days.map { (calendar.startOfDay(for: $0.date), $0) })
        let maxCharacters = max(snapshot.days.map(\.characters).max() ?? 0, 1)
        let rows = Array(repeating: GridItem(.fixed(12), spacing: 4), count: 7)
        return ScrollView(.horizontal) {
            LazyHGrid(rows: rows, spacing: 4) {
                ForEach(dates, id: \.self) { date in
                    let day = daysByDate[date]
                    Button {
                        selectedAnchor = date
                    } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(heatColor(characters: day?.characters ?? 0, maxCharacters: maxCharacters))
                            .frame(width: 12, height: 12)
                            .overlay {
                                if selectedMode != .year, selectedRange.contains(date, calendar: calendar) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help("\(formattedDate(date)): \(formatCharacters(day?.characters ?? 0))")
                }
            }
            .padding(10)
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var selectedRangeSection: some View {
        StatisticsDashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(title: "Selected Range", detail: selectedRangeTitle)
                NativeGlassSegmentedPicker(
                    selection: $selectedTab,
                    values: selectedTabValues,
                    minSegmentWidth: 72,
                    fillsWidth: true
                ) { tab in
                    selectedTabText(tab)
                }
                switch selectedTab {
                case .overview:
                    metricGrid([
                        ("Duration", formatDuration(rangeSummary.readingTime)),
                        ("Characters", formatCharacters(rangeSummary.characters)),
                        ("Speed", formatSpeed(rangeSummary.averageSpeedPerHour)),
                        (selectedMode == .day ? "Goal Progress" : "Days Met", selectedMode == .day ? "\(rangeSummary.targetProgressPercent)%" : String(format: String(localized: "%d days"), rangeSummary.targetDays))
                    ])
                case .trend:
                    trendChart
                case .distribution:
                    distributionList
                }
            }
        }
    }

    private var trendSection: some View {
        StatisticsDashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Trend", detail: String(localized: "Characters / Duration"))
                trendChart
            }
        }
    }

    private var trendChart: some View {
        let maxCharacters = max(trendPoints.map(\.characters).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 7) {
            if trendPoints.isEmpty {
                ContentUnavailableView("No trend data", systemImage: "chart.bar")
                    .frame(minHeight: 130)
            } else {
                ForEach(trendPoints) { point in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.accentColor.gradient)
                            .frame(height: max(CGFloat(point.characters) / CGFloat(maxCharacters) * 130, point.characters > 0 ? 8 : 2))
                        Text(point.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(point.label): \(formatCharacters(point.characters)), \(formatDuration(point.readingTime))")
                }
            }
        }
        .frame(minHeight: 154, alignment: .bottom)
    }

    private var distributionSection: some View {
        StatisticsDashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "By Book", detail: selectedRangeTitle)
                distributionList
            }
        }
    }

    private var distributionList: some View {
        VStack(spacing: 0) {
            if distributionRows.isEmpty {
                ContentUnavailableView("No reading records", systemImage: "books.vertical")
                    .frame(minHeight: 120)
            } else {
                ForEach(distributionRows) { row in
                    HStack(spacing: 10) {
                        CoverImage(url: row.coverPath.map(URL.init(fileURLWithPath:)), maxPixelSize: 180) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.secondary.opacity(0.16))
                        }
                        .frame(width: 30, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text("\(formatCharacters(row.characters)) · \(formatDuration(row.readingTime))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("\(row.percent)%")
                            .font(.callout.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, 9)
                    if row.id != distributionRows.last?.id {
                        Divider().opacity(0.5)
                    }
                }
            }
        }
    }

    private var selectedTabValues: [StatisticsDashboardRangeTab] {
        selectedMode == .day ? [.overview, .distribution] : StatisticsDashboardRangeTab.allCases
    }

    private var dailyTargetText: String {
        switch targetSettings.dailyTargetType {
        case .characters:
            String(format: String(localized: "%@ chars"), targetSettings.dailyCharacterTarget.formatted(.number.grouping(.automatic)))
        case .duration:
            formatDuration(Double(targetSettings.dailyDurationTargetMinutes * 60))
        }
    }

    private var selectedRangeTitle: String {
        switch selectedMode {
        case .year:
            return String(localized: "Recent year")
        case .month:
            let components = calendar.dateComponents([.year, .month], from: selectedRange.start)
            return "\(components.year ?? 0)-\(components.month ?? 0)"
        case .week:
            return "\(monthDay(selectedRange.start))-\(monthDay(selectedRange.end))"
        case .day:
            return formattedDate(selectedRange.start)
        }
    }

    private func sectionHeader(title: LocalizedStringKey, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline.weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metricGrid(_ metrics: [(LocalizedStringKey, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(metrics.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    Text(metrics[index].0)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(metrics[index].1)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func goalRing(percent: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.14), lineWidth: 13)
            Circle()
                .trim(from: 0, to: min(CGFloat(percent) / 100, 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(percent)%")
                    .font(.title2.weight(.bold).monospacedDigit())
                Text("Goal")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func heatColor(characters: Int, maxCharacters: Int) -> Color {
        guard characters > 0 else { return Color.secondary.opacity(0.12) }
        let ratio = min(max(Double(characters) / Double(maxCharacters), 0.18), 1)
        return Color.accentColor.opacity(0.18 + 0.72 * ratio)
    }

    private func rangeModeText(_ mode: StatisticsRangeMode) -> some View {
        switch mode {
        case .year:
            Text("Year")
        case .month:
            Text("Month")
        case .week:
            Text("Week")
        case .day:
            Text("Day")
        }
    }

    private func selectedTabText(_ tab: StatisticsDashboardRangeTab) -> some View {
        switch tab {
        case .overview:
            Text("Overview")
        case .trend:
            Text("Trend")
        case .distribution:
            Text("By Book")
        }
    }

    private func formatCharacters(_ characters: Int) -> String {
        characters.formatted(.number.grouping(.automatic))
    }

    private func formatSpeed(_ speed: Int) -> String {
        String(format: String(localized: "%@/h"), speed.formatted(.number.grouping(.automatic)))
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = max(Int((seconds / 60).rounded()), 0)
        if minutes < 60 {
            return String(format: String(localized: "%dm"), minutes)
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return String(format: String(localized: "%dh"), hours)
        }
        return String(format: String(localized: "%dh %dm"), hours, remainder)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    }

    private func monthDay(_ date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }

    private func shortWeekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private func reloadSnapshot() {
        guard let booksDirectory = try? BookStorage.getBooksDirectory() else {
            snapshot = StatisticsDashboardSnapshot(days: [])
            return
        }
        snapshot = StatisticsDashboardRepository.loadSnapshot(
            books: books,
            booksDirectory: booksDirectory,
            calendar: calendar
        )
        if selectedAnchor == nil {
            selectedAnchor = snapshot.days.last?.date ?? today
        }
    }
}

private enum StatisticsDashboardRangeTab: String, CaseIterable, Identifiable {
    case overview
    case trend
    case distribution

    var id: String { rawValue }
}

private struct StatisticsDashboardCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .nativeGlassCardSurface(cornerRadius: 18)
    }
}
