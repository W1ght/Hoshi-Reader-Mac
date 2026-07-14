#if HOSHI_VIDEO
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoLibraryView: View {
    let onOpenVideo: (VideoPlaybackSource, URL?) -> Void
    private let thumbnailScheduler = VideoThumbnailScheduler.shared

    @State private var viewModel = VideoLibraryViewModel()
    @State private var isReadyForSourceActions = false
    @State private var isManagingSources = false
    @State private var isAddingLink = false
    @State private var pendingResolvedRemoteSource: ResolvedRemoteVideoSource?
    @State private var expandedSectionIDs: Set<String> = []
    @State private var pendingCollectionDeletion: VideoLibraryCollection?
    @State private var openTask: Task<Void, Never>?

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
            .alert("Delete Collection?", isPresented: collectionDeletionAlertBinding) {
                Button("Delete Collection", role: .destructive) {
                    if let collection = pendingCollectionDeletion {
                        deleteCollection(collection)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingCollectionDeletion = nil
                }
            } message: {
                Text("This removes the collection but keeps its videos in your library.")
            }
            .overlay {
                if viewModel.isScanning {
                    LoadingOverlay(String(localized: "Scanning Video Folders..."))
                }
            }
            .sheet(isPresented: $isManagingSources) {
                VideoLibrarySourceManagementView(viewModel: viewModel)
            }
            .sheet(
                isPresented: $isAddingLink,
                onDismiss: openResolvedRemoteSourceAfterSheetDismissal
            ) {
                RemoteVideoLinkSheet { resolvedSource in
                    _ = viewModel.addRemoteItem(resolvedSource)
                    pendingResolvedRemoteSource = resolvedSource
                }
            }
            .onAppear {
                viewModel.load()
                viewModel.refreshPlaybackHistory()
                armSourceActions()
            }
            .onDisappear {
                openTask?.cancel()
                openTask = nil
                viewModel.cancelPendingOpen()
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

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItemGroup(placement: .primaryAction) {
            VideoLibraryLayoutToolbarControl(viewModel: viewModel)
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItemGroup(placement: .primaryAction) {
            VideoLibrarySearchAndSourceToolbarControl(
                viewModel: viewModel,
                onAddFolder: presentFolderImporter,
                onAddLink: { isAddingLink = true },
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
                                count: section.rows.count,
                                onDeleteCollection: deleteCollectionAction(for: section)
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
                thumbnailScheduler: thumbnailScheduler,
                hidesSingleSectionHeader: shouldHideSinglePosterSectionHeader(for: sections),
                usesCollapsibleSections: viewModel.displayMode.usesCollapsibleSections,
                expandedSectionIDs: $expandedSectionIDs,
                onOpen: { item in
                    viewModel.select(item: item)
                    open(item, fromBeginning: false)
                },
                onOpenFromBeginning: { item in
                    viewModel.select(item: item)
                    open(item, fromBeginning: true)
                },
                onSelect: viewModel.select,
                onMarkWatched: viewModel.markWatched,
                onClearProgress: viewModel.clearProgress,
                onRemoveRemote: viewModel.removeRemoteItem,
                onDeleteCollection: { collection in
                    pendingCollectionDeletion = collection
                }
            )
        }
    }

    private func libraryListRow(_ row: VideoLibraryRow) -> some View {
        VideoLibraryRowView(
            row: row,
            thumbnailScheduler: thumbnailScheduler,
            onOpen: {
                viewModel.select(item: row.item)
                open(row.item, fromBeginning: false)
            },
            onOpenFromBeginning: {
                viewModel.select(item: row.item)
                open(row.item, fromBeginning: true)
            },
            onSelect: {
                viewModel.select(item: row.item)
            },
            onMarkWatched: {
                viewModel.markWatched(row.item)
            },
            onClearProgress: {
                viewModel.clearProgress(row.item)
            },
            onRemoveRemote: {
                viewModel.removeRemoteItem(row.item)
            }
        )
    }

    private func open(_ item: VideoLibraryItem, fromBeginning: Bool) {
        openTask?.cancel()
        viewModel.cancelPendingOpen()
        openTask = Task { @MainActor in
            let source = if fromBeginning {
                await viewModel.openFromBeginningPlaybackSource(for: item)
            } else {
                await viewModel.openPlaybackSource(for: item)
            }
            guard !Task.isCancelled, let source else { return }
            onOpenVideo(source, viewModel.subtitleURLForOpening(item))
        }
    }

    private func openResolvedRemoteSourceAfterSheetDismissal() {
        guard let resolvedSource = pendingResolvedRemoteSource else { return }
        pendingResolvedRemoteSource = nil
        onOpenVideo(.remoteStream(resolvedSource), nil)
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

    private var collectionDeletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingCollectionDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingCollectionDeletion = nil
                }
            }
        )
    }

    private func deleteCollectionAction(for section: VideoLibrarySection) -> (() -> Void)? {
        guard let collection = section.collection else { return nil }
        return {
            pendingCollectionDeletion = collection
        }
    }

    private func deleteCollection(_ collection: VideoLibraryCollection) {
        viewModel.removeCollection(id: collection.id)
        expandedSectionIDs.remove("collection-\(collection.id.uuidString)")
        pendingCollectionDeletion = nil
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
    let onAddLink: () -> Void
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
                onAddLink()
            } label: {
                Label("Add Link", systemImage: "link.badge.plus")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(!isReadyForSourceActions)
            .help("Add Link")
            .accessibilityLabel(Text("Add Link"))

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
            .accessibilityLabel(Text("Video Library View"))
    }
}

