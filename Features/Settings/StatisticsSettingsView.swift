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

}
