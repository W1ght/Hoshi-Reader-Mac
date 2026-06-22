#if HOSHI_VIDEO
import SwiftUI

struct SubtitleTranscriptView: View {
    let transcript: SubtitleTranscript
    let currentTime: TimeInterval
    let isLoading: Bool
    let errorMessage: String?
    var onSeek: (TimeInterval) -> Void

    @State private var rowWindow = SubtitleTranscriptWindow()
    @State private var focusedRowID: String?

    var body: some View {
        VStack(spacing: 0) {
            if transcript.rows.isEmpty {
                emptyState
            } else {
                transcriptRows
            }
        }
        .onAppear {
            resetWindowForCurrentTime()
        }
        .onChange(of: transcript.changeToken) { _, _ in
            resetWindowForCurrentTime()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Group {
            if isLoading {
                ContentUnavailableView {
                    Label("Loading Transcript", systemImage: "captions.bubble")
                } description: {
                    Text("Reading the selected subtitle track…")
                } actions: {
                    ProgressView()
                        .controlSize(.small)
                }
            } else if let errorMessage {
                ContentUnavailableView(
                    "Transcript Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ContentUnavailableView(
                    "No Transcript",
                    systemImage: "captions.bubble",
                    description: Text("Load subtitles to view the transcript.")
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private var transcriptRows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(transcript.rows(in: rowWindow.visibleRange).enumerated()), id: \.element.id) { offset, row in
                        transcriptRow(row)
                            .id(row.id)
                            .onAppear {
                                extendWindowIfNeeded(forVisibleOffset: offset)
                            }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: currentTime) { _, time in
                guard let rowIndex = transcript.nearestRowIndex(at: time) else { return }
                let previousRange = rowWindow.visibleRange
                rowWindow.followPlayback(
                    rowCount: transcript.rows.count,
                    focusing: rowIndex
                )
                let row = transcript.rows[rowIndex]
                guard row.id != focusedRowID || rowWindow.visibleRange != previousRange else {
                    return
                }
                focusedRowID = row.id
                withAnimation(.smooth(duration: 0.18)) {
                    proxy.scrollTo(row.id, anchor: .center)
                }
            }
        }
    }

    private func transcriptRow(_ row: SubtitleTranscriptRow) -> some View {
        let isCurrent = row.startTime <= currentTime && currentTime <= row.endTime
        return VideoStudyListCard(isSelected: isCurrent) {
            onSeek(row.startTime)
        } content: {
            VStack(alignment: .leading, spacing: 5) {
                Text(VideoTimeFormatter.string(from: row.startTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isCurrent ? .primary : .secondary)

                Text(row.primaryText)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                if let secondaryText = row.secondaryText,
                   !secondaryText.isEmpty {
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resetWindowForCurrentTime() {
        guard let index = transcript.nearestRowIndex(at: currentTime) else {
            rowWindow.reset(rowCount: 0, focusing: 0)
            focusedRowID = nil
            return
        }
        rowWindow.reset(rowCount: transcript.rows.count, focusing: index)
        focusedRowID = transcript.rows[index].id
    }

    private func extendWindowIfNeeded(forVisibleOffset offset: Int) {
        let absoluteIndex = rowWindow.visibleRange.lowerBound + offset
        if absoluteIndex <= rowWindow.visibleRange.lowerBound + 4 {
            rowWindow.extendBefore(rowCount: transcript.rows.count)
        }
        if absoluteIndex >= rowWindow.visibleRange.upperBound - 5 {
            rowWindow.extendAfter(rowCount: transcript.rows.count)
        }
    }
}
#endif
