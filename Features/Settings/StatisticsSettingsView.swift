//
//  StatisticsSettingsView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct StatisticsSettingsView: View {
    @Environment(UserConfig.self) var userConfig
    var body: some View {
        @Bindable var userConfig = userConfig
        NativeSettingsForm {
            NativeSettingsSectionCard {
                Text("Statistics")
            } content: {
                NativeSettingsToggle("Enable", isOn: $userConfig.enableStatistics)
            } footer: {
                Text("Statistics appears in Bookshelf when enabled.")
            }

            if userConfig.enableStatistics {
                NativeSettingsSectionCard("Daily Goal") {
                    NativeSettingsRow("Goal Type") {
                        NativeGlassSegmentedPicker(
                            selection: $userConfig.dailyStatisticsTargetType,
                            values: DailyTargetType.allCases,
                            minSegmentWidth: 88
                        ) { targetType in
                            textOfDailyTargetType(targetType)
                        }
                    }
                    NativeSettingsSeparator()
                    switch userConfig.dailyStatisticsTargetType {
                    case .characters:
                        NativeSettingsStepperRow(
                            title: "Character Target",
                            value: "\(userConfig.dailyStatisticsCharacterTarget.formatted(.number.grouping(.automatic)))",
                            range: StatisticsTargetSettings.characterTargetRange,
                            step: StatisticsTargetSettings.characterTargetStep,
                            selection: $userConfig.dailyStatisticsCharacterTarget
                        )
                    case .duration:
                        NativeSettingsStepperRow(
                            title: "Duration Target",
                            value: Duration.seconds(Double(userConfig.dailyStatisticsDurationTargetMinutes * 60)).formatted(.time(pattern: .hourMinute)),
                            range: StatisticsTargetSettings.durationTargetMinutesRange,
                            step: StatisticsTargetSettings.durationTargetMinutesStep,
                            selection: $userConfig.dailyStatisticsDurationTargetMinutes
                        )
                    }
                } footer: {
                    Text("The dashboard uses this daily goal to calculate progress and streaks.")
                }

                NativeSettingsSectionCard("Weekly Goal") {
                    NativeSettingsStepperRow(
                        title: "Target Days",
                        value: "\(userConfig.weeklyStatisticsTargetDays)",
                        range: StatisticsTargetSettings.weeklyTargetDaysRange,
                        step: 1,
                        selection: $userConfig.weeklyStatisticsTargetDays
                    )
                } footer: {
                    Text("A week is complete when this many days meet the daily goal.")
                }

                NativeSettingsSectionCard("Autostart") {
                    NativeSettingsRow("Autostart") {
                        NativeGlassSegmentedPicker(
                            selection: $userConfig.statisticsAutostartMode,
                            values: StatisticsAutostartMode.allCases,
                            minSegmentWidth: 72
                        ) { mode in
                            textOfAutoRestartMode(mode)
                        }
                    }
                }

                if userConfig.enableSync {
                    NativeSettingsSectionCard {
                        Text("Sync")
                    } content: {
                        NativeSettingsToggle("ッツ Sync", isOn: $userConfig.statisticsEnableSync)
                        NativeSettingsSeparator()
                        NativeSettingsRow("Sync Behaviour") {
                            NativeGlassSegmentedPicker(
                                selection: $userConfig.statisticsSyncMode,
                                values: StatisticsSyncMode.allCases,
                                minSegmentWidth: 72
                            ) { mode in
                                textOfAutoSyncMode(mode)
                            }
                        }
                    } footer: {
                        Text("Determines if statistics will be merged entry by entry or replaced completely on a sync.")
                    }
                }
            }
        }
        .navigationTitle("Statistics")
    }

    private func textOfAutoRestartMode(_ mode: StatisticsAutostartMode) -> some View {
        switch mode {
        case .off:
            Text("Off")
        case .pageturn:
            Text("Page Turn")
        case .on:
            Text("On")
        }
    }

    private func textOfAutoSyncMode(_ mode: StatisticsSyncMode) -> some View {
        switch mode {
        case .merge:
            Text("Merge")
        case .replace:
            Text("Replace")
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
