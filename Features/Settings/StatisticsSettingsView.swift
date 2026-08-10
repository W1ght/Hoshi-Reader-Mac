//
//  StatisticsSettingsView.swift
//  Niratan
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

                NativeSettingsSectionCard("Daily Reset") {
                    NativeSettingsRow("Reset Time") {
                        DatePicker(
                            "",
                            selection: resetTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }
                } footer: {
                    Text("Reading statistics recorded before this time count toward the previous day.")
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

    private var resetTimeBinding: Binding<Date> {
        Binding {
            let resetMinutes = StatisticsDayBoundary.normalizedResetMinutes(
                userConfig.statisticsResetTime
            )
            var components = DateComponents()
            components.calendar = Calendar.current
            components.timeZone = Calendar.current.timeZone
            components.year = 2001
            components.month = 1
            components.day = 1
            components.hour = resetMinutes / 60
            components.minute = resetMinutes % 60
            return components.date ?? Date(timeIntervalSinceReferenceDate: 0)
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            userConfig.statisticsResetTime = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
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

}
