//
//  SasayakiMatchView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct SasayakiSubtitleMatchSection: View {
    let rootURL: URL
    @Binding var fileURL: URL?
    let onImportRequested: () -> Void
    let onMatchUpdated: (SasayakiMatchData) -> Void

    @State private var searchWindow: Double = 200
    @State private var isMatching = false
    @State private var match: SasayakiMatchData?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            fileSection
            searchSection

            if let match {
                currentMatchSection(match)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }
        }
        .onAppear {
            match = BookStorage.loadSasayakiMatch(root: rootURL)
        }
        .onChange(of: fileURL) { _, newURL in
            if newURL != nil {
                errorMessage = nil
            }
        }
    }

    private var fileSection: some View {
        NativeSettingsSectionCard("Subtitle Match") {
            NativeSettingsRow {
                fileNameView
            } accessory: {
                Button("Open") {
                    onImportRequested()
                }
                .buttonStyle(NativeSettingsActionButtonStyle())
            }
        }
    }

    private var searchSection: some View {
        NativeSettingsSectionCard {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                NativeSettingsRow {
                    Text("Search Window")
                } accessory: {
                    Text("\(Int(searchWindow))")
                        .fontWeight(.semibold)
                }

                Slider(value: $searchWindow, in: 50...1000, step: 50)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                NativeSettingsSeparator()

                NativeSettingsButtonRow {
                    Button(action: matchFile) {
                        matchButtonLabel
                    }
                    .disabled(fileURL == nil || isMatching)
                }
            }
        }
    }

    private func currentMatchSection(_ match: SasayakiMatchData) -> some View {
        NativeSettingsSectionCard("Current Match") {
            NativeSettingsRow("Match Rate") {
                Text(matchRate(for: match))
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var matchButtonLabel: some View {
        if isMatching {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Matching…")
            }
        } else {
            Text("Match")
        }
    }

    private func matchRate(for matchData: SasayakiMatchData) -> String {
        let matched = matchData.matches.count
        let total = matched + matchData.unmatched
        let percentage = total > 0 ? (Double(matched) / Double(total)) * 100 : 0
        return "\(matched)/\(total) (\(String(format: "%.1f%%", percentage)))"
    }

    private func matchFile() {
        guard let fileURL else { return }

        isMatching = true
        errorMessage = nil
        Task { @MainActor in
            defer { isMatching = false }
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let srtData = try Data(contentsOf: fileURL)
                let cues = SasayakiParser.parseCues(from: srtData)
                let result = try SasayakiMatcher.match(
                    rootURL: rootURL,
                    cues: cues,
                    searchWindow: Int(searchWindow)
                )
                try BookStorage.save(result, inside: rootURL, as: FileNames.sasayakiMatch)
                match = result
                onMatchUpdated(result)
            } catch {
                errorMessage = String(localized: "Could not match subtitles.")
            }
        }
    }

    @ViewBuilder
    private var fileNameView: some View {
        if let fileName = fileURL?.lastPathComponent {
            Text(fileName)
                .lineLimit(1)
        } else {
            Text("No file selected")
                .lineLimit(1)
        }
    }
}
