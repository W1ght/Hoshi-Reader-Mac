//
//  AdvancedView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AdvancedView: View {
    var body: some View {
        List {
            Section("Reader") {
                NavigationLink {
                    AudioView()
                } label: {
                    Label("Audio", systemImage: "speaker.wave.2")
                }
                .foregroundStyle(.primary)
                
                NavigationLink {
                    StatisticsSettingsView()
                } label: {
                    Label("Statistics", systemImage: "chart.xyaxis.line")
                }
                .foregroundStyle(.primary)
                
                NavigationLink {
                    SasayakiSettingsView()
                } label: {
                    Label("Sasayaki (Audiobooks)", systemImage: "waveform")
                }
                .foregroundStyle(.primary)
            }

            Section("Video") {
                NavigationLink {
                    VideoSettingsView()
                } label: {
                    Label("Video", systemImage: "play.rectangle")
                }
                .foregroundStyle(.primary)
            }

            Section("Shortcuts & Controls") {
                NavigationLink {
                    KeyboardShortcutsView()
                } label: {
                    Label("Keyboard Shortcuts", systemImage: "keyboard")
                }
                .foregroundStyle(.primary)

                NavigationLink {
                    XboxControllerView()
                } label: {
                    Label("Game Controller", systemImage: "gamecontroller")
                }
                .foregroundStyle(.primary)
            }

            Section("Sync & Data") {
                NavigationLink {
                    SyncView()
                } label: {
                    Label("ッツ Sync", systemImage: "cloud")
                }
                .foregroundStyle(.primary)

                NavigationLink {
                    BackupView()
                } label: {
                    Label("Backup", systemImage: "externaldrive")
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Advanced")
    }
}
