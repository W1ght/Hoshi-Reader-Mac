#if HOSHI_VIDEO
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoLibraryView: View {
    let onOpenVideo: (URL, URL?) -> Void

    @State private var viewModel = VideoLibraryViewModel()
    @State private var thumbnailStore = VideoThumbnailStore()
    @State private var isReadyForSourceActions = false
    @State private var isManagingSources = false
    @State private var expandedSectionIDs: Set<String> = []

    var body: some View {
        content
            .toolbar {
                videoToolbarContent
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
            .sheet(isPresented: $isManagingSources) {
                VideoLibrarySourceManagementView(viewModel: viewModel)
            }
            .onAppear {
                viewModel.load()
                viewModel.refreshPlaybackHistory()
                armSourceActions()
            }
            .onDisappear {
                isReadyForSourceActions = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                viewModel.refreshPlaybackHistory()
            }
    }

    @ToolbarContentBuilder
    private var videoToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            VideoLibrarySortToolbarControl(viewModel: viewModel)
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            VideoLibraryLayoutToolbarControl(viewModel: viewModel)
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            VideoLibrarySearchAndSourceToolbarControl(
                viewModel: viewModel,
                onAddFolder: presentFolderImporter,
                onManageSources: { isManagingSources = true },
                isReadyForSourceActions: isReadyForSourceActions
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 0) {
            VideoLibrarySidebarView(viewModel: viewModel)
            .frame(width: 240)
            .background {
                NativeGlassPageBackground()
                    .ignoresSafeArea(.container, edges: .top)
            }

            VStack(spacing: 0) {
                VideoLibraryContentTitleBar(viewModel: viewModel)

                Divider()

                libraryContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                NativeGlassPageBackground()
            }

            if viewModel.selectedRow != nil {
                Divider()

                VideoLibraryInspectorView(viewModel: viewModel)
                    .frame(minWidth: 280, idealWidth: 300, maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            NativeGlassPageBackground()
        }
    }

    private func armSourceActions() {
        isReadyForSourceActions = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            isReadyForSourceActions = true
        }
    }

    private func presentFolderImporter() {
        guard isReadyForSourceActions else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false

        let response = panel.runModal()
        guard response == .OK else { return }
        viewModel.addFolders(.success(panel.urls))
    }

    @ViewBuilder
    private var libraryContent: some View {
        let sections = viewModel.sections()
        if !viewModel.hasSources {
            ContentUnavailableView {
                Label("No Video Folders", systemImage: "film.stack")
            } description: {
                Text("Add a local folder to build your video bookshelf.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sections.isEmpty {
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
                    if viewModel.displayMode.usesCollapsibleSections {
                        DisclosureGroup(isExpanded: sectionExpansionBinding(for: section)) {
                            ForEach(section.rows) { row in
                                libraryListRow(row)
                            }
                        } label: {
                            VideoLibraryDisclosureSectionLabel(
                                title: section.title,
                                count: section.rows.count
                            )
                        }
                    } else {
                        Section(section.title) {
                            ForEach(section.rows) { row in
                                libraryListRow(row)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        } else {
            VideoLibraryPosterGridView(
                sections: sections,
                thumbnailStore: thumbnailStore,
                hidesSingleSectionHeader: shouldHideSinglePosterSectionHeader(for: sections),
                usesCollapsibleSections: viewModel.displayMode.usesCollapsibleSections,
                expandedSectionIDs: $expandedSectionIDs,
                onOpen: { item in
                    viewModel.select(item: item)
                    if let url = viewModel.openURL(for: item) {
                        onOpenVideo(url, viewModel.subtitleURLForOpening(item))
                    }
                },
                onOpenFromBeginning: { item in
                    viewModel.select(item: item)
                    if let url = viewModel.openFromBeginningURL(for: item) {
                        onOpenVideo(url, viewModel.subtitleURLForOpening(item))
                    }
                },
                onSelect: viewModel.select,
                onMarkWatched: viewModel.markWatched,
                onClearProgress: viewModel.clearProgress
            )
        }
    }

    private func libraryListRow(_ row: VideoLibraryRow) -> some View {
        VideoLibraryRowView(
            row: row,
            thumbnailStore: thumbnailStore,
            onOpen: {
                viewModel.select(item: row.item)
                if let url = viewModel.openURL(for: row.item) {
                    onOpenVideo(url, viewModel.subtitleURLForOpening(row.item))
                }
            },
            onOpenFromBeginning: {
                viewModel.select(item: row.item)
                if let url = viewModel.openFromBeginningURL(for: row.item) {
                    onOpenVideo(url, viewModel.subtitleURLForOpening(row.item))
                }
            },
            onSelect: {
                viewModel.select(item: row.item)
            },
            onMarkWatched: {
                viewModel.markWatched(row.item)
            },
            onClearProgress: {
                viewModel.clearProgress(row.item)
            }
        )
    }

    private func sectionExpansionBinding(for section: VideoLibrarySection) -> Binding<Bool> {
        Binding(
            get: { expandedSectionIDs.contains(section.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSectionIDs.insert(section.id)
                } else {
                    expandedSectionIDs.remove(section.id)
                }
            }
        )
    }

    private func shouldHideSinglePosterSectionHeader(for sections: [VideoLibrarySection]) -> Bool {
        guard sections.count == 1 else { return false }
        return sections.first?.id == duplicateSectionHeaderID
    }

    private var duplicateSectionHeaderID: String? {
        switch viewModel.displayMode {
        case .continueWatching: "continue"
        case .favorites: "favorites"
        case .unwatched: "unwatched"
        case .finished: "finished"
        case .missing: "missing"
        case .recent: "recent"
        case .all: "all"
        case .needsReview: "needs-review"
        case .series, .folders, .collections: nil
        }
    }

}

private struct VideoLibrarySidebarView: View {
    @Bindable var viewModel: VideoLibraryViewModel

    var body: some View {
        List(selection: modeSelection) {
            Section("Library") {
                sidebarRow(.continueWatching, systemImage: "play.circle")
                sidebarRow(.unwatched, systemImage: "circle")
                sidebarRow(.finished, systemImage: "checkmark.circle")
                sidebarRow(.missing, systemImage: "exclamationmark.triangle")
                sidebarRow(.recent, systemImage: "clock")
                sidebarRow(.all, systemImage: "film.stack")
                sidebarRow(.needsReview, systemImage: "tray")
            }

            Section("Organization") {
                sidebarRow(.favorites, systemImage: "star")
                sidebarRow(.series, systemImage: "rectangle.stack")
                sidebarRow(.collections, systemImage: "folder")
                sidebarRow(.folders, systemImage: "folder.badge.gearshape")
            }
        }
        .listStyle(.sidebar)
    }

    private var modeSelection: Binding<VideoLibraryDisplayMode?> {
        Binding(
            get: { viewModel.displayMode },
            set: { mode in
                if let mode {
                    viewModel.displayMode = mode
                }
            }
        )
    }

    private func sidebarRow(
        _ mode: VideoLibraryDisplayMode,
        systemImage: String
    ) -> some View {
        Label(LocalizedStringKey(mode.titleKey), systemImage: systemImage)
            .tag(mode)
    }
}

private struct VideoLibrarySourceToolbarButtons: View {
    @Bindable var viewModel: VideoLibraryViewModel
    let onAddFolder: () -> Void
    let onManageSources: () -> Void
    let isReadyForSourceActions: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.refreshAllSources()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(!viewModel.hasSources || viewModel.isScanning)
            .help("Refresh")
            .accessibilityLabel(Text("Refresh"))

            Button {
                onAddFolder()
            } label: {
                Label("Add Video Folder", systemImage: "folder.badge.plus")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(!isReadyForSourceActions)
            .help("Add Video Folder")
            .accessibilityLabel(Text("Add Video Folder"))

            Button {
                onManageSources()
            } label: {
                Label("Manage Sources", systemImage: "folder.badge.gearshape")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(!viewModel.hasSources)
            .help("Manage Sources")
            .accessibilityLabel(Text("Manage Sources"))
        }
        .fixedSize()
    }
}

private struct VideoLibraryContentTitleBar: View {
    @Bindable var viewModel: VideoLibraryViewModel

    var body: some View {
        HStack(spacing: 0) {
            Text(LocalizedStringKey(viewModel.displayMode.titleKey))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
    }
}

private struct VideoLibrarySortToolbarControl: View {
    @Bindable var viewModel: VideoLibraryViewModel

    var body: some View {
        VideoLibrarySortPopUpButton(selection: $viewModel.sortOption)
            .frame(width: 104, height: 30)
            .accessibilityLabel(Text("Sort Videos"))
    }
}

private struct VideoLibraryLayoutToolbarControl: View {
    @Bindable var viewModel: VideoLibraryViewModel

    var body: some View {
        VideoLibraryLayoutSegmentedControl(selection: $viewModel.layoutMode)
            .frame(width: 78, height: 30)
            .accessibilityLabel(Text("Video Layout"))
    }
}

private struct VideoLibrarySearchAndSourceToolbarControl: View {
    @Bindable var viewModel: VideoLibraryViewModel
    let onAddFolder: () -> Void
    let onManageSources: () -> Void
    let isReadyForSourceActions: Bool

    var body: some View {
        HStack(spacing: 8) {
            VideoLibrarySearchToolbarControl(viewModel: viewModel)

            VideoLibrarySourceToolbarButtons(
                viewModel: viewModel,
                onAddFolder: onAddFolder,
                onManageSources: onManageSources,
                isReadyForSourceActions: isReadyForSourceActions
            )
        }
    }
}

private struct VideoLibrarySearchToolbarControl: View {
    @Bindable var viewModel: VideoLibraryViewModel

    var body: some View {
        VideoLibrarySearchField(text: $viewModel.searchText)
            .frame(minWidth: 90, idealWidth: 140, maxWidth: 180)
            .layoutPriority(1)
    }
}

private struct VideoLibrarySearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search Videos", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .contentShape(Rectangle())
    }
}

private struct VideoLibrarySortPopUpButton: NSViewRepresentable {
    @Binding var selection: VideoLibrarySortOption

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.required, for: .horizontal)
        context.coordinator.configure(button)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.configure(button)
    }

    final class Coordinator: NSObject {
        var selection: Binding<VideoLibrarySortOption>

        init(selection: Binding<VideoLibrarySortOption>) {
            self.selection = selection
        }

        func configure(_ button: NSPopUpButton) {
            if button.numberOfItems != VideoLibrarySortOption.allCases.count {
                button.removeAllItems()
                for option in VideoLibrarySortOption.allCases {
                    let item = NSMenuItem(
                        title: String(localized: String.LocalizationValue(option.titleKey)),
                        action: nil,
                        keyEquivalent: ""
                    )
                    item.representedObject = option.rawValue
                    button.menu?.addItem(item)
                }
            }

            if let index = VideoLibrarySortOption.allCases.firstIndex(of: selection.wrappedValue) {
                button.selectItem(at: index)
            }
            button.toolTip = String(localized: "Sort Videos")
            button.setAccessibilityLabel(String(localized: "Sort Videos"))
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            let selectedIndex = sender.indexOfSelectedItem
            guard VideoLibrarySortOption.allCases.indices.contains(selectedIndex) else { return }
            selection.wrappedValue = VideoLibrarySortOption.allCases[selectedIndex]
        }
    }
}

private struct VideoLibraryLayoutSegmentedControl: NSViewRepresentable {
    @Binding var selection: VideoLibraryLayoutMode

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: Array(repeating: "", count: VideoLibraryLayoutMode.allCases.count),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.segmentStyle = .automatic
        control.controlSize = .small
        control.setContentHuggingPriority(.required, for: .horizontal)
        context.coordinator.configure(control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.configure(control)
    }

    final class Coordinator: NSObject {
        var selection: Binding<VideoLibraryLayoutMode>

        init(selection: Binding<VideoLibraryLayoutMode>) {
            self.selection = selection
        }

        func configure(_ control: NSSegmentedControl) {
            if control.segmentCount != VideoLibraryLayoutMode.allCases.count {
                control.segmentCount = VideoLibraryLayoutMode.allCases.count
            }

            for (index, mode) in VideoLibraryLayoutMode.allCases.enumerated() {
                let title = String(localized: String.LocalizationValue(mode.titleKey))
                let image = NSImage(
                    systemSymbolName: mode.systemImageName,
                    accessibilityDescription: title
                )
                control.setImage(image, forSegment: index)
                control.setLabel("", forSegment: index)
                control.setToolTip(title, forSegment: index)
                control.setWidth(34, forSegment: index)
            }

            if let selectedIndex = VideoLibraryLayoutMode.allCases.firstIndex(of: selection.wrappedValue) {
                control.selectedSegment = selectedIndex
            }
            control.setAccessibilityLabel(String(localized: "Video Layout"))
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let selectedIndex = sender.selectedSegment
            guard VideoLibraryLayoutMode.allCases.indices.contains(selectedIndex) else { return }
            selection.wrappedValue = VideoLibraryLayoutMode.allCases[selectedIndex]
        }
    }
}

private struct VideoLibraryHeaderGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                content
                    .glassEffect(
                        .regular.interactive(),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
            }
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10), lineWidth: 0.7)
                }
        }
    }
}

private struct VideoLibrarySectionHeaderSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modifier(VideoLibraryHeaderGlassSurface())
    }
}

private struct VideoLibraryPosterGridView: View {
    let sections: [VideoLibrarySection]
    let thumbnailStore: VideoThumbnailStore
    let hidesSingleSectionHeader: Bool
    let usesCollapsibleSections: Bool
    @Binding var expandedSectionIDs: Set<String>
    let onOpen: (VideoLibraryItem) -> Void
    let onOpenFromBeginning: (VideoLibraryItem) -> Void
    let onSelect: (VideoLibraryItem) -> Void
    let onMarkWatched: (VideoLibraryItem) -> Void
    let onClearProgress: (VideoLibraryItem) -> Void

    private static let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(sections) { section in
                    if usesCollapsibleSections {
                        DisclosureGroup(isExpanded: sectionExpansionBinding(for: section)) {
                            posterGrid(for: section)
                                .padding(.top, 14)
                        } label: {
                            VideoLibrarySectionHeader(title: section.title, count: section.rows.count)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            if !hidesSingleSectionHeader {
                                VideoLibrarySectionHeader(title: section.title)
                            }

                            posterGrid(for: section)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func posterGrid(for section: VideoLibrarySection) -> some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 20) {
            ForEach(section.rows) { row in
                VideoLibraryPosterCardView(
                    row: row,
                    thumbnailStore: thumbnailStore,
                    onOpen: { onOpen(row.item) },
                    onOpenFromBeginning: { onOpenFromBeginning(row.item) },
                    onSelect: { onSelect(row.item) },
                    onMarkWatched: { onMarkWatched(row.item) },
                    onClearProgress: { onClearProgress(row.item) }
                )
            }
        }
    }

    private func sectionExpansionBinding(for section: VideoLibrarySection) -> Binding<Bool> {
        Binding(
            get: { expandedSectionIDs.contains(section.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedSectionIDs.insert(section.id)
                } else {
                    expandedSectionIDs.remove(section.id)
                }
            }
        )
    }
}

private struct VideoLibrarySectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            if let count {
                Text(Self.videoCountText(count))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .modifier(VideoLibrarySectionHeaderSurface())
    }