private struct VideoLibrarySearchAndSourceToolbarControl: View {
    @Bindable var viewModel: VideoLibraryViewModel
    let onAddFolder: () -> Void
    let onAddLink: () -> Void
    let onManageSources: () -> Void
    let isReadyForSourceActions: Bool

    var body: some View {
        HStack(spacing: 8) {
            VideoLibrarySearchToolbarControl(viewModel: viewModel)

            VideoLibrarySourceToolbarButtons(
                viewModel: viewModel,
                onAddFolder: onAddFolder,
                onAddLink: onAddLink,
                onManageSources: onManageSources,
                isReadyForSourceActions: isReadyForSourceActions
            )
        }
    }
}

struct RemoteVideoLinkSheet: View {
    let onResolved: (ResolvedRemoteVideoSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rawURL = ""
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var resolutionTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("YouTube Video")
                    .font(.headline)

                Text("Experimental")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.14), in: Capsule())
            }

            Text("YouTube playback is experimental and may stop working when YouTube changes its service.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Open Link", text: $rawURL)
                .textFieldStyle(.roundedBorder)
                .disabled(isResolving)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    resolutionTask?.cancel()
                    dismiss()
                }

                Button {
                    resolve()
                } label: {
                    if isResolving {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Resolving Link...")
                        }
                    } else {
                        Text("Add Link")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isResolving || URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onDisappear {
            resolutionTask?.cancel()
            resolutionTask = nil
        }
    }

    private func resolve() {
        let cleaned = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned) else { return }
        isResolving = true
        errorMessage = nil
        resolutionTask?.cancel()
        resolutionTask = Task { @MainActor in
            do {
                let resolved = try await RemoteVideoResolverRegistry().resolve(url: url)
                guard !Task.isCancelled else { return }
                onResolved(resolved)
                dismiss()
            } catch {
                guard !Task.isCancelled,
                      !(error is CancellationError) else {
                    return
                }
                if let resolverError = error as? RemoteVideoResolverError,
                   case .cancelled = resolverError {
                    return
                }
                errorMessage = error.localizedDescription
                isResolving = false
            }
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
            control.setAccessibilityLabel(String(localized: "Video Library View"))
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let selectedIndex = sender.selectedSegment
            guard VideoLibraryLayoutMode.allCases.indices.contains(selectedIndex) else { return }
            selection.wrappedValue = VideoLibraryLayoutMode.allCases[selectedIndex]
        }
    }
}

