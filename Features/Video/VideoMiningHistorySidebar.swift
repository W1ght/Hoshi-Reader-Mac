#if HOSHI_VIDEO
import AppKit
import SwiftUI

enum VideoStudySidebarTab: String, CaseIterable, Identifiable {
    case history
    case transcript
    case chapters

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .history: "Mining History"
        case .transcript: "Transcript"
        case .chapters: "Chapters"
        }
    }

    var systemName: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .transcript: "text.alignleft"
        case .chapters: "list.bullet.rectangle"
        }
    }
}

struct VideoMiningHistorySidebar: View {
    static let minWidth: CGFloat = 320
    static let defaultWidth: CGFloat = 340
    static let maxWidth: CGFloat = 560

    @Binding var selectedTab: VideoStudySidebarTab
    let items: [VideoMiningHistoryItem]
    let transcript: SubtitleTranscript
    let chapters: [VideoChapter]
    let currentTime: TimeInterval
    let pendingABLoopStart: TimeInterval?
    let abLoop: VideoABLoop?
    let isTranscriptLoading: Bool
    let transcriptErrorMessage: String?
    let canAlignPreviousSubtitle: Bool
    let canAlignNextSubtitle: Bool
    var onClose: () -> Void
    var onJump: (VideoMiningHistoryItem) -> Void
    var onSeekTranscript: (TimeInterval) -> Void
    var onSetTranscriptABLoopStart: (TimeInterval) -> Void
    var onSetTranscriptABLoopEnd: (TimeInterval) -> Void
    var onAlignPreviousSubtitle: () -> Void
    var onAlignNextSubtitle: () -> Void
    var onSeekChapter: (Int) -> Void
    var onCopy: (VideoMiningHistoryItem) -> Void
    var onDelete: (String) -> Void
    var onClear: () -> Void

    @State private var isLatestItemVisible = true
    @State private var isConfirmingClear = false

    private struct HistorySection: Identifiable {
        let id: String
        let sourceName: String
        var items: [VideoMiningHistoryItem]
    }

