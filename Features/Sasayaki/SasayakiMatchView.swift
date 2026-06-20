//
//  SasayakiMatchView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UniformTypeIdentifiers

private enum SasayakiMatchLayout {
    static let sheetWidth: CGFloat = 680
    static let sheetHeight: CGFloat = 620
}

struct SasayakiMatchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let book: BookMetadata
    var viewModel: BookshelfViewModel

    @State private var isImporting = false
    @State private var fileURL: URL?
    @State private var searchWindow: Double = 200
    @State private var isMatching = false
    @State private var match: SasayakiMatchData?

    var body: some View {
        VStack(spacing: 0) {
            matchHeader

            NativeSettingsForm(
                horizontalPadding: 26,
                verticalPadding: 12,
                spacing: 24
            ) {
                fileSection
                searchSection

                if let match {
                    currentMatchSection(match)
                }
            }
        }
        .frame(
            width: SasayakiMatchLayout.sheetWidth,
            height: SasayakiMatchLayout.sheetHeight
        )
        .background(NativeSettingsPalette.pageBackground(colorScheme))
        .onAppear {
            match = viewModel.loadSasayakiMatch(book: book)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "srt")!]
        ) { result in
            if case .success(let url) = result {
                fileURL = url
            }
        }
    }

    private var matchHeader: some View {
        ZStack {
            Text("Match")
                .font(.title3.weight(.semibold))

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var fileSection: some View {
        NativeSettingsSectionCard("File") {
            NativeSettingsRow {
                fileNameView
            } accessory: {
                Button("Open") {
                    isImporting = true
                }
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
        guard let fileURL else {
            return
        }

        isMatching = true
        Task { @MainActor in
            defer { isMatching = false }
            match = try? await viewModel.runSasayakiMatch(
                book: book,
                srtURL: fileURL,
                searchWindow: Int(searchWindow)
            )
        }
    }

    @ViewBuilder
    private var fileNameView: some View {
        if fileURL?.lastPathComponent == nil {
            Text("No file selected")
                .lineLimit(1)
        } else {
            Text(fileURL!.lastPathComponent)
                .lineLimit(1)
        }
    }
}
