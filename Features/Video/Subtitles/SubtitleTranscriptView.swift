#if HOSHI_VIDEO
import SwiftUI

struct SubtitleTranscriptView: View {
    let transcript: SubtitleTranscript
    let currentTime: TimeInterval
    let pendingABLoopStart: TimeInterval?
    let abLoop: VideoABLoop?
    let isLoading: Bool
    let errorMessage: String?
    var onSeek: (TimeInterval) -> Void
    var onSetABLoopStart: (TimeInterval) -> Void
    var onSetABLoopEnd: (TimeInterval) -> Void

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
                followPlayback(time, using: proxy)
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
        } accessories: {
            HStack(spacing: 5) {
                abLoopMarkerButton("A", isActive: isABLoopStart(row)) {
                    onSetABLoopStart(row.startTime)
                }
                abLoopMarkerButton("B", isActive: isABLoopEnd(row)) {
                    onSetABLoopEnd(row.endTime)
                }
                .disabled(!canSetABLoopEnd)
            }
        }
    }

    private var canSetABLoopEnd: Bool {
        pendingABLoopStart != nil || abLoop != nil
    }

    private func isABLoopStart(_ row: SubtitleTranscriptRow) -> Bool {
        guard let start = pendingABLoopStart ?? abLoop?.start else { return false }
        return rowContains(row, time: start)
    }

    private func isABLoopEnd(_ row: SubtitleTranscriptRow) -> Bool {
        guard let end = abLoop?.end, pendingABLoopStart == nil else { return false }
        return rowContains(row, time: end)
    }

    private func rowContains(_ row: SubtitleTranscriptRow, time: TimeInterval) -> Bool {
        row.startTime <= time && time <= row.endTime
    }

    private func abLoopMarkerButton(
        _ label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(isActive ? Color.white : Color.secondary)
                .frame(width: 22, height: 22)
                .background {
                    Circle()
                        .fill(isActive ? Color.accentColor : Color.primary.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
        .help(label == "A" ? "Set A Point" : "Set B Point")
        .accessibilityLabel(Text(label == "A" ? "Set A Point" : "Set B Point"))
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

    private func followPlayback(
        _ time: TimeInterval,
        using proxy: ScrollViewProxy
    ) {
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
        proxy.scrollTo(row.id, anchor: .center)
    }

    private var currentRowID: String? {
        transcript.nearestRowIndex(at: currentTime).map { transcript.rows[$0].id }
    }
}

extension SubtitleTranscriptView: Equatable {
    static func == (lhs: SubtitleTranscriptView, rhs: SubtitleTranscriptView) -> Bool {
        lhs.transcript.changeToken == rhs.transcript.changeToken
            && lhs.currentRowID == rhs.currentRowID
            && lhs.pendingABLoopStart == rhs.pendingABLoopStart
            && lhs.abLoop == rhs.abLoop
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
    }
}
#endif
