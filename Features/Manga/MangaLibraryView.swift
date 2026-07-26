import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MangaLibraryView: View {
    let onOpenManga: (MangaLibraryItem, MangaLibrarySource) -> Void

    @Bindable var viewModel: MangaLibraryViewModel
    @State private var isSelecting = false
    @State private var selectedItems = Set<MangaLibraryItem>()
    @State private var showBulkRemoveConfirmation = false
    @State private var showShelfManagement = false

    var body: some View {
        libraryContent
        .toolbar {
            toolbarContent
        }
        .overlay {
            if viewModel.isScanning {
                ProgressView("Updating Manga Library...")
                    .controlSize(.large)
                    .padding(24)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
        }
        .alert("Error", isPresented: $viewModel.shouldShowError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert(
            "Remove \(selectedItems.count) manga from the library?",
            isPresented: $showBulkRemoveConfirmation
        ) {
            Button("Remove from Library", role: .destructive) {
                viewModel.removeItemsFromLibrary(selectedItems)
                clearSelection()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original manga files will not be deleted.")
        }
        .sheet(isPresented: $showShelfManagement) {
            MangaShelfManagementView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.load()
        }
        .onDisappear {
            viewModel.cancelScanning()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: MangaLibraryStore.didChangeNotification)
        ) { _ in
            viewModel.load()
        }
        .onChange(of: isSelecting) {
            if !isSelecting {
                selectedItems.removeAll()
            }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if !viewModel.hasLoadedCatalog {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        } else if viewModel.catalog.sources.isEmpty {
            ContentUnavailableView {
                Label("No Manga", systemImage: "books.vertical")
            } description: {
                Text("Add a local folder, CBZ, ZIP, or EPUB file to start reading.")
            } actions: {
                Button("Import Manga", systemImage: "plus") {
                    presentMangaImporter()
                }
                .buttonStyle(.glassProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.visibleItems.isEmpty {
            ContentUnavailableView {
                Label("No Manga in Library", systemImage: "books.vertical")
            } description: {
                Text("Import a manga source again to restore items removed from the library.")
            } actions: {
                Button("Import Manga", systemImage: "plus") {
                    presentMangaImporter()
                }
                .buttonStyle(.glassProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let sections = viewModel.sections()
            ScrollView {
                ForEach(sections) { section in
                    if !section.items.isEmpty {
                        MangaShelfView(
                            viewModel: viewModel,
                            section: section,
                            showTitle: true,
                            isSelecting: isSelecting,
                            selectedItems: $selectedItems,
                            onOpen: openManga
                        )
                    }
                }
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.hasLoadedCatalog {
            if isSelecting {
                ToolbarItem(placement: .navigation) {
                    Button("Done") {
                        clearSelection()
                    }
                    .fontWeight(.semibold)
                }

                ToolbarItem(placement: .primaryAction) {
                    mangaMoveMenu(items: selectedItems)
                        .disabled(selectedItems.isEmpty)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showBulkRemoveConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedItems.isEmpty)
                }
            } else {
                ToolbarItem(placement: .navigation) {
                    Menu {
                        Section {
                            Text("Sorting by...")
                                .foregroundStyle(.secondary)
                            @Bindable var viewModel = viewModel
                            Picker("Sort", selection: $viewModel.sortOption) {
                                ForEach(MangaLibrarySortOption.allCases) { option in
                                    Label(
                                        String(localized: String.LocalizationValue(option.titleKey)),
                                        systemImage: option.icon
                                    )
                                    .tag(option)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }

                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation(.default.speed(2)) {
                            isSelecting = true
                        }
                    } label: {
                        Image(systemName: "checklist")
                    }
                    .disabled(viewModel.visibleItems.isEmpty)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showShelfManagement = true
                    } label: {
                        Image(systemName: "folder.badge.gearshape")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentMangaImporter()
                    } label: {
                        Label("Import Manga", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func openManga(_ item: MangaLibraryItem) {
        guard let source = viewModel.source(for: item) else { return }
        viewModel.recordOpened(item)
        onOpenManga(item, source)
    }

    private func clearSelection() {
        withAnimation(.default.speed(2)) {
            isSelecting = false
            selectedItems.removeAll()
        }
    }

    private func mangaMoveMenu(items: Set<MangaLibraryItem>) -> some View {
        Menu {
            Button {
                viewModel.moveItems(items, to: nil)
                clearSelection()
            } label: {
                Label("None", systemImage: "tray")
            }
            ForEach(viewModel.catalog.shelves) { shelf in
                Button {
                    viewModel.moveItems(items, to: shelf.id)
                    clearSelection()
                } label: {
                    Label(shelf.name, systemImage: "folder")
                }
            }
        } label: {
            Image(systemName: "folder")
        }
    }

    private func presentMangaImporter() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.allowedContentTypes = MangaMediaTypes.importContentTypes
        panel.message = String(
            localized: "Choose a folder, CBZ, ZIP, or EPUB file."
        )
        panel.prompt = String(localized: "Import")
        guard panel.runModal() == .OK else { return }
        viewModel.addSources(panel.urls)
    }
}

private struct MangaShelfView: View {
    let viewModel: MangaLibraryViewModel
    let section: MangaShelfSection
    let showTitle: Bool
    let isSelecting: Bool
    @Binding var selectedItems: Set<MangaLibraryItem>
    let onOpen: (MangaLibraryItem) -> Void

    @State private var isCollapsed: Bool
    @State private var compactRowCount = 4
    @State private var itemFrames: [String: CGRect] = [:]
    @State private var activeDragSourceID: String?
    @State private var activeDragTargetID: String?

    private let dragReorderAnimation: Animation = .smooth(duration: 0.22)
    private let dragEndAnimation: Animation = .easeOut(duration: 0.16)

    init(
        viewModel: MangaLibraryViewModel,
        section: MangaShelfSection,
        showTitle: Bool,
        isSelecting: Bool,
        selectedItems: Binding<Set<MangaLibraryItem>>,
        onOpen: @escaping (MangaLibraryItem) -> Void
    ) {
        self.viewModel = viewModel
        self.section = section
        self.showTitle = showTitle
        self.isSelecting = isSelecting
        self._selectedItems = selectedItems
        self.onOpen = onOpen
        self._isCollapsed = State(initialValue: !section.isReading)
    }

    private var columns: [GridItem] {
        [GridItem(
            .adaptive(
                minimum: BookshelfLayout.v050CoverWidth,
                maximum: BookshelfLayout.v050CoverWidth
            ),
            spacing: BookshelfLayout.columnSpacing
        )]
    }

    private var compactColumns: [GridItem] {
        [GridItem(
            .adaptive(minimum: BookshelfLayout.compactCoverWidth),
            spacing: BookshelfLayout.compactColumnSpacing
        )]
    }

    private var coordinateSpaceName: String {
        "manga-shelf-\(section.id)"
    }

    var body: some View {
        VStack {
            if showTitle {
                ShelfSectionHeader(
                    title: section.isReading
                        ? String(localized: "Reading")
                        : section.shelf?.name ?? String(localized: "Unshelved"),
                    count: section.items.count,
                    isCollapsible: section.shelf != nil,
                    isCollapsed: $isCollapsed
                )
            }

            if isCollapsed, section.shelf != nil {
                compactCollapsedGrid
            } else {
                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: BookshelfLayout.rowSpacing
                ) {
                    ForEach(section.items) { item in
                        let cell = MangaLibraryItemCell(
                            item: item,
                            viewModel: viewModel,
                            currentShelfID: section.shelf?.id,
                            hideMove: section.isReading,
                            onOpen: { onOpen(item) },
                            isSelecting: isSelecting,
                            selectedItems: $selectedItems,
                            dragCoordinateSpaceName: section.isReading ? nil : coordinateSpaceName,
                            onDragChanged: section.isReading ? nil : { location in
                                reorderItem(item.id, draggedTo: location)
                            },
                            onDragEnded: section.isReading ? nil : { location in
                                reorderItem(item.id, draggedTo: location)
                                endDrag()
                            }
                        )

                        if section.isReading {
                            cell
                        } else {
                            cell
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: MangaItemFramePreferenceKey.self,
                                            value: [
                                                item.id: proxy.frame(
                                                    in: .named(coordinateSpaceName)
                                                ),
                                            ]
                                        )
                                    }
                                }
                                .contentShape(Rectangle())
                                .shelfDragAppearance(dragVisualState(for: item.id))
                        }
                    }
                }
                .padding(.horizontal)
                .coordinateSpace(name: coordinateSpaceName)
                .onPreferenceChange(MangaItemFramePreferenceKey.self) { frames in
                    itemFrames = frames
                }
            }
        }
    }

    private var compactCollapsedGrid: some View {
        LazyVGrid(columns: compactColumns, spacing: BookshelfLayout.compactColumnSpacing) {
            ForEach(section.items.prefix(compactRowCount)) { item in
                Button {
                    withAnimation(.default.speed(1.5)) {
                        isCollapsed = false
                    }
                } label: {
                    ShelfCoverFrame(width: BookshelfLayout.compactCoverWidth) {
                        MangaCoverImage(path: item.coverCachePath)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onGeometryChange(for: Int.self) { proxy in
            max(
                1,
                Int(
                    (proxy.size.width + BookshelfLayout.compactColumnSpacing)
                        / (BookshelfLayout.compactCoverWidth + BookshelfLayout.compactColumnSpacing)
                )
            )
        } action: { count in
            compactRowCount = count
        }
        .padding(.horizontal)
    }

    private func reorderItem(_ sourceID: String, draggedTo location: CGPoint) {
        guard !section.isReading else { return }
        beginDragIfNeeded(sourceID)
        guard let targetID = itemFrames.first(where: { id, frame in
            id != sourceID && frame.insetBy(dx: -8, dy: -8).contains(location)
        })?.key,
              activeDragTargetID != targetID else {
            return
        }
        withAnimation(dragReorderAnimation) {
            viewModel.reorderItem(sourceID, in: section, before: targetID)
            activeDragTargetID = targetID
        }
    }

    private func beginDragIfNeeded(_ sourceID: String) {
        guard activeDragSourceID != sourceID else { return }
        withAnimation(dragReorderAnimation) {
            activeDragSourceID = sourceID
            activeDragTargetID = nil
        }
    }

    private func endDrag() {
        withAnimation(dragEndAnimation) {
            activeDragSourceID = nil
            activeDragTargetID = nil
        }
    }

    private func dragVisualState(for itemID: String) -> ShelfDragVisualState {
        if activeDragSourceID == itemID {
            return .source
        }
        if activeDragTargetID == itemID {
            return .target
        }
        return .inactive
    }
}

private struct MangaLibraryItemCell: View {
    let item: MangaLibraryItem
    let viewModel: MangaLibraryViewModel
    let currentShelfID: UUID?
    let hideMove: Bool
    let onOpen: () -> Void
    let isSelecting: Bool
    @Binding var selectedItems: Set<MangaLibraryItem>
    let dragCoordinateSpaceName: String?
    let onDragChanged: ((CGPoint) -> Void)?
    let onDragEnded: ((CGPoint) -> Void)?

    @State private var showRemoveConfirmation = false
    @State private var showMarkReadConfirmation = false
    @State private var renameDraft: MangaRenameDraft?

    private var isSelected: Bool {
        selectedItems.contains(item)
    }

    var body: some View {
        Button {
            if isSelecting {
                withAnimation(.default.speed(2)) {
                    if isSelected {
                        selectedItems.remove(item)
                    } else {
                        selectedItems.insert(item)
                    }
                }
            } else {
                onOpen()
            }
        } label: {
            labelContent
        }
        .buttonStyle(.plain)
        .contextMenu(isSelecting ? nil : ContextMenu {
            if !hideMove {
                Menu {
                    Button {
                        viewModel.moveItem(item, to: nil)
                    } label: {
                        Label("None", systemImage: "tray")
                    }
                    .disabled(currentShelfID == nil)

                    ForEach(viewModel.catalog.shelves) { shelf in
                        Button {
                            viewModel.moveItem(item, to: shelf.id)
                        } label: {
                            Label(shelf.name, systemImage: "folder")
                        }
                        .disabled(currentShelfID == shelf.id)
                    }
                } label: {
                    Label("Move", systemImage: "folder")
                }
            }

            Button {
                showMarkReadConfirmation = true
            } label: {
                Label("Mark Read", systemImage: "checkmark")
            }

            Button {
                renameDraft = MangaRenameDraft(item: item, title: item.displayTitle)
            } label: {
                Label("Rename", systemImage: "character.cursor.ibeam.ja")
            }

            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                Label("Remove from Library", systemImage: "trash")
            }
        })
        .sheet(item: $renameDraft) { _ in
            MangaRenameSheet(
                title: Binding(
                    get: { renameDraft?.title ?? "" },
                    set: { renameDraft?.title = $0 }
                ),
                onSave: saveRename,
                onCancel: { renameDraft = nil }
            )
        }
        .confirmationDialog(
            "Remove \"\(item.displayTitle)\" from the library?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from Library", role: .destructive) {
                viewModel.removeItemsFromLibrary([item])
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The original manga files will not be deleted.")
        }
        .confirmationDialog(
            "Mark \"\(item.displayTitle)\" as read?",
            isPresented: $showMarkReadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Confirm") {
                viewModel.markRead(item)
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityLabel(item.displayTitle)
        .accessibilityValue("\(item.pageCount) pages")
    }

    @ViewBuilder
    private var labelContent: some View {
        let content = ShelfBookCard(
            title: item.displayTitle,
            progress: item.progress,
            isSelected: isSelecting && isSelected
        ) {
            MangaCoverImage(path: item.coverCachePath)
        }

        if let dragCoordinateSpaceName,
           let onDragChanged,
           let onDragEnded {
            content
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(
                        minimumDistance: 8,
                        coordinateSpace: .named(dragCoordinateSpaceName)
                    )
                    .onChanged { value in
                        onDragChanged(value.location)
                    }
                    .onEnded { value in
                        onDragEnded(value.location)
                    }
                )
        } else {
            content
        }
    }

    private func saveRename() {
        guard let renameDraft else { return }
        viewModel.renameItem(renameDraft.item, title: renameDraft.title)
        self.renameDraft = nil
    }
}

private struct MangaCoverImage: View {
    let path: String?

    var body: some View {
        CoverImage(
            url: path.map(URL.init(fileURLWithPath:)),
            maxPixelSize: 768
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "book.closed")
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(0.709, contentMode: .fit)
        .clipped()
    }
}

private struct MangaShelfManagementView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: MangaLibraryViewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        NativeReaderSheetPanel("Manage Manga Shelves", onClose: {
            dismiss()
        }) {
            ShelfManagementForm(
                showReading: $viewModel.showReading,
                shelves: viewModel.catalog.shelves.map {
                    ShelfManagementEntry(id: $0.id.uuidString, name: $0.name)
                },
                onCreate: viewModel.createShelf,
                onDelete: { id in
                    guard let shelfID = UUID(uuidString: id) else { return }
                    viewModel.deleteShelf(id: shelfID)
                },
                onMove: viewModel.moveShelves
            )
        }
        .frame(
            width: ShelfManagementLayout.panelWidth,
            height: ShelfManagementLayout.panelHeight
        )
    }
}

private struct MangaRenameDraft: Identifiable {
    let id = UUID()
    let item: MangaLibraryItem
    var title: String
}

private struct MangaRenameSheet: View {
    @Binding var title: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Rename")
                .font(.title2.bold())
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct MangaItemFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}