    private static func videoCountText(_ count: Int) -> String {
        String(format: String(localized: "%d videos"), count)
    }
}

private struct VideoLibraryDisclosureSectionLabel: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(Self.videoCountText(count))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private static func videoCountText(_ count: Int) -> String {
        String(format: String(localized: "%d videos"), count)
    }
}

private struct VideoLibraryPosterCardView: View {
    let row: VideoLibraryRow
    let thumbnailStore: VideoThumbnailStore
    let onOpen: () -> Void
    let onOpenFromBeginning: () -> Void
    let onSelect: () -> Void
    let onMarkWatched: () -> Void
    let onClearProgress: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 9) {
                    VideoThumbnailImageView(
                        item: row.item,
                        thumbnailStore: thumbnailStore,
                        generatesMissingThumbnail: true
                    )
                        .overlay {
                            if isHovered {
                                VideoLibraryPosterPlayOverlay()
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if let progress = row.playbackState?.progress {
                                VideoLibraryBottomProgressBar(progress: progress)
                            }
                        }

                    Text(row.displayTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .frame(minHeight: 36, alignment: .topLeading)

                    Text(metadataText.uppercased())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VideoLibraryDetailsButton(onSelect: onSelect)
                .padding(6)
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(action: onSelect) {
                Label("Details", systemImage: "info.circle")
            }

            Divider()

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

private struct VideoLibraryPosterPlayOverlay: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(.black.opacity(0.46), in: Circle())
            .shadow(radius: 10, y: 3)
    }
}

private struct VideoLibraryBottomProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.black.opacity(0.20))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * clampedProgress)
            }
        }
        .frame(height: 5)
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
}

