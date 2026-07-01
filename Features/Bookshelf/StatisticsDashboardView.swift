//
//  StatisticsDashboardView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

private let statisticsDashboardSpacing: CGFloat = 16
private let statisticsBookRankingLimit = 12

private enum StatisticsTrendChartStyle: String, CaseIterable, Identifiable {
    case bar
    case line

    var id: String { rawValue }
}

struct StatisticsDashboardView: View {
    let books: [BookMetadata]
    let shelves: [BookShelf]

    @Environment(UserConfig.self) private var userConfig
    @State private var snapshot = StatisticsDashboardSnapshot(days: [])
    @State private var isLoadingSnapshot = false
    @State private var snapshotLoadGeneration = 0
    @State private var selectedMode: StatisticsRangeMode = .year
    @State private var selectedTrendGrain: StatisticsTrendGrain = .day
    @State private var selectedTrendMetric: StatisticsTrendMetric = .characters
    @State private var selectedTrendChartStyle: StatisticsTrendChartStyle = .bar
    @State private var selectedBookRankingMetric: StatisticsBookRankingMetric = .characters
    @State private var selectedAnchor: Date?
    @State private var selectedCalendarDate: Date?
    @State private var hasUserSelectedCalendarDate = false

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var isInitialSnapshotLoading: Bool {
        isLoadingSnapshot && snapshot.days.isEmpty
    }
    private var displaySnapshot: StatisticsDashboardSnapshot {
        isInitialSnapshotLoading ? placeholderSnapshot : snapshot
    }
    private var placeholderSnapshot: StatisticsDashboardSnapshot {
        StatisticsDashboardPlaceholder.snapshot(
            books: books,
            windowRange: windowRange,
            today: today,
            calendar: calendar
        )
    }
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
            selectedAnchor ?? displaySnapshot.days.last?.date ?? today,
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
    private var latestCalendarDate: Date {
        windowRange.coerce(displaySnapshot.days.last?.date ?? today, calendar: calendar)
    }
    private var calendarSelectionDate: Date {
        windowRange.coerce(selectedCalendarDate ?? selectedAnchor ?? latestCalendarDate, calendar: calendar)
    }
    private var calendarSelectionDay: StatisticsDayAggregate? {
        displaySnapshot.days.first { calendar.isDate($0.date, inSameDayAs: calendarSelectionDate) }
    }
    private var todaySummary: StatisticsTodaySummary {
        StatisticsDashboardCalculator.todaySummary(
            snapshot: displaySnapshot,
            today: today,
            settings: targetSettings,
            calendar: calendar
        )
    }
    private var weekSummary: StatisticsWeekSummary {
        StatisticsDashboardCalculator.weekSummary(
            snapshot: displaySnapshot,
            today: today,
            settings: targetSettings,
            calendar: calendar
        )
    }
    private var rangeSummary: StatisticsRangeSummary {
        StatisticsDashboardCalculator.rangeSummary(
            days: displaySnapshot.days,
            range: selectedRange,
            settings: targetSettings,
            calendar: calendar
        )
    }
    private var speedSummary: StatisticsSpeedSummary {
        StatisticsDashboardCalculator.speedSummary(
            days: displaySnapshot.days,
            range: selectedRange,
            calendar: calendar
        )
    }
    private var trendPoints: [StatisticsTrendPoint] {
        StatisticsDashboardCalculator.trendPoints(
            grain: selectedTrendGrain,
            range: selectedRange,
            days: displaySnapshot.days,
            calendar: calendar
        )
    }
    private var bookRankingRows: [StatisticsBookRankingRow] {
        StatisticsDashboardCalculator.bookRankingRows(
            days: displaySnapshot.days,
            range: selectedRange,
            metric: selectedBookRankingMetric,
            limit: statisticsBookRankingLimit
        )
    }
    private var shelfComparisonRows: [StatisticsShelfComparisonRow] {
        StatisticsDashboardCalculator.shelfComparisonRows(
            books: displaySnapshot.books,
            shelves: shelves,
            days: displaySnapshot.days,
            range: selectedRange,
            unshelvedName: String(localized: "Unshelved"),
            calendar: calendar
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - 48, 0)
            ScrollView {
                VStack(alignment: .leading, spacing: statisticsDashboardSpacing) {
                    header
                    corruptStatisticsWarning
                    if isInitialSnapshotLoading {
                        loadingDashboardPlaceholder(width: contentWidth)
                    } else if snapshot.days.isEmpty {
                        emptyDashboardState
                    } else {
                        dashboardLayoutWithLoadingOverlay(width: contentWidth)
                    }
                }
                .frame(width: contentWidth, alignment: .topLeading)
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
            Text(selectedRangeTitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyDashboardState: some View {
        VStack(alignment: .leading, spacing: statisticsDashboardSpacing) {
            targetSettingsSection
                .frame(maxWidth: 560, alignment: .topLeading)

            ContentUnavailableView {
                Label("No Reading Records", systemImage: "chart.xyaxis.line")
            } description: {
                Text("Open a book and start reading with statistics enabled.")
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .nativeGlassCardSurface(cornerRadius: 18)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func loadingDashboardPlaceholder(width: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            dashboardLayout(width: width)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            loadingStatusPill
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func dashboardLayout(width: CGFloat) -> some View {
        VStack(spacing: statisticsDashboardSpacing) {
            fullWidthTrendSection
            dashboardColumns(width: width)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func dashboardLayoutWithLoadingOverlay(width: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            dashboardLayout(width: width)

            if isLoadingSnapshot {
                loadingStatusPill
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var loadingStatusPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading Statistics")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .help(String(localized: "Scanning local reading records."))
    }

    private var fullWidthTrendSection: some View {
        trendSection
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func dashboardColumns(width: CGFloat) -> some View {
        if width >= 1_260 {
            let columnWidth = max((width - statisticsDashboardSpacing * 2) / 3, 260)
            let doubleColumnWidth = columnWidth * 2 + statisticsDashboardSpacing
            HStack(alignment: .top, spacing: statisticsDashboardSpacing) {
                VStack(spacing: statisticsDashboardSpacing) {
                    todaySection
                    targetSettingsSection
                    weekSection
                }
                .frame(width: columnWidth, alignment: .topLeading)

                VStack(spacing: statisticsDashboardSpacing) {
                    shelfComparisonSection
                        .frame(width: doubleColumnWidth, alignment: .topLeading)

                    HStack(alignment: .top, spacing: statisticsDashboardSpacing) {
                        VStack(spacing: statisticsDashboardSpacing) {
                            selectedRangeSection
                            calendarSection
                        }
                        .frame(width: columnWidth, alignment: .topLeading)

                        VStack(spacing: statisticsDashboardSpacing) {
                            speedSummarySection
                            bookRankingSection
                        }
                        .frame(width: columnWidth, alignment: .topLeading)
                    }
                }
                .frame(width: doubleColumnWidth, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else if width >= 840 {
            HStack(alignment: .top, spacing: statisticsDashboardSpacing) {
                VStack(spacing: statisticsDashboardSpacing) {
                    todaySection
                    targetSettingsSection
                    weekSection
                    calendarSection
                    shelfComparisonSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(spacing: statisticsDashboardSpacing) {
                    selectedRangeSection
                    speedSummarySection
                    bookRankingSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: statisticsDashboardSpacing) {
                todaySection
                targetSettingsSection
                weekSection
                calendarSection
                selectedRangeSection
                speedSummarySection
                bookRankingSection
                shelfComparisonSection
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
                        ("Speed", formatOptionalSpeed(todaySummary.averageSpeedPerHour)),
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
                    ("Speed", formatOptionalSpeed(weekSummary.averageSpeedPerHour))
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
                sectionHeader(title: "Reading Calendar", detail: selectedRangeTitle)
                heatmap
                calendarSelectionFooter
            }
        }
    }

    private var heatmap: some View {
        let dates = StatisticsDashboardCalculator.dates(in: windowRange, calendar: calendar)
        let daysByDate = Dictionary(uniqueKeysWithValues: displaySnapshot.days.map { (calendar.startOfDay(for: $0.date), $0) })
        let maxCharacters = max(displaySnapshot.days.map(\.characters).max() ?? 0, 1)
        let rows = Array(repeating: GridItem(.fixed(12), spacing: 4), count: 7)
        return ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHGrid(rows: rows, spacing: 4) {
                    ForEach(dates, id: \.self) { date in
                        let day = daysByDate[date]
                        let isSelectedDate = calendar.isDate(date, inSameDayAs: calendarSelectionDate)
                        Button {
                            let selectedDate = calendar.startOfDay(for: date)
                            selectedAnchor = selectedDate
                            selectedCalendarDate = selectedDate
                            hasUserSelectedCalendarDate = true
                        } label: {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(heatColor(characters: day?.characters ?? 0, maxCharacters: maxCharacters))
                                .frame(width: 12, height: 12)
                                .overlay {
                                    if selectedMode != .year, selectedRange.contains(date, calendar: calendar) {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                                    }
                                }
                                .overlay {
                                    if isSelectedDate {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .strokeBorder(Color.accentColor, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help("\(formattedFullDate(date)): \(formatCharacters(day?.characters ?? 0))")
                        .accessibilityLabel(Text("\(formattedFullDate(date)), \(formatCharacters(day?.characters ?? 0))"))
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.visible)
            .onAppear {
                scrollHeatmap(to: calendarSelectionDate, with: scrollProxy)
            }
            .onChange(of: calendarSelectionDate) { _, date in
                scrollHeatmap(to: date, with: scrollProxy)
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var calendarSelectionFooter: some View {
        let selectedDay = calendarSelectionDay
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: String(localized: "Selected: %@"), formattedFullDate(calendarSelectionDate)))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if selectedDay == nil {
                    Text("No reading records")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                calendarSelectionMetric(
                    title: "Characters",
                    value: formatCharacters(selectedDay?.characters ?? 0),
                    systemImage: "textformat"
                )
                calendarSelectionMetric(
                    title: "Duration",
                    value: formatDuration(selectedDay?.readingTime ?? 0),
                    systemImage: "clock"
                )
                calendarSelectionMetric(
                    title: "Books",
                    value: formatCharacters(selectedDay?.activeBookCount ?? 0),
                    systemImage: "books.vertical"
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var targetSettingsSection: some View {
        StatisticsDashboardCard {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader(title: "Goal", detail: dailyTargetText)
                    .padding(.bottom, 10)

                NativeSettingsRow("Goal Type") {
                    NativeGlassSegmentedPicker(
                        selection: Bindable(userConfig).dailyStatisticsTargetType,
                        values: DailyTargetType.allCases,
                        minSegmentWidth: 86
                    ) { targetType in
                        textOfDailyTargetType(targetType)
                    }
                }

                Divider().opacity(0.55)

                switch userConfig.dailyStatisticsTargetType {
                case .characters:
                    NativeSettingsStepperRow(
                        title: "Character Target",
                        value: "\(userConfig.dailyStatisticsCharacterTarget.formatted(.number.grouping(.automatic)))",
                        range: StatisticsTargetSettings.characterTargetRange,
                        step: StatisticsTargetSettings.characterTargetStep,
                        selection: Bindable(userConfig).dailyStatisticsCharacterTarget
                    )
                case .duration:
                    NativeSettingsStepperRow(
                        title: "Duration Target",
                        value: Duration.seconds(Double(userConfig.dailyStatisticsDurationTargetMinutes * 60)).formatted(.time(pattern: .hourMinute)),
                        range: StatisticsTargetSettings.durationTargetMinutesRange,
                        step: StatisticsTargetSettings.durationTargetMinutesStep,
                        selection: Bindable(userConfig).dailyStatisticsDurationTargetMinutes
                    )
                }

                Divider().opacity(0.55)

                NativeSettingsStepperRow(
                    title: "Weekly Target Days",
                    value: "\(userConfig.weeklyStatisticsTargetDays)",
                    range: StatisticsTargetSettings.weeklyTargetDaysRange,
                    step: 1,
                    selection: Bindable(userConfig).weeklyStatisticsTargetDays
                )

                Text("Goals recalculate historical progress and streaks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
    }

    private var selectedRangeSection: some View {
        StatisticsDashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(title: "Selected Range", detail: selectedRangeTitle)
                metricGrid([
                    ("Duration", formatDuration(rangeSummary.readingTime)),
                    ("Characters", formatCharacters(rangeSummary.characters)),
                    ("Speed", formatOptionalSpeed(rangeSummary.averageSpeedPerHour)),
                    (selectedMode == .day ? "Goal Progress" : "Days Met", selectedMode == .day ? "\(rangeSummary.targetProgressPercent)%" : String(format: String(localized: "%d days"), rangeSummary.targetDays))
                ])
            }
        }
    }

    private var bookRankingSection: some View {
        StatisticsDashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    sectionHeader(title: "Book Ranking", detail: selectedRangeTitle)
                    Spacer()
                    NativeGlassSegmentedPicker(
                        selection: $selectedBookRankingMetric,
                        values: StatisticsBookRankingMetric.allCases,
                        minSegmentWidth: 58
                    ) { metric in
                        bookRankingMetricText(metric)
                    }
                    .frame(maxWidth: 250)
                }

                VStack(spacing: 10) {
                    if bookRankingRows.isEmpty {
                        ContentUnavailableView("No reading records", systemImage: "list.number")
                            .frame(minHeight: 150)
                    } else {
                        let maxValue = max(bookRankingRows.map(bookRankingValue).max() ?? 0, 1)
                        ForEach(bookRankingRows) { row in
                            bookRankingRow(row, maxValue: maxValue)
                        }
                    }
                }
            }
        }
    }

    private var speedSummarySection: some View {
        StatisticsDashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(title: "Speed Summary", detail: selectedRangeTitle)
                metricGrid([
                    ("Weighted Avg", formatOptionalSpeed(speedSummary.weightedAverageSpeedPerHour)),
                    ("Typical Day", formatOptionalSpeed(speedSummary.medianDaySpeedPerHour)),
                    ("Last 7 Active Days", formatOptionalSpeed(speedSummary.recentActiveDaySpeedPerHour)),
                    ("Change vs First 14", formatSignedPercent(speedSummary.speedChangePercent)),
                    ("Fastest Day", formatSpeedDay(speedSummary.bestDay)),
                    ("Slowest Day", formatSpeedDay(speedSummary.worstDay))
                ])
                Text("Speed ignores reading samples under 1 minute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shelfComparisonSection: some View {
        StatisticsDashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(title: "Shelf Comparison", detail: selectedRangeTitle)
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        shelfComparisonHeader
                        Divider().opacity(0.55)
                        if shelfComparisonRows.isEmpty {
                            ContentUnavailableView("No reading records", systemImage: "folder")
                                .frame(minWidth: 640, minHeight: 96)
                        } else {
                            ForEach(shelfComparisonRows) { row in
                                shelfComparisonRow(row)
                                if row.id != shelfComparisonRows.last?.id {
                                    Divider().opacity(0.45)
                                }
                            }
                        }
                    }
                    .frame(minWidth: 660, alignment: .topLeading)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private var trendSection: some View {
        StatisticsDashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(title: "Range & Trend", detail: selectedRangeTitle)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        trendControl(title: "Range") {
                            NativeGlassSegmentedPicker(
                                selection: $selectedMode,
                                values: StatisticsRangeMode.allCases,
                                minSegmentWidth: 50
                            ) { mode in
                                rangeModeText(mode)
                            }
                        }
                        trendControl(title: "Time Grain") {
                            NativeGlassSegmentedPicker(
                                selection: $selectedTrendGrain,
                                values: StatisticsTrendGrain.allCases,
                                minSegmentWidth: 50
                            ) { grain in
                                trendGrainText(grain)
                            }
                        }
                        trendControl(title: "Metric") {
                            NativeGlassSegmentedPicker(
                                selection: $selectedTrendMetric,
                                values: StatisticsTrendMetric.allCases,
                                minSegmentWidth: 66
                            ) { metric in
                                trendMetricText(metric)
                            }
                        }
                        trendControl(title: "Style") {
                            NativeGlassSegmentedPicker(
                                selection: $selectedTrendChartStyle,
                                values: StatisticsTrendChartStyle.allCases,
                                minSegmentWidth: 44
                            ) { style in
                                trendChartStyleText(style)
                            }
                        }
                    }
                    .padding(.bottom, 1)
                }
                .scrollIndicators(.never)

                Text("Range filters all dashboard cards. Time Grain changes only the trend chart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                trendChart
            }
        }
    }

    private var trendChart: some View {
        let dataMaxValue = trendPoints.compactMap { $0.value(for: selectedTrendMetric) }.max() ?? 0
        let chartMaxValue = max(dataMaxValue * 1.1, 1)
        let chartHeight: CGFloat = 138
        return Group {
            if trendPoints.isEmpty {
                ContentUnavailableView("No trend data", systemImage: "chart.bar")
                    .frame(minHeight: 160)
            } else {
                GeometryReader { proxy in
                    let axisWidth: CGFloat = 54
                    let chartSpacing: CGFloat = 8
                    let availableChartWidth = max(proxy.size.width - axisWidth - chartSpacing, 1)
                    let contentWidth = trendContentWidth(availableWidth: availableChartWidth)

                    HStack(alignment: .top, spacing: chartSpacing) {
                        chartYAxis(maxValue: chartMaxValue, height: chartHeight)
                            .frame(width: axisWidth)

                        ScrollView(.horizontal) {
                            VStack(spacing: 6) {
                                ZStack(alignment: .bottomLeading) {
                                    chartGridLines(height: chartHeight)
                                    switch selectedTrendChartStyle {
                                    case .bar:
                                        trendBarChart(maxValue: chartMaxValue, chartHeight: chartHeight, contentWidth: contentWidth)
                                    case .line:
                                        trendLineChart(maxValue: chartMaxValue, chartHeight: chartHeight, contentWidth: contentWidth)
                                    }
                                }
                                .frame(width: contentWidth, height: chartHeight, alignment: .bottomLeading)

                                ZStack(alignment: .topLeading) {
                                    ForEach(Array(trendPoints.enumerated()), id: \.element.id) { index, point in
                                        if shouldShowTrendLabel(at: index) {
                                            Text(point.label)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.72)
                                                .frame(width: trendLabelWidth)
                                                .position(x: trendXPosition(for: index, contentWidth: contentWidth), y: 8)
                                        }
                                    }
                                }
                                .frame(width: contentWidth, height: 16, alignment: .topLeading)
                            }
                            .padding(.bottom, 2)
                        }
                        .scrollIndicators(.automatic)
                    }
                }
                .frame(minHeight: chartHeight + 28, alignment: .top)
            }
        }
    }

    private var dailyTargetText: String {
        switch targetSettings.dailyTargetType {
        case .characters:
            String(format: String(localized: "%@ chars"), targetSettings.dailyCharacterTarget.formatted(.number.grouping(.automatic)))
        case .duration:
            formatDuration(Double(targetSettings.dailyDurationTargetMinutes * 60))
        }
    }

    private var trendBarWidth: CGFloat {
        switch selectedTrendGrain {
        case .day:
            12
        case .week:
            22
        case .month:
            28
        }
    }

    private var trendLabelWidth: CGFloat {
        switch selectedTrendGrain {
        case .day:
            42
        case .week:
            66
        case .month:
            58
        }
    }

    private func trendContentWidth(availableWidth: CGFloat) -> CGFloat {
        let naturalWidth = CGFloat(trendPoints.count) * trendBarWidth + CGFloat(max(trendPoints.count - 1, 0)) * trendSpacing
        return max(naturalWidth, availableWidth, 1)
    }

    private var trendSpacing: CGFloat {
        switch selectedTrendGrain {
        case .day:
            5
        case .week:
            8
        case .month:
            10
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

    private func trendControl<Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
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

    private func calendarSelectionMetric(
        title: LocalizedStringKey,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func bookRankingRow(_ row: StatisticsBookRankingRow, maxValue: Double) -> some View {
        let value = bookRankingValue(row)
        return HStack(spacing: 12) {
            Text(row.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            GeometryReader { proxy in
                let width = max(proxy.size.width * CGFloat(value / maxValue), value > 0 ? 2 : 0)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.78))
                        .frame(width: width)
                }
            }
            .frame(height: 9)

            Text(bookRankingValueText(row))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 92, alignment: .trailing)
        }
        .frame(minHeight: 34)
        .help("\(row.title): \(bookRankingValueText(row))")
    }

    private var shelfComparisonHeader: some View {
        HStack(spacing: 10) {
            shelfHeaderColumn("Shelf", width: 160, alignment: .leading)
            shelfHeaderColumn("Books", width: 56, alignment: .trailing)
            shelfHeaderColumn("Total Characters", width: 112, alignment: .trailing)
            shelfHeaderColumn("Recorded Characters", width: 118, alignment: .trailing)
            shelfHeaderColumn("Duration", width: 82, alignment: .trailing)
            shelfHeaderColumn("Avg Speed", width: 92, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private func shelfComparisonRow(_ row: StatisticsShelfComparisonRow) -> some View {
        HStack(spacing: 10) {
            shelfValueColumn(row.name, width: 160, alignment: .leading)
            shelfValueColumn(formatCharacters(row.bookCount), width: 56, alignment: .trailing)
            shelfValueColumn(formatCharacters(row.totalCharacters), width: 112, alignment: .trailing)
            shelfValueColumn(formatCharacters(row.recordedCharacters), width: 118, alignment: .trailing)
            shelfValueColumn(formatDuration(row.readingTime), width: 82, alignment: .trailing)
            shelfValueColumn(formatOptionalSpeed(row.averageSpeedPerHour), width: 92, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }

    private func shelfHeaderColumn(
        _ text: LocalizedStringKey,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: width, alignment: alignment)
    }

    private func shelfValueColumn(
        _ text: String,
        width: CGFloat,
        alignment: Alignment
    ) -> some View {
        Text(text)
            .font(.callout.monospacedDigit())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: width, alignment: alignment)
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

    private func trendGrainText(_ grain: StatisticsTrendGrain) -> some View {
        switch grain {
        case .day:
            Text("Day")
        case .week:
            Text("Week")
        case .month:
            Text("Month")
        }
    }

    private func bookRankingMetricText(_ metric: StatisticsBookRankingMetric) -> some View {
        switch metric {
        case .characters:
            Text("Characters")
        case .duration:
            Text("Duration")
        case .speed:
            Text("Speed")
        }
    }

    private func textOfDailyTargetType(_ targetType: DailyTargetType) -> some View {
        switch targetType {
        case .characters:
            Text("Characters")
        case .duration:
            Text("Duration")
        }
    }

    private func trendMetricText(_ metric: StatisticsTrendMetric) -> some View {
        switch metric {
        case .characters:
            Text("Characters")
        case .duration:
            Text("Duration")
        case .speed:
            Text("Speed")
        }
    }

    private func trendChartStyleText(_ style: StatisticsTrendChartStyle) -> some View {
        switch style {
        case .bar:
            Image(systemName: "chart.bar.fill")
                .accessibilityLabel(Text("Bar"))
        case .line:
            Image(systemName: "chart.xyaxis.line")
                .accessibilityLabel(Text("Line"))
        }
    }

    private func trendBarChart(maxValue: Double, chartHeight: CGFloat, contentWidth: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(Array(trendPoints.enumerated()), id: \.element.id) { index, point in
                if let value = point.value(for: selectedTrendMetric) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.accentColor.gradient)
                        .frame(
                            width: trendBarWidth,
                            height: max(CGFloat(value / maxValue) * chartHeight, value > 0 ? 8 : 2)
                        )
                        .position(
                            x: trendXPosition(for: index, contentWidth: contentWidth),
                            y: chartHeight - max(CGFloat(value / maxValue) * chartHeight, value > 0 ? 8 : 2) / 2
                        )
                        .help(trendPointHelp(point, value: value))
                } else {
                    Text("-")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: trendBarWidth, height: 14)
                        .position(x: trendXPosition(for: index, contentWidth: contentWidth), y: chartHeight - 7)
                        .help(trendPointHelp(point, value: nil))
                }
            }
        }
        .frame(width: contentWidth, height: chartHeight, alignment: .bottomLeading)
    }

    private func trendLineChart(maxValue: Double, chartHeight: CGFloat, contentWidth: CGFloat) -> some View {
        let segments = trendLineSegments(maxValue: maxValue, chartHeight: chartHeight, contentWidth: contentWidth)
        let points = segments.flatMap { $0 }
        return ZStack(alignment: .topLeading) {
            ForEach(segments.indices, id: \.self) { index in
                Path { path in
                    for (pointIndex, point) in segments[index].enumerated() {
                        if pointIndex == 0 {
                            path.move(to: point.location)
                        } else {
                            path.addLine(to: point.location)
                        }
                    }
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            ForEach(points) { point in
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 7, height: 7)
                    .position(point.location)
                    .help(trendPointHelp(point.trendPoint, value: point.value))
            }
        }
        .frame(width: contentWidth, height: chartHeight, alignment: .topLeading)
    }

    private func trendLineSegments(maxValue: Double, chartHeight: CGFloat, contentWidth: CGFloat) -> [[StatisticsTrendLinePoint]] {
        var segments: [[StatisticsTrendLinePoint]] = []
        var current: [StatisticsTrendLinePoint] = []
        for (index, point) in trendPoints.enumerated() {
            guard let value = point.value(for: selectedTrendMetric) else {
                if !current.isEmpty {
                    segments.append(current)
                    current = []
                }
                continue
            }
            let x = trendXPosition(for: index, contentWidth: contentWidth)
            let y = chartHeight - CGFloat(value / maxValue) * chartHeight
            current.append(StatisticsTrendLinePoint(
                trendPoint: point,
                value: value,
                location: CGPoint(x: x, y: min(max(y, 3.5), chartHeight - 3.5))
            ))
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    private func trendXPosition(for index: Int, contentWidth: CGFloat) -> CGFloat {
        guard trendPoints.count > 1 else { return contentWidth / 2 }
        let usableWidth = max(contentWidth - trendBarWidth, 1)
        return trendBarWidth / 2 + CGFloat(index) * (usableWidth / CGFloat(trendPoints.count - 1))
    }

    private func trendPointHelp(_ point: StatisticsTrendPoint, value: Double?) -> String {
        "\(point.id): \(value.map(formatTrendValue) ?? "-") · \(formatCharacters(point.characters)), \(formatDuration(point.readingTime))"
    }

    private func bookRankingValue(_ row: StatisticsBookRankingRow) -> Double {
        switch selectedBookRankingMetric {
        case .characters:
            Double(row.characters)
        case .duration:
            row.readingTime
        case .speed:
            Double(row.averageSpeedPerHour ?? 0)
        }
    }

    private func bookRankingValueText(_ row: StatisticsBookRankingRow) -> String {
        switch selectedBookRankingMetric {
        case .characters:
            formatCharacters(row.characters)
        case .duration:
            formatDuration(row.readingTime)
        case .speed:
            formatOptionalSpeed(row.averageSpeedPerHour)
        }
    }

    private func shouldShowTrendLabel(at index: Int) -> Bool {
        guard trendPoints.count > 14 else { return true }
        let stride = max(Int(ceil(Double(trendPoints.count) / 12.0)), 1)
        return index.isMultiple(of: stride) || index == trendPoints.count - 1
    }

    private func formatCharacters(_ characters: Int) -> String {
        characters.formatted(.number.grouping(.automatic))
    }

    private func formatSpeed(_ speed: Int) -> String {
        String(format: String(localized: "%@/h"), speed.formatted(.number.grouping(.automatic)))
    }

    private func formatOptionalSpeed(_ speed: Int?) -> String {
        speed.map(formatSpeed) ?? "-"
    }

    private func formatSignedPercent(_ percent: Int?) -> String {
        guard let percent else { return "-" }
        if percent > 0 {
            return "+\(percent)%"
        }
        return "\(percent)%"
    }

    private func formatSpeedDay(_ day: StatisticsSpeedDay?) -> String {
        guard let day else { return "-" }
        return "\(monthDay(day.date)) · \(formatSpeed(day.speedPerHour))"
    }

    private func formatAxisCharacters(_ characters: Int) -> String {
        characters.formatted(.number.notation(.compactName))
    }

    private func formatAxisValue(_ value: Double) -> String {
        switch selectedTrendMetric {
        case .characters:
            return formatAxisCharacters(Int(value.rounded()))
        case .duration:
            return formatDuration(value)
        case .speed:
            return String(format: String(localized: "%@/h"), formatAxisCharacters(Int(value.rounded())))
        }
    }

    private func formatTrendValue(_ value: Double) -> String {
        switch selectedTrendMetric {
        case .characters:
            return formatCharacters(Int(value.rounded()))
        case .duration:
            return formatDuration(value)
        case .speed:
            return formatSpeed(Int(value.rounded()))
        }
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

    private func formattedFullDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.defaultDigits).day(.defaultDigits))
    }

    private func monthDay(_ date: Date) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 0)/\(components.day ?? 0)"
    }

    private func shortWeekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private func reloadSnapshot() {
        snapshotLoadGeneration += 1
        let generation = snapshotLoadGeneration
        let bookInputs = books.map {
            StatisticsBookSnapshotInput(
                id: $0.id,
                title: $0.displayTitle,
                cover: $0.cover,
                folder: $0.folder
            )
        }
        let calendar = calendar
        let booksDirectory = try? BookStorage.getBooksDirectory()
        isLoadingSnapshot = true

        DispatchQueue.global(qos: .userInitiated).async {
            let loadedSnapshot: StatisticsDashboardSnapshot
            if let booksDirectory {
                loadedSnapshot = StatisticsDashboardRepository.loadSnapshot(
                    bookInputs: bookInputs,
                    booksDirectory: booksDirectory,
                    calendar: calendar
                )
            } else {
                loadedSnapshot = StatisticsDashboardSnapshot(days: [])
            }

            DispatchQueue.main.async {
                guard snapshotLoadGeneration == generation else { return }
                applySnapshot(loadedSnapshot)
                isLoadingSnapshot = false
            }
        }
    }

    private func applySnapshot(_ loadedSnapshot: StatisticsDashboardSnapshot) {
        snapshot = loadedSnapshot
        if selectedAnchor == nil {
            selectedAnchor = snapshot.days.last?.date ?? today
        }
        let latestDate = snapshot.days.last?.date ?? today
        if !hasUserSelectedCalendarDate {
            selectedCalendarDate = latestDate
        } else if let selectedCalendarDate {
            self.selectedCalendarDate = windowRange.coerce(selectedCalendarDate, calendar: calendar)
        }
    }

    private func scrollHeatmap(to date: Date, with proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(calendar.startOfDay(for: date), anchor: .trailing)
            }
        }
    }

    private func chartYAxis(maxValue: Double, height: CGFloat) -> some View {
        VStack(alignment: .trailing) {
            Text(formatAxisValue(maxValue))
            Spacer()
            Text(formatAxisValue(maxValue / 2))
            Spacer()
            Text("0")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 54, height: height, alignment: .trailing)
    }

    private func chartGridLines(height: CGFloat) -> some View {
        VStack {
            ForEach(0..<3, id: \.self) { index in
                Rectangle()
                    .fill(Color.secondary.opacity(index == 2 ? 0.22 : 0.12))
                    .frame(height: 1)
                if index != 2 {
                    Spacer()
                }
            }
        }
        .frame(height: height)
    }
}

private enum StatisticsDashboardPlaceholder {
    private static let activityOffsets = [330, 304, 278, 251, 226, 203, 181, 158, 137, 116, 96, 77, 59, 42, 28, 17, 9, 4, 1, 0]
    private static let fallbackBookIDs: [UUID] = (1...statisticsBookRankingLimit).compactMap {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))
    }

    static func snapshot(
        books: [BookMetadata],
        windowRange: StatisticsDateRange,
        today: Date,
        calendar: Calendar
    ) -> StatisticsDashboardSnapshot {
        let records = placeholderRecords(from: books)
        let activeRecords = Array(records.prefix(min(records.count, 6)))
        let days = activityOffsets.enumerated().compactMap { index, offset -> StatisticsDayAggregate? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today)
                    .map(calendar.startOfDay(for:)),
                  windowRange.contains(date, calendar: calendar),
                  !activeRecords.isEmpty else {
                return nil
            }

            let totalCharacters = 2_400 + ((index * 3_371) % 18_000)
            let speed = 7_200 + (index % 5) * 1_150
            let readingTime = Double(totalCharacters) / Double(speed) * 3_600
            let primary = activeRecords[index % activeRecords.count]
            let secondary = activeRecords[(index + 1) % activeRecords.count]
            let primaryCharacters = activeRecords.count > 1 && !index.isMultiple(of: 4)
                ? Int(Double(totalCharacters) * 0.66)
                : totalCharacters
            let primaryTime = readingTime * (Double(primaryCharacters) / Double(totalCharacters))
            var contributions = [
                contribution(
                    record: primary,
                    characters: primaryCharacters,
                    readingTime: primaryTime
                )
            ]

            if secondary.id != primary.id, primaryCharacters < totalCharacters {
                contributions.append(
                    contribution(
                        record: secondary,
                        characters: totalCharacters - primaryCharacters,
                        readingTime: readingTime - primaryTime
                    )
                )
            }

            return StatisticsDayAggregate(
                date: date,
                characters: contributions.reduce(0) { $0 + $1.characters },
                readingTime: contributions.reduce(0) { $0 + $1.readingTime },
                bookContributions: contributions
            )
        }
        .sorted { $0.date < $1.date }

        return StatisticsDashboardSnapshot(days: days, books: records)
    }

    private static func placeholderRecords(from books: [BookMetadata]) -> [StatisticsBookRecord] {
        var usedIDs = Set<UUID>()
        var records = books.prefix(statisticsBookRankingLimit).enumerated().map { index, book in
            usedIDs.insert(book.id)
            return StatisticsBookRecord(
                id: book.id,
                title: book.displayTitle,
                coverPath: nil,
                totalCharacters: 80_000 + index * 23_000
            )
        }

        for (index, id) in fallbackBookIDs.enumerated() where records.count < statisticsBookRankingLimit && !usedIDs.contains(id) {
            records.append(
                StatisticsBookRecord(
                    id: id,
                    title: String(localized: "Loading Statistics"),
                    coverPath: nil,
                    totalCharacters: 70_000 + index * 19_000
                )
            )
        }

        return records
    }

    private static func contribution(
        record: StatisticsBookRecord,
        characters: Int,
        readingTime: Double
    ) -> StatisticsBookContribution {
        StatisticsBookContribution(
            bookID: record.id,
            title: record.title,
            coverPath: record.coverPath,
            characters: characters,
            readingTime: readingTime
        )
    }
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

private struct StatisticsTrendLinePoint: Identifiable {
    let trendPoint: StatisticsTrendPoint
    let value: Double
    let location: CGPoint

    var id: String { trendPoint.id }
}

private struct NativeSettingsStepperRow: View {
    let title: LocalizedStringKey
    let value: String
    let range: ClosedRange<Int>
    let step: Int
    @Binding var selection: Int

    var body: some View {
        NativeSettingsRow(title) {
            Text(verbatim: value)
                .fontWeight(.semibold)
                .monospacedDigit()
            Stepper(value: clampedSelection, in: range, step: step) {
                Text(title)
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private var clampedSelection: Binding<Int> {
        Binding {
            min(max(selection, range.lowerBound), range.upperBound)
        } set: { newValue in
            selection = min(max(newValue, range.lowerBound), range.upperBound)
        }
    }
}
