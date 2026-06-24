#if HOSHI_VIDEO
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoLibraryView: View {
    let onOpenVideo: (URL) -> Void

    @State private var viewModel = VideoLibraryViewModel()
    @State private var thumbnailStore = VideoThumbnailStore()
    @State private var isManagingSources = false

    var body: some View {
        content
            .toolbar {
                toolbarContent
            }
            .fileImporter(
                isPresented: $viewModel.isSelectingFolder,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: true,
                onCompletion: viewModel.addFolders
            )
            .sheet(isPresented: $isManagingSources) {
                VideoLibrarySourceManagementView(viewModel: viewModel)
            }
            .alert("Error", isPresented: $viewModel.shouldShowError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .overlay {
                if viewModel.isScanning {
                    LoadingOverlay(String(localized: "Scanning Video Folders..."))
                }
            }
            .onAppear {
                viewModel.load()
                viewModel.refreshPlaybackHistory()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                viewModel.refreshPlaybackHistory()
            }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasSources {
            ContentUnavailableView {
                Label("No Video Folders", systemImage: "film.stack")
            } description: {
                Text("Add a local folder to build your video bookshelf.")
            } actions: {
                Button {
                    viewModel.isSelectingFolder = true
                } label: {
                    Label("Add Video Folder", systemImage: "folder.badge.plus")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                VideoLibraryControlBar(viewModel: viewModel)

                Divider()

                libraryContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        let sections = viewModel.sections()
        if sections.isEmpty {
            ContentUnavailableView {
                Label(LocalizedStringKey(viewModel.emptyTitleKey), systemImage: "film")
            } description: {
                Text(LocalizedStringKey(viewModel.emptyDescriptionKey))
            } actions: {
                Button {
                    viewModel.refreshAllSources()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.layoutMode == .list {
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.rows) { row in
                            VideoLibraryRowView(
                                row: row,
                                onOpen: {
                                    if let url = viewModel.openURL(for: row.item) {
                                        onOpenVideo(url)
                                    }
                                },
                                onOpenFromBeginning: {
                                    if let url = viewModel.openFromBeginningURL(for: row.item) {
                                        onOpenVideo(url)
                                    }
                                },
                                onMarkWatched: {
                                    viewModel.markWatched(row.item)
                                },
                                onClearProgress: {
                                    viewModel.clearProgress(row.item)
                                }
                            )
                        }
                    }
                }
            }
            .listStyle(.inset)
        } else {
            VideoLibraryPosterGridView(
                sections: sections,
                thumbnailStore: thumbnailStore,
                onOpen: { item in
                    if let url = viewModel.openURL(for: item) {
                        onOpenVideo(url)
                    }
                },
                onOpenFromBeginning: { item in
                    if let url = viewModel.openFromBeginningURL(for: item) {
                        onOpenVideo(url)
                    }
                },
                onMarkWatched: viewModel.markWatched,
                onClearProgress: viewModel.clearProgress
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.refreshAllSources()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .disabled(!viewModel.hasSources || viewModel.isScanning)
            .help("Refresh Video Folders")

            Button {
                isManagingSources = true
            } label: {
                Label("Manage Sources", systemImage: "folder.badge.gearshape")
            }
            .labelStyle(.iconOnly)
            .disabled(!viewModel.hasSources)
            .help("Manage Sources")

            Button {
                viewModel.isSelectingFolder = true
            } label: {
                Label("Add Video Folder", systemImage: "folder.badge.plus")
            }
            .labelStyle(.iconOnly)
            .help("Add Video Folder")
        }
    }
}

private struct VideoLibraryControlBar: View {
    @Bindable var viewModel: VideoLibraryViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Picker("Video Library View", selection: $viewModel.displayMode) {
                    ForEach(VideoLibraryDisplayMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 680)

                Picker("Video Layout", selection: $viewModel.layoutMode) {
                    ForEach(VideoLibraryLayoutMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                TextField("Search Videos", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                Picker("Sort Videos", selection: $viewModel.sortOption) {
                    ForEach(VideoLibrarySortOption.allCases) { option in
                        Text(LocalizedStringKey(option.titleKey)).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 170)

                Toggle(isOn: $viewModel.showUnfinishedOnly) {
                    Label("Unfinished", systemImage: "circle.lefthalf.filled")
                }
                .toggleStyle(.button)
                .help("Unfinished")
                .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}

private struct VideoLibraryPosterGridView: View {
    let sections: [VideoLibrarySection]
    let thumbnailStore: VideoThumbnailStore
    let onOpen: (VideoLibraryItem) -> Void
    let onOpenFromBeginning: (VideoLibraryItem) -> Void
    let onMarkWatched: (VideoLibraryItem) -> Void
    let onClearProgress: (VideoLibraryItem) -> Void

    private static let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 2)

                        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 16) {
                            ForEach(section.rows) { row in
                                VideoLibraryPosterCardView(
                                    row: row,
                                    thumbnailStore: thumbnailStore,
                                    onOpen: { onOpen(row.item) },
                                    onOpenFromBeginning: { onOpenFromBeginning(row.item) },
                                    onMarkWatched: { onMarkWatched(row.item) },
                                    onClearProgress: { onClearProgress(row.item) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct VideoLibraryPosterCardView: View {
    let row: VideoLibraryRow
    let thumbnailStore: VideoThumbnailStore
    let onOpen: () -> Void
    let onOpenFromBeginning: () -> Void
    let onMarkWatched: () -> Void
    let onClearProgress: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                VideoThumbnailImageView(item: row.item, thumbnailStore: thumbnailStore)
                    .overlay(alignment: .bottomLeading) {
                        if let progress = row.playbackState?.progress {
                            ProgressView(value: progress)
                                .controlSize(.small)
                                .padding(8)
                        }
                    }

                Text(row.item.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .frame(minHeight: 36, alignment: .topLeading)

                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onOpenFromBeginning) {
                Label("Play from Beginning", systemImage: "backward.end")
            }

            Button(action: onMarkWatched) {
                Label("Mark as Watched", systemImage: "checkmark.circle")
            }

            Button(action: onClearProgress) {
                Label("Clear Progress", systemImage: "xmark.circle")
            }
            .disabled(row.playbackState == nil)

            Divider()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([row.item.url])
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }
        }
    }

    private var metadataText: String {
        if let state = row.playbackState {
            if state.isFinished {
                return String(localized: "Watched")
            }
            if let remaining = state.remainingTime {
                return String(
                    format: String(localized: "%@ left"),
                    VideoTimeFormatter.string(from: remaining)
                )
            }
        }
        return row.item.parentFolder
    }
}

private struct VideoThumbnailImageView: View {
    let item: VideoLibraryItem
    let thumbnailStore: VideoThumbnailStore

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "film")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: thumbnailStore.cacheKey(for: item)) {
            guard let url = await thumbnailStore.thumbnailURL(for: item) else { return }
            image = NSImage(contentsOf: url)
        }
    }
}

private struct VideoLibraryRowView: View {
    let row: VideoLibraryRow
    let onOpen: () -> Void
    let onOpenFromBeginning: () -> Void
    let onMarkWatched: () -> Void
    let onClearProgress: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: row.playbackState?.isFinished == true ? "checkmark.rectangle" : "play.rectangle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.item.title)
                        .lineLimit(1)
                        .font(.body.weight(.medium))
                    HStack(spacing: 8) {
                        Text(row.sourceName)
                        Text(row.item.parentFolder)
                        Text(Self.fileSizeFormatter.string(fromByteCount: row.item.fileSize))
                        if let modifiedAt = row.item.modifiedAt {
                            Text(modifiedAt, style: .date)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    if let progress = row.playbackState?.progress {
                        ProgressView(value: progress)
                            .controlSize(.small)
                    }
                }

                Spacer(minLength: 12)

                if let stateText {
                    Text(stateText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onOpenFromBeginning) {
                Label("Play from Beginning", systemImage: "backward.end")
            }

            Button(action: onMarkWatched) {
                Label("Mark as Watched", systemImage: "checkmark.circle")
            }

            Button(action: onClearProgress) {
                Label("Clear Progress", systemImage: "xmark.circle")
            }
            .disabled(row.playbackState == nil)

            Divider()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([row.item.url])
            } label: {
                Label("Reveal in Finder", systemImage: "finder")
            }
        }
    }

    private var stateText: String? {
        guard let state = row.playbackState else { return nil }
        if state.isFinished {
            return String(localized: "Watched")
        }
        if let remaining = state.remainingTime {
            return String(
                format: String(localized: "%@ left"),
                VideoTimeFormatter.string(from: remaining)
            )
        }
        return VideoTimeFormatter.string(from: state.position)
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private struct VideoLibrarySourceManagementView: View {
    @Bindable var viewModel: VideoLibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Manage Sources")
                    .font(.title2.bold())
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            List {
                ForEach(viewModel.sourceSummaries) { summary in
                    VideoLibrarySourceRowView(
                        summary: summary,
                        isScanning: viewModel.isScanning,
                        onRefresh: {
                            viewModel.refreshSource(id: summary.id)
                        },
                        onRemove: {
                            viewModel.removeSource(id: summary.id)
                        }
                    )
                }
            }
        }
        .frame(width: 620, height: 420)
    }
}

private struct VideoLibrarySourceRowView: View {
    let summary: VideoLibrarySourceSummary
    let isScanning: Bool
    let onRefresh: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: summary.source.lastError == nil ? "folder" : "folder.badge.questionmark")
                .foregroundStyle(summary.source.lastError == nil ? Color.secondary : Color.red)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(summary.source.name)
                    .font(.body.weight(.medium))
                Text(summary.source.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(Self.localizedCount("%d videos", summary.itemCount))
                    Text(Self.localizedCount("%d in progress", summary.inProgressCount))
                    if summary.missingCount > 0 {
                        Text(Self.localizedCount("%d missing", summary.missingCount))
                            .foregroundStyle(.red)
                    }
                    Text(lastScannedText)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let lastError = summary.source.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            Button(action: onRefresh) {
                Label("Refresh Source", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .help("Refresh Source")
            .disabled(isScanning)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: summary.source.path)
                ])
            } label: {
                Label("Reveal Source in Finder", systemImage: "folder")
            }
            .labelStyle(.iconOnly)
            .help("Reveal Source in Finder")

            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "minus.circle")
            }
            .labelStyle(.iconOnly)
            .help("Remove")
        }
        .padding(.vertical, 5)
    }

    private var lastScannedText: String {
        guard let lastScannedAt = summary.source.lastScannedAt else {
            return String(localized: "Never scanned")
        }
        return "\(String(localized: "Last Scanned")) \(Self.scanDateFormatter.string(from: lastScannedAt))"
    }

    private static func localizedCount(_ key: String, _ count: Int) -> String {
        String(format: NSLocalizedString(key, comment: ""), count)
    }

    private static let scanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
#endif