private struct VideoLibraryPosterGridView: View {
    let sections: [VideoLibrarySection]
    let thumbnailScheduler: VideoThumbnailScheduler
    let hidesSingleSectionHeader: Bool
    let usesCollapsibleSections: Bool
    @Binding var expandedSectionIDs: Set<String>
    let onOpen: (VideoLibraryItem) -> Void
    let onOpenFromBeginning: (VideoLibraryItem) -> Void
    let onSelect: (VideoLibraryItem) -> Void
    let onMarkWatched: (VideoLibraryItem) -> Void
    let onClearProgress: (VideoLibraryItem) -> Void
    let onRemoveRemote: (VideoLibraryItem) -> Void
    let onDeleteCollection: (VideoLibraryCollection) -> Void

    private static let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections) { section in
                    if usesCollapsibleSections {
                        DisclosureGroup(isExpanded: sectionExpansionBinding(for: section)) {
                            posterGrid(for: section)
                                .padding(.top, 12)
                        } label: {
                            VideoLibraryDisclosureSectionLabel(
                                title: section.title,
                                count: section.rows.count,
                                onDeleteCollection: deleteCollectionAction(for: section)
                            )
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if !hidesSingleSectionHeader {
                                VideoLibraryPosterSectionHeader(title: section.title)
                            }

                            posterGrid(for: section)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func posterGrid(for section: VideoLibrarySection) -> some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 16) {
            ForEach(section.rows) { row in
                VideoLibraryPosterCardView(
                    row: row,
                    thumbnailScheduler: thumbnailScheduler,
                    thumbnailRequestMode: .generateIfMissing,
                    onOpen: { onOpen(row.item) },
                    onOpenFromBeginning: { onOpenFromBeginning(row.item) },
                    onSelect: { onSelect(row.item) },
                    onMarkWatched: { onMarkWatched(row.item) },
                    onClearProgress: { onClearProgress(row.item) },
                    onRemoveRemote: { onRemoveRemote(row.item) }
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

    private func deleteCollectionAction(for section: VideoLibrarySection) -> (() -> Void)? {
        guard let collection = section.collection else { return nil }
        return {
            onDeleteCollection(collection)
        }
    }
}

private struct VideoLibraryPosterSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 4)
    }
}

private struct VideoLibraryDisclosureSectionLabel: View {
    let title: String
    let count: Int
    let onDeleteCollection: (() -> Void)?

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

            if let onDeleteCollection {
                VideoLibraryCollectionActionsMenu(onDeleteCollection: onDeleteCollection)
            }
        }
    }

    private static func videoCountText(_ count: Int) -> String {
        String(format: String(localized: "%d videos"), count)
    }
}

private struct VideoLibraryCollectionActionsMenu: View {
    let onDeleteCollection: () -> Void