    private var sections: [HistorySection] {
        var result: [HistorySection] = []
        for item in items {
            if result.last?.sourceName == item.subtitleSourceName {
                result[result.count - 1].items.append(item)
            } else {
                result.append(
                    HistorySection(
                        id: "\(item.subtitleSourceName)-\(result.count)",
                        sourceName: item.subtitleSourceName,
                        items: [item]
                    )
                )
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabPicker

            if selectedTab == .transcript {
                subtitleAlignmentControls
            }

            Divider()
                .opacity(0.5)

            switch selectedTab {
            case .history:
                if items.isEmpty {
                    emptyState
                } else {
                    historyList

                    Divider()
                        .opacity(0.5)

                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Label("Clear Mining History", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VideoMiningHistoryButtonStyle())
                    .padding(14)
                }
            case .transcript:
                SubtitleTranscriptView(
                    transcript: transcript,
                    currentTime: currentTime,
                    pendingABLoopStart: pendingABLoopStart,
                    abLoop: abLoop,
                    isLoading: isTranscriptLoading,
                    errorMessage: transcriptErrorMessage,
                    onSeek: onSeekTranscript,
                    onSetABLoopStart: onSetTranscriptABLoopStart,
                    onSetABLoopEnd: onSetTranscriptABLoopEnd
                )
                .equatable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .chapters:
                if chapters.isEmpty {
                    chapterEmptyState
                } else {
                    chapterList
                }
            }
        }
        .frame(minWidth: Self.minWidth, idealWidth: Self.defaultWidth, maxWidth: .infinity)
        .background {
            VideoStudySidebarBackground()
        }
        .overlay(alignment: .leading) {
            Divider()
        }
        .confirmationDialog(
            "Clear Mining History?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear Mining History", role: .destructive, action: onClear)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved subtitle from Mining History.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(selectedTab.title, systemImage: selectedTab.systemName)
                .font(.headline)
                .labelStyle(.titleAndIcon)

            Spacer()

            if selectedTab != .transcript {
                Text("\(selectedTab == .history ? items.count : chapters.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(VideoMiningHistoryIconButtonStyle())
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var tabPicker: some View {
        NativeGlassSegmentedPicker(
            selection: $selectedTab,
            values: VideoStudySidebarTab.allCases,
            minSegmentWidth: 88,
            fillsWidth: true
        ) { tab in
            Label(tab.title, systemImage: tab.systemName)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var subtitleAlignmentControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Align Subtitle to Current Time")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(action: onAlignPreviousSubtitle) {
                    Label("Previous", systemImage: "arrow.left.to.line")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canAlignPreviousSubtitle)
                .help("Align Previous Subtitle to Current Time")

                Button(action: onAlignNextSubtitle) {
                    Label("Next", systemImage: "arrow.right.to.line")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canAlignNextSubtitle)
                .help("Align Next Subtitle to Current Time")
            }
            .buttonStyle(VideoMiningHistoryButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Mining History Empty", systemImage: "tray")
        } description: {
            Text("Mined video subtitles will appear here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var chapterEmptyState: some View {
        ContentUnavailableView {
            Label("No Chapters", systemImage: "list.bullet.rectangle")
        } description: {
            Text("This video does not contain chapter markers.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var currentChapterID: Int? {
        chapters
            .filter { $0.startTime <= currentTime }
            .max(by: { $0.startTime < $1.startTime })?
            .id
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(chapters) { chapter in
                        VideoStudyListCard(isSelected: chapter.id == currentChapterID) {
                            onSeekChapter(chapter.id)
                        } content: {
                            HStack(spacing: 10) {
                                Image(systemName: chapter.id == currentChapterID
                                    ? "play.fill"
                                    : "bookmark")
                                    .font(.caption)
                                    .foregroundStyle(chapter.id == currentChapterID
                                        ? Color.accentColor
                                        : Color.secondary)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chapter.title)
                                        .font(.callout)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(VideoTimeFormatter.string(from: chapter.startTime))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .id(chapter.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .onChange(of: currentChapterID) { _, chapterID in
                guard let chapterID else { return }
                withAnimation(.smooth(duration: 0.18)) {
                    proxy.scrollTo(chapterID, anchor: .center)
                }
            }
        }
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sections) { section in
                        sectionHeader(section.sourceName)

                        ForEach(section.items) { item in
                            historyRow(item)
                                .id(item.id)
                                .onAppear {
                                    if item.id == items.last?.id {
                                        isLatestItemVisible = true
                                    }
                                }
                                .onDisappear {
                                    if item.id == items.last?.id {
                                        isLatestItemVisible = false
                                    }
                                }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .task {
                scrollToLatest(using: proxy, animated: false)
            }
            .onChange(of: items.count) { _, _ in
                guard isLatestItemVisible else { return }
                scrollToLatest(using: proxy, animated: true)
            }
        }
    }

    private func sectionHeader(_ sourceName: String) -> some View {
        Text(sourceName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 4)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func historyRow(_ item: VideoMiningHistoryItem) -> some View {
        VideoStudyListCard {
            onJump(item)
        } content: {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.subtitleText.isEmpty ? "Blank Subtitle" : item.subtitleText)
                    .font(.callout)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(VideoTimeFormatter.string(from: item.cueStart))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } accessories: {
            HStack(spacing: 6) {
                Button {
                    onCopy(item)
                } label: {
                    Label("Copy Subtitle", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(VideoMiningHistoryIconButtonStyle())
                .help("Copy Subtitle")

                Button(role: .destructive) {
                    onDelete(item.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(VideoMiningHistoryIconButtonStyle())
                .help("Delete")
            }
        }
    }

    private func scrollToLatest(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let id = items.last?.id else { return }
        if animated {
            withAnimation(.smooth(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

}

private struct VideoStudySidebarBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
            .overlay {
                Rectangle()
                    .fill(colorScheme == .light ? Color.white.opacity(0.62) : Color.black.opacity(0.16))
            }
    }
}

struct VideoStudySidebarResizeHandle: View {
    @State private var isHovering = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 10)
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(isHovering ? 0.28 : 0.12))
                    .frame(width: 2)
                    .padding(.vertical, 10)
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                }
            }
    }
}

private struct VideoMiningHistoryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                configuration.isPressed ? Color.primary.opacity(0.14) : Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

private struct VideoMiningHistoryIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .background(
                configuration.isPressed ? Color.primary.opacity(0.14) : Color.primary.opacity(0.08),
                in: Circle()
            )
    }
}
#endif
