//
//  StatisticsView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import EPUBKit


struct ReaderStatisticsContentView: View {
    let sessionStatistics: Statistics
    let todaysStatistics: Statistics
    let allTimeStatistics: Statistics
    let bookCharacterCount: Int
    let currentCharacter: Int
    let currentChapterCount: Int
    let contentLanguage: ContentLanguageProfile
    let isTracking: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onClose: () -> Void

    var body: some View {
        NativeReaderSheetPanel("Statistics", onClose: onClose) {
            List {
                Section {
                    statisticRow(countLabel, value: contentLanguage.displayCount(forRawCharacters: sessionStatistics.charactersRead).formatted(.number.grouping(.never)))
                    statisticRow("Reading Speed:", value: "\(contentLanguage.displayCount(forRawCharacters: sessionStatistics.lastReadingSpeed).formatted(.number.grouping(.never))) / h")
                    statisticRow("Reading Time:", value: Duration.seconds(sessionStatistics.readingTime).formatted())
                    statisticRow("Time to finish Book:", value: Duration.seconds(timeToFinishBook).formatted())
                    statisticRow("Time to finish Chapter:", value: Duration.seconds(timeToFinishChapter).formatted())
                } header: {
                    HStack {
                        Text("Session")
                        if !isTracking {
                            Button {
                                onStart()
                            } label: {
                                Image(systemName: "play.fill")
                            }
                            .foregroundStyle(.primary)
                        } else {
                            Button {
                                onStop()
                            } label: {
                                Image(systemName: "pause.fill")
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                
                Section {
                    statisticRow(countLabel, value: contentLanguage.displayCount(forRawCharacters: todaysStatistics.charactersRead).formatted(.number.grouping(.never)))
                    statisticRow("Reading Speed:", value: "\(contentLanguage.displayCount(forRawCharacters: todaysStatistics.lastReadingSpeed).formatted(.number.grouping(.never))) / h")
                    statisticRow("Reading Time:", value: Duration.seconds(todaysStatistics.readingTime).formatted())
                } header: {
                    Text("Today")
                }
                
                Section {
                    statisticRow(countLabel, value: contentLanguage.displayCount(forRawCharacters: allTimeStatistics.charactersRead).formatted(.number.grouping(.never)))
                    statisticRow("Reading Speed:", value: "\(contentLanguage.displayCount(forRawCharacters: allTimeStatistics.lastReadingSpeed).formatted(.number.grouping(.never))) / h")
                    statisticRow("Reading Time:", value: Duration.seconds(allTimeStatistics.readingTime).formatted())
                } header: {
                    Text("All Time")
                }
            }
            .monospacedDigit()
            .scrollContentBackground(.hidden)
        }
    }

    private var countLabel: LocalizedStringKey {
        contentLanguage == .english ? "Approximate Words Read:" : "Characters Read:"
    }

    private var timeToFinishBook: Double {
        guard sessionStatistics.lastReadingSpeed > 0 else { return 0 }
        return Double(max(bookCharacterCount - currentCharacter, 0)) / (Double(sessionStatistics.lastReadingSpeed) / 3600.0)
    }

    private var timeToFinishChapter: Double {
        guard sessionStatistics.lastReadingSpeed > 0 else { return 0 }
        return Double(max(currentChapterCount - currentCharacter, 0)) / (Double(sessionStatistics.lastReadingSpeed) / 3600.0)
    }

    private func statisticRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("**\(value)**")
        }
    }
}