    var body: some View {
        Menu {
            Button(role: .destructive, action: onDeleteCollection) {
                Label("Delete Collection", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
                .modifier(VideoLibraryCollectionActionsGlassEffect())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Collection Actions")
        .accessibilityLabel(Text("Collection Actions"))
    }
}

private struct VideoLibraryCollectionActionsGlassEffect: ViewModifier {
    func body(content: Content) -> some View {
        GlassEffectContainer(spacing: 0) {
            content
                .foregroundStyle(.secondary)
                .glassEffect(.regular.interactive(), in: Circle())
        }
    }
}

private struct VideoLibraryPosterCardView: View {
    let row: VideoLibraryRow
    let thumbnailScheduler: VideoThumbnailScheduler
    let thumbnailRequestMode: VideoThumbnailRequestMode
    let onOpen: () -> Void
    let onOpenFromBeginning: () -> Void
    let onSelect: () -> Void
    let onMarkWatched: () -> Void
    let onClearProgress: () -> Void
    let onRemoveRemote: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 9) {
                    VideoLibraryPosterArtworkView(
                        row: row,
                        thumbnailScheduler: thumbnailScheduler,
                        requestMode: thumbnailRequestMode,
                        isHovered: isHovered
                    )
                        .overlay(alignment: .bottom) {
                            if let progress = row.playbackState?.progress {
                                VideoLibraryBottomProgressBar(progress: progress)
                            }
                        }

                    Text(row.displayTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                        .frame(minHeight: 36, alignment: .topLeading)

                    Text(metadataText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            VideoLibraryDetailsButton(onSelect: onSelect)
                .padding(8)
        }
        .videoLibraryNeutralCardSurface(cornerRadius: 16)
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

            if let localURL = row.item.localURL {
                Divider()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([localURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "finder")
                }
            } else {
                Divider()

                Button(role: .destructive, action: onRemoveRemote) {
                    Label("Remove from Library", systemImage: "trash")
                }
            }
        }
    }

    private var metadataText: String {
        var components = [row.sourceName]
        if row.item.localURL != nil {
            components.append(row.item.parentFolder)
            components.append(Self.fileSizeFormatter.string(fromByteCount: row.item.fileSize))
        }
        if let stateText {
            components.append(stateText)
        }
        return components.joined(separator: "  ")
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

private struct VideoLibraryPosterArtworkView: View {
    let row: VideoLibraryRow
    let thumbnailScheduler: VideoThumbnailScheduler
    let requestMode: VideoThumbnailRequestMode
    let isHovered: Bool

    var body: some View {
        ZStack {
            VideoThumbnailImageView(
                item: row.item,
                remoteThumbnailURL: row.remoteThumbnailURL,
                parentFolder: row.item.parentFolder,
                scheduler: thumbnailScheduler,
                requestMode: requestMode,
                cornerRadius: 12
            )

            if isHovered {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.42), in: Circle())
                    .shadow(radius: 8, y: 3)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct VideoThumbnailImageView: View {
    let item: VideoLibraryItem
    let remoteThumbnailURL: URL?
    let parentFolder: String
    let scheduler: VideoThumbnailScheduler
    let requestMode: VideoThumbnailRequestMode
    let cornerRadius: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            VideoThumbnailPlaceholderView(parentFolder: parentFolder, cornerRadius: cornerRadius)

            if let remoteThumbnailURL {
                AsyncImage(url: remoteThumbnailURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            } else if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: thumbnailTaskID) {
            image = nil
            guard remoteThumbnailURL == nil, item.localURL != nil else { return }
            guard let url = await scheduler.thumbnailURL(
                for: item,
                requestMode: requestMode
            ) else {
                return
            }
            image = NSImage(contentsOf: url)
        }
    }

    private var thumbnailTaskID: String {
        "\(remoteThumbnailURL?.absoluteString ?? VideoThumbnailStore.cacheKey(for: item))-\(requestMode.taskIdentity)"
    }
}

private struct VideoThumbnailPlaceholderView: View {
    let parentFolder: String
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.16),
                            Color.secondary.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.7)
                }

            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(parentFolder)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
            }
        }
    }
}

private struct VideoLibraryBottomProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.primary.opacity(0.14))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * clampedProgress)
            }
        }
        .frame(height: 4)
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
}

