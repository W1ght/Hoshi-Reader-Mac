//
//  SettingsHomeView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct SettingsHomeView: View {
    @Environment(UserConfig.self) private var userConfig

    var body: some View {
        List {
            NavigationLink {
                DictionaryView()
            } label: {
                Label("Dictionaries", systemImage: "character.book.closed.ja")
            }
            .foregroundStyle(.primary)

            NavigationLink {
                AnkiView()
            } label: {
                Label("Anki", systemImage: "tray.full")
            }
            .foregroundStyle(.primary)

            NavigationLink {
                AppearanceView(userConfig: userConfig, showDismiss: false)
            } label: {
                Label("Appearance", systemImage: "paintpalette")
            }
            .foregroundStyle(.primary)

            NavigationLink {
                AdvancedView()
            } label: {
                Label("Advanced", systemImage: "gearshape.2")
            }
            .foregroundStyle(.primary)

            Section {
                Link(destination: URL(string: "https://github.com/W1ght/Hoshi-Reader-for-Mac/issues")!) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }

                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Settings")
    }
}