private struct VideoThumbnailImageView: View {
    let item: VideoLibraryItem
    let thumbnailStore: VideoThumbnailStore
    let generatesMissingThumbnail: Bool

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
            image = nil
            if let cachedURL = thumbnailStore.cachedThumbnailURL(for: item) {
                image = NSImage(contentsOf: cachedURL)
                return
            }
            guard generatesMissingThumbnail else { return }
            guard let url = await thumbnailStore.thumbnailURL(for: item) else { return }
            image = NSImage(contentsOf: url)
        }
    }
}

private struct VideoLibraryRowView: View {
    let row: VideoLibraryRow
    let thumbnailStore: VideoThumbnailStore
    let onOpen: () -> Void
    let onOpenFromBeginning: () -> Void
    let onSelect: () -> Void
    let onMarkWatched: () -> Void
    let onClearProgress: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    VideoThumbnailImageView(
                        item: row.item,
                        thumbnailStore: thumbnailStore,
                        generatesMissingThumbnail: true
                    )
                        .frame(width: 144, height: 81)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.displayTitle)
                            .lineLimit(1)
                            .font(.body.weight(.semibold))

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

                        HStack(spacing: 8) {
                            if let progress = row.playbackState?.progress {
                                ProgressView(value: progress)
                                    .controlSize(.small)
                                    .frame(width: 120)
                            }

                            if let stateText {
                                Text(stateText)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            VideoLibraryDetailsButton(onSelect: onSelect)
        }
        .contextMenu {
            Button(action: onSelect) {
                Label("Details", systemImage: "info.circle")
            }

            Divider()

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

private struct VideoLibraryDetailsButton: View {
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Label("Details", systemImage: "info.circle")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Details")
        .accessibilityLabel(Text("Details"))
    }
}

private struct VideoLibraryInspectorView: View {
    @Bindable var viewModel: VideoLibraryViewModel

    @State private var titleDraft = ""
    @State private var tagsDraft = ""
    @State private var collectionNameDraft = ""
    @State private var smartCollectionNameDraft = ""
    @State private var smartCollectionRuleField: VideoLibrarySmartRuleField = .fileName
    @State private var smartCollectionRuleDraft = ""
    @State private var isBindingSubtitle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Video Details")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.clearSelection()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Close")
                .accessibilityLabel(Text("Close"))
            }

            if let row = viewModel.selectedRow {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        metadataSection(row)
                        subtitleSection(row)
                        collectionsSection(row)
                        smartCollectionsSection(row)
                        batchSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView {
                    Label("Details", systemImage: "sidebar.right")
                } description: {
                    Text("Select a video to edit its local metadata.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .fileImporter(
            isPresented: $isBindingSubtitle,
            allowedContentTypes: Self.subtitleContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard let item = viewModel.selectedRow?.item,
                  let subtitleURL = try? result.get().first else {
                return
            }
            viewModel.bindSubtitle(subtitleURL, for: item)
        }
        .onChange(of: viewModel.selectedItemID, initial: true) { _, _ in
            syncDrafts()
        }
    }

    private func metadataSection(_ row: VideoLibraryRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Display Title", text: $titleDraft)

            Toggle("Favorite", isOn: Binding(
                get: { viewModel.selectedRow?.metadata.isFavorite ?? false },
                set: { isFavorite in
                    viewModel.setFavorite(isFavorite, for: row.item)
                }
            ))

            TextField("Tags", text: $tagsDraft)
                .help("Tags")

            Button("Save Metadata") {
                viewModel.setDisplayTitle(titleDraft, for: row.item)
                viewModel.setTags(Self.tags(from: tagsDraft), for: row.item)
                syncDrafts()
            }
        }
    }

    private func subtitleSection(_ row: VideoLibraryRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bound Subtitle")
                .font(.subheadline.weight(.semibold))

            if let boundSubtitleURL = row.boundSubtitleURL {
                Text(boundSubtitleURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button("Clear Subtitle") {
                    viewModel.bindSubtitle(nil, for: row.item)
                }
            } else if let subtitleCandidateURL = row.subtitleCandidateURL {
                Label(
                    "\(String(localized: "Auto Subtitle")): \(subtitleCandidateURL.lastPathComponent)",
                    systemImage: "captions.bubble"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text("Auto Subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Bind Subtitle") {
                isBindingSubtitle = true
            }
        }
    }

    private func collectionsSection(_ row: VideoLibraryRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collections")
                .font(.subheadline.weight(.semibold))

            ForEach(viewModel.catalog.collections.filter { $0.kind == .manual }) { collection in
                Toggle(collection.name, isOn: Binding(
                    get: {
                        viewModel.selectedRow?.metadata.collectionIDs.contains(collection.id) ?? false
                    },
                    set: { isIncluded in
                        viewModel.setCollectionMembership(
                            isIncluded,
                            collectionID: collection.id,
                            for: row.item
                        )
                    }
                ))
            }

            HStack(spacing: 8) {
                TextField("New Collection", text: $collectionNameDraft)
                Button("Add Collection") {
                    _ = viewModel.createCollection(name: collectionNameDraft, items: [row.item])
                    collectionNameDraft = ""
                }
                .disabled(collectionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func smartCollectionsSection(_ row: VideoLibraryRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Smart Collections")
                .font(.subheadline.weight(.semibold))

            ForEach(viewModel.catalog.collections.filter { $0.kind == .smart }) { collection in
                HStack(spacing: 8) {
                    Label(collection.name, systemImage: "line.3.horizontal.decrease.circle")
                        .lineLimit(1)
                    Spacer()
                    Text("Smart")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Label("New Smart Collection", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("New Smart Collection", text: $smartCollectionNameDraft)

            Picker("Rule Field", selection: $smartCollectionRuleField) {
                ForEach(VideoLibrarySmartRuleField.smartCollectionEditorFields, id: \.self) { field in
                    Text(LocalizedStringKey(field.smartCollectionTitleKey))
                        .tag(field)
                }
            }
            .pickerStyle(.menu)

            TextField("Rule Text", text: $smartCollectionRuleDraft)

            if !smartCollectionDraftRules.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Preview Matches")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    let previewRows = viewModel.smartCollectionPreviewRows(
                        rules: smartCollectionDraftRules,
                        limit: 5
                    )
                    if previewRows.isEmpty {
                        Text("No Matching Videos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(previewRows) { previewRow in
                            Text(previewRow.displayTitle)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Button {
                _ = viewModel.createSmartCollection(
                    name: smartCollectionNameDraft,
                    rules: smartCollectionDraftRules
                )
                smartCollectionNameDraft = ""
                smartCollectionRuleDraft = ""
            } label: {
                Label("Add Smart Collection", systemImage: "plus")
            }
            .disabled(
                smartCollectionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || smartCollectionDraftRules.isEmpty
            )
        }
    }

    private var smartCollectionDraftRules: [VideoLibrarySmartRule] {
        let value = smartCollectionRuleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        return [
            VideoLibrarySmartRule(
                field: smartCollectionRuleField,
                match: .contains,
                value: value
            )
        ]
    }

    private var batchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Button("Mark Selected Watched") {
                viewModel.markSelectedWatched()
            }

            Button("Clear Selected Progress") {
                viewModel.clearSelectedProgress()
            }

            Button("Remove Missing", role: .destructive) {
                _ = viewModel.removeMissingItems()
            }
        }
    }

    private func syncDrafts() {
        guard let row = viewModel.selectedRow else {
            titleDraft = ""
            tagsDraft = ""
            return
        }
        titleDraft = row.metadata.displayTitle ?? row.item.title
        tagsDraft = row.metadata.tags.joined(separator: ", ")
    }

    private static func tags(from value: String) -> [String] {
        value
            .split { character in
                character == "," || character == "\n"
            }
            .map(String.init)
    }

    private static let subtitleContentTypes: [UTType] = {
        let explicitTypes = ["srt", "vtt", "ass", "ssa"].compactMap { UTType(filenameExtension: $0) }
        return explicitTypes + [.plainText, .text]
    }()
}

private extension VideoLibrarySmartRuleField {
    static let smartCollectionEditorFields: [VideoLibrarySmartRuleField] = [
        .fileName,
        .parentFolder,
        .path,
        .tag,
    ]

    var smartCollectionTitleKey: String {
        switch self {
        case .fileName:
            return "File Name"
        case .parentFolder:
            return "Parent Folder"
        case .path:
            return "Path"
        case .tag:
            return "Tag"
        case .hasBoundSubtitle:
            return "Bound Subtitle"
        case .playbackState:
            return "Watched"
        }
    }
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