private struct VideoLibraryRowView: View {
    let row: VideoLibraryRow
    let thumbnailScheduler: VideoThumbnailScheduler
    let onOpen: () -> Void
    let onOpenFromBeginning: () -> Void
    let onSelect: () -> Void
    let onMarkWatched: () -> Void
    let onClearProgress: () -> Void
    let onRemoveRemote: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    VideoThumbnailImageView(
                        item: row.item,
                        remoteThumbnailURL: row.remoteThumbnailURL,
                        parentFolder: row.item.parentFolder,
                        scheduler: thumbnailScheduler,
                        requestMode: .generateIfMissing,
                        cornerRadius: 8
                    )
                    .frame(width: 144, height: 81)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.displayTitle)
                            .lineLimit(1)
                            .font(.body.weight(.semibold))

                        HStack(spacing: 8) {
                            Text(row.sourceName)
                            if row.item.localURL != nil {
                                Text(row.item.parentFolder)
                                Text(Self.fileSizeFormatter.string(fromByteCount: row.item.fileSize))
                                if let modifiedAt = row.item.modifiedAt {
                                    Text(modifiedAt, style: .date)
                                }
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

            if let localURL = row.item.localURL {
                Divider()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([localURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "finder")
                }
            } else {
                Divider()

                Button(role: .destructive, action: onRemoveRemote) {
                    Label("Remove from Library", systemImage: "trash")
                }
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
                .help("Close")
                .accessibilityLabel(Text("Close"))
                .buttonStyle(VideoLibraryInspectorIconButtonStyle())
            }

            if let row = viewModel.selectedRow {
                ScrollView {
                    inspectorSections(row)
                }
                .scrollIndicators(.automatic)
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

    @ViewBuilder
    private func inspectorSections(_ row: VideoLibraryRow) -> some View {
        GlassEffectContainer(spacing: 12) {
            inspectorSectionStack(row)
        }
    }

    private func inspectorSectionStack(_ row: VideoLibraryRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            metadataSection(row)
            subtitleSection(row)
            collectionsSection(row)
            smartCollectionsSection(row)
            batchSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataSection(_ row: VideoLibraryRow) -> some View {
        VideoLibraryInspectorCard {
            TextField("Display Title", text: $titleDraft)
                .videoLibraryInspectorInput()

            Toggle("Favorite", isOn: Binding(
                get: { viewModel.selectedRow?.metadata.isFavorite ?? false },
                set: { isFavorite in
                    viewModel.setFavorite(isFavorite, for: row.item)
                }
            ))

            TextField("Tags", text: $tagsDraft)
                .videoLibraryInspectorInput()
                .help("Tags")

            Button {
                viewModel.setDisplayTitle(titleDraft, for: row.item)
                viewModel.setTags(Self.tags(from: tagsDraft), for: row.item)
                syncDrafts()
            } label: {
                Label("Save Metadata", systemImage: "checkmark")
            }
            .buttonStyle(VideoLibraryInspectorActionButtonStyle())
        }
    }

    private func subtitleSection(_ row: VideoLibraryRow) -> some View {
        VideoLibraryInspectorCard {
            Text("Bound Subtitle")
                .font(.subheadline.weight(.semibold))

            if let boundSubtitleURL = row.boundSubtitleURL {
                Text(boundSubtitleURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    viewModel.bindSubtitle(nil, for: row.item)
                } label: {
                    Label("Clear Subtitle", systemImage: "xmark.circle")
                }
                .buttonStyle(VideoLibraryInspectorActionButtonStyle())
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

            Button {
                isBindingSubtitle = true
            } label: {
                Label("Bind Subtitle", systemImage: "captions.bubble")
            }
            .buttonStyle(VideoLibraryInspectorActionButtonStyle())
        }
    }

    private func collectionsSection(_ row: VideoLibraryRow) -> some View {
        VideoLibraryInspectorCard {
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
                    .videoLibraryInspectorInput()

                Button {
                    _ = viewModel.createCollection(name: collectionNameDraft, items: [row.item])
                    collectionNameDraft = ""
                } label: {
                    Label("Add Collection", systemImage: "plus")
                }
                .buttonStyle(VideoLibraryInspectorActionButtonStyle())
                .disabled(collectionNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func smartCollectionsSection(_ row: VideoLibraryRow) -> some View {
        VideoLibraryInspectorCard {
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
                .videoLibraryInspectorInput()

            NativeGlassMenuPicker(
                selection: $smartCollectionRuleField,
                values: VideoLibrarySmartRuleField.smartCollectionEditorFields,
                minWidth: 132,
                fillsWidth: true
            ) { field in
                Text(LocalizedStringKey(field.smartCollectionTitleKey))
            }

            TextField("Rule Text", text: $smartCollectionRuleDraft)
                .videoLibraryInspectorInput()

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
            .buttonStyle(VideoLibraryInspectorActionButtonStyle())
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
        VideoLibraryInspectorCard {
            Button {
                viewModel.markSelectedWatched()
            } label: {
                Label("Mark Selected Watched", systemImage: "checkmark.circle")
            }
            .buttonStyle(VideoLibraryInspectorActionButtonStyle())

            Button {
                viewModel.clearSelectedProgress()
            } label: {
                Label("Clear Selected Progress", systemImage: "xmark.circle")
            }
            .buttonStyle(VideoLibraryInspectorActionButtonStyle())

            Button(role: .destructive) {
                _ = viewModel.removeMissingItems()
            } label: {
                Label("Remove Missing", systemImage: "trash")
            }
            .buttonStyle(VideoLibraryInspectorActionButtonStyle(role: .destructive))
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

private struct VideoLibraryInspectorCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .videoLibraryNeutralCardSurface(cornerRadius: 14)
    }
}

private struct VideoLibraryNeutralCardSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.035 : 0.34))
                    .overlay {
                        shape.strokeBorder(.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.7)
                    }
            }
            .clipShape(shape)
    }
}

private extension View {
    func videoLibraryNeutralCardSurface(cornerRadius: CGFloat) -> some View {
        modifier(VideoLibraryNeutralCardSurface(cornerRadius: cornerRadius))
    }
}

private struct VideoLibraryInspectorActionButtonStyle: ButtonStyle {
    enum Role {
        case standard
        case destructive
    }

    var role: Role = .standard
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .frame(minHeight: 30)
            .contentShape(Capsule())
            .modifier(
                VideoLibraryInspectorButtonSurface(
                    isPressed: configuration.isPressed,
                    isEnabled: isEnabled
                )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }

    private var foregroundStyle: Color {
        guard isEnabled else { return .secondary }
        switch role {
        case .standard:
            return .primary
        case .destructive:
            return .red
        }
    }
}

private struct VideoLibraryInspectorButtonSurface: ViewModifier {
    let isPressed: Bool
    let isEnabled: Bool
    @Environment(UserConfig.self) private var userConfig
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .opacity(isEnabled ? 1 : 0.56)
            .background {
                if isPressed {
                    Capsule()
                        .fill(NativeGlassPalette.cardTint(for: userConfig, colorScheme: colorScheme))
                }
            }
            .glassEffect(.regular.interactive(), in: Capsule())
    }
}

private struct VideoLibraryInspectorIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .secondary : .tertiary)
            .modifier(
                VideoLibraryInspectorIconButtonSurface(
                    isPressed: configuration.isPressed,
                    isEnabled: isEnabled
                )
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

private struct VideoLibraryInspectorIconButtonSurface: ViewModifier {
    let isPressed: Bool
    let isEnabled: Bool
    @Environment(UserConfig.self) private var userConfig
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .opacity(isEnabled ? 1 : 0.56)
            .background {
                if isPressed {
                    Circle()
                        .fill(NativeGlassPalette.cardTint(for: userConfig, colorScheme: colorScheme))
                }
            }
            .glassEffect(.regular.interactive(), in: Circle())
    }
}

private struct VideoLibraryInspectorInputSurface: ViewModifier {
    @Environment(UserConfig.self) private var userConfig
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(NativeGlassPalette.cardTint(for: userConfig, colorScheme: colorScheme))
                    }
                    .overlay {
                        shape.strokeBorder(NativeGlassPalette.stroke(for: colorScheme), lineWidth: 0.7)
                    }
            }
            .clipShape(shape)
            .nativeGlassInspectorInputEffect()
    }
}

private extension View {
    func videoLibraryInspectorInput() -> some View {
        modifier(VideoLibraryInspectorInputSurface())
    }

    @ViewBuilder
    func nativeGlassInspectorInputEffect() -> some View {
        self.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
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
