#if HOSHI_VIDEO
import SwiftUI

struct SubtitleTranscriptView: View {
    let transcript: SubtitleTranscript
    let currentTime: TimeInterval
    var onSeek: (TimeInterval) -> Void
    var onClose: () -> Void

    @State private var rowWindow = SubtitleTranscriptWindow()
    @State private var focusedRowID: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            if transcript.rows.isEmpty {
                emptyState
            } else {
                transcriptRows
            }
        }
        .frame(minWidth: 300, idealWidth: 350, maxWidth: 420)
        .modifier(VideoTranscriptGlassSurface(cornerRadius: 24))
        .onAppear {
            resetWindowForCurrentTime()
        }
        .onChange(of: transcript.changeToken) { _, _ in
            resetWindowForCurrentTime()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Transcript", systemImage: "text.alignleft")
                .font(.headline)
                .labelStyle(.titleAndIcon)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close Transcript")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Transcript",
            systemImage: "captions.bubble",
            description: Text("Load subtitles to view the transcript.")
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private var transcriptRows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
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
        return Button {
            onSeek(row.startTime)
        } label: {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCurrent ? Color.accentColor.opacity(0.16) : Color.clear)
            }
        }
        .buttonStyle(.plain)
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

private struct VideoTranscriptGlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}
#endif
