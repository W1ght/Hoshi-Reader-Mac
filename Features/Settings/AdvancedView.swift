//
//  AdvancedView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AdvancedView: View {
    var body: some View {
        List {
            Section {
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

                #if HOSHI_VIDEO
                NavigationLink {
                    VideoSettingsView()
                } label: {
                    Label("Video", systemImage: "play.rectangle")
                }
                .foregroundStyle(.primary)
                #endif

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
            
            Section {
                NavigationLink {
                    SyncView()
                } label: {
                    Label("ッツ Sync", systemImage: "cloud")
                }
                .foregroundStyle(.primary)
            }
            
            Section {
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
