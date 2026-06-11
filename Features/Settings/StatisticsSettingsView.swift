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
        #if os(macOS) && !targetEnvironment(macCatalyst)
        NativeSettingsForm {
            NativeSettingsSectionCard {
                Text("Statistics")
            } content: {
                NativeSettingsToggle("Enable", isOn: $userConfig.enableStatistics)
            } footer: {
                Text("Statistics can be accessed from the Reader's context menu.")
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
        #else
        List {
            Section {
                Toggle("Enable", isOn: $userConfig.enableStatistics)
            } footer: {
                Text("Statistics can be accessed from the Reader's context menu.")
            }

            if userConfig.enableStatistics {
                Section {
                    #if os(macOS) && !targetEnvironment(macCatalyst)
                    HStack {
                        Text("Autostart")
                        Spacer()
                        NativeGlassSegmentedPicker(
                            selection: $userConfig.statisticsAutostartMode,
                            values: StatisticsAutostartMode.allCases,
                            minSegmentWidth: 72
                        ) { mode in
                            textOfAutoRestartMode(mode)
                        }
                    }
                    #else
                    Picker("Autostart", selection: $userConfig.statisticsAutostartMode) {
                        ForEach(StatisticsAutostartMode.allCases, id: \.self) { mode in
                            textOfAutoRestartMode(mode).tag(mode)
                        }
                    }
                    #endif
                }

                if userConfig.enableSync {
                    Section {
                        Toggle("ッツ Sync", isOn: $userConfig.statisticsEnableSync)
                        #if os(macOS) && !targetEnvironment(macCatalyst)
                        HStack {
                            Text("Sync Behaviour")
                            Spacer()
                            NativeGlassSegmentedPicker(
                                selection: $userConfig.statisticsSyncMode,
                                values: StatisticsSyncMode.allCases,
                                minSegmentWidth: 72
                            ) { mode in
                                textOfAutoSyncMode(mode)
                            }
                        }
                        #else
                        Picker("Sync Behaviour", selection: $userConfig.statisticsSyncMode) {
                            ForEach(StatisticsSyncMode.allCases, id: \.self) { mode in
                                textOfAutoSyncMode(mode).tag(mode)
                            }
                        }
                        #endif
                    } header: {
                        Text("Sync")
                    } footer: {
                        Text("Determines if statistics will be merged entry by entry or replaced completely on a sync.")
                    }
                }
            }
        }
        .navigationTitle("Statistics")
        #endif
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
