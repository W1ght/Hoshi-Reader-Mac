import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NativeBookshelfReuseView: View {
    @Environment(UserConfig.self) private var userConfig
    @Binding var selectedReaderBook: BookMetadata?
    @Binding var pendingImportURL: URL?
    @Binding var pendingRemoteImportURL: URL?
    @State private var viewModel = BookshelfViewModel()
    @State private var showShelfManagement = false
    @State private var isSelecting = false
    @State private var selectedBooks = Set<BookMetadata>()
    @State private var showBulkDeleteConfirmation = false
    @State private var pendingLookup: String?
    @State private var pendingTab: Int?
    @State private var sasayakiBook: BookMetadata?

    var body: some View {
        bookshelfContent
        .onChange(of: pendingTab) { _, tab in
            guard let tab else { return }
            switch tab {
            case 1, 2:
                selectedReaderBook = nil
            default:
                break
            }
            pendingTab = nil
        }
        .onChange(of: selectedReaderBook) { oldBook, newBook in
            guard oldBook != nil, newBook == nil else { return }
            viewModel.loadBooks()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bookshelfContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            let sections = viewModel.shelfSections(
                sortedBy: userConfig.bookshelfSortOption,
                showReading: userConfig.bookshelfShowReading
            )

            if viewModel.books.isEmpty && viewModel.googleDriveBooks.isEmpty {
                ContentUnavailableView {
                    Label("No Books", systemImage: "books.vertical")
                } description: {
                    Text("Import an EPUB using the toolbar button to start reading.")
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                ScrollView {
                    NativeBookshelfSectionsView(
                        viewModel: viewModel,
                        sections: sections,
                        isSelecting: isSelecting,
                        selectedBooks: $selectedBooks,
                        pendingLookup: $pendingLookup,
                        pendingTab: $pendingTab,
                        selectedReaderBook: $selectedReaderBook,
                        sasayakiBook: $sasayakiBook
                    )
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar {
            toolbarContent
        }
        .fileImporter(
            isPresented: $viewModel.isImporting,
            allowedContentTypes: [.epub],
            allowsMultipleSelection: true,
            onCompletion: viewModel.importBooks
        )
        .sheet(isPresented: $showShelfManagement) {
            ShelfManagementView(viewModel: viewModel)
        }
        .sheet(item: $sasayakiBook) { book in
            SasayakiMatchView(book: book, viewModel: viewModel)
        }
        .alert(
            "Delete \(selectedBooks.count) book(s)?",
            isPresented: $showBulkDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteBooks(selectedBooks)
                clearSelection()
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Error", isPresented: $viewModel.shouldShowError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Done", isPresented: $viewModel.shouldShowSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.successMessage)
        }
        .overlay {
            if viewModel.isSyncing {
                LoadingOverlay(String(localized: "Syncing..."))
            }
            if viewModel.isDownloading {
                LoadingOverlay(String(localized: "Downloading EPUB..."))
            }
            if let importBooksProgress = viewModel.importBooksProgress {
                LoadingOverlay(importBooksProgress)
            }
            if viewModel.isLoadingGoogleDriveBooks {
                LoadingOverlay(String(localized: "Loading Google Drive Books..."))
            }
        }
        .onAppear {
            viewModel.loadBooks()
        }
        .onChange(of: pendingImportURL, initial: true) { _, url in
            guard let url else { return }
            if ["colpkg", "apkg"].contains(url.pathExtension.lowercased()) {
                do {
                    try AnkiManager.shared.importAnkiBackup(from: url)
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.shouldShowError = true
                }
            } else {
                viewModel.importBook(result: .success(url))
            }
            viewModel.clearInbox()
            pendingImportURL = nil
        }
        .onChange(of: pendingRemoteImportURL, initial: true) { _, url in
            guard let url else { return }
            viewModel.importRemoteBook(from: url)
            pendingRemoteImportURL = nil
        }
        .onChange(of: isSelecting) { _, selecting in
            if !selecting {
                selectedBooks.removeAll()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    clearSelection()
                }
                .fontWeight(.semibold)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        viewModel.moveBooks(selectedBooks, to: nil)
                        clearSelection()
                    } label: {
                        Label("None", systemImage: "tray")
                    }
                    ForEach(viewModel.shelves, id: \.name) { shelf in
                        Button {
                            viewModel.moveBooks(selectedBooks, to: shelf.name)
                            clearSelection()
                        } label: {
                            Label(shelf.name, systemImage: "folder")
                        }
                    }
                } label: {
                    Label("Move to Shelf", systemImage: "folder")
                }
                .disabled(selectedBooks.isEmpty)

                Button(role: .destructive) {
                    showBulkDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedBooks.isEmpty)
            }
        } else {
            ToolbarItemGroup(placement: .navigation) {
                Menu {
                    Picker("Sort", selection: Bindable(userConfig).bookshelfSortOption) {
                        ForEach(SortOption.allCases) { option in
                            label(for: option)
                                .tag(option)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort Books")

                Button {
                    withAnimation(.default.speed(2)) {
                        isSelecting = true
                    }
                } label: {
                    Label("Select Books", systemImage: "checklist")
                }
                .help("Select Books")
            }

            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if userConfig.enableSync && GoogleDriveAuth.shared.isAuthenticated {
                    Button {
                        Task {
                            await viewModel.loadGoogleDriveBooks()
                        }
                    } label: {
                        if viewModel.isLoadingGoogleDriveBooks {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh Google Drive Books", systemImage: "icloud.and.arrow.down")
                        }
                    }
                    .disabled(viewModel.isLoadingGoogleDriveBooks)
                    .help("Refresh Google Drive Books")
                }

                Button {
                    showShelfManagement = true
                } label: {
                    Label("Manage Shelves", systemImage: "folder.badge.gearshape")
                }
                .help("Manage Shelves")

                Button {
                    viewModel.isImporting = true
                } label: {
                    Label("Import EPUB", systemImage: "plus")
                }
                .help("Import EPUB")
            }
        }
    }

    private func clearSelection() {
        withAnimation(.default.speed(2)) {
            isSelecting = false
            selectedBooks.removeAll()
        }
    }

    private func label(for sortOption: SortOption) -> some View {
        switch sortOption {
        case .recent:
            Label(LocalizedStringKey("Sort Option Recent"), systemImage: sortOption.icon)
        case .title:
            Label(LocalizedStringKey("Sort Option Title"), systemImage: sortOption.icon)
        }
    }
}

private struct NativeBookshelfSectionsView: View {
    let viewModel: BookshelfViewModel
    let sections: [ShelfSection]
    let isSelecting: Bool
    @Binding var selectedBooks: Set<BookMetadata>
    @Binding var pendingLookup: String?
    @Binding var pendingTab: Int?
    @Binding var selectedReaderBook: BookMetadata?
    @Binding var sasayakiBook: BookMetadata?

    var body: some View {
        VStack(spacing: 26) {
            ForEach(sections) { section in
                if !section.books.isEmpty {
                    ShelfView(
                        viewModel: viewModel,
                        section: section,
                        showTitle: sections.count > 1,
                        isSelecting: isSelecting,
                        selectedBooks: $selectedBooks,
                        pendingLookup: $pendingLookup,
                        pendingTab: $pendingTab,
                        selectedReaderBook: $selectedReaderBook,
                        onMatch: { sasayakiBook = $0 }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct NativeDictionaryReuseView: View {
    let request: NativeDictionaryOpenRequest?

    var body: some View {
        DictionarySearchView(
            initialQuery: request?.query ?? "",
            initialAutofocus: false,
            shouldFocus: false
        )
        .id(request?.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NativeSettingsReuseView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var selection: NativeSettingsSection? = .appearance

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 240)
                .background(.thinMaterial)

            Divider()

            NativeSettingsDetailView(section: selection ?? .appearance, userConfig: userConfig)
                .id(selection ?? .appearance)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(selection?.title ?? "Settings")
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
        }
    }

    private var settingsSidebar: some View {
        List(selection: $selection) {
            Section("Library") {
                nativeSettingsRow(.profiles)
                nativeSettingsRow(.appearance)
                nativeSettingsRow(.dictionaries)
                nativeSettingsRow(.anki)
            }

            Section("Reader") {
                nativeSettingsRow(.audio)
                nativeSettingsRow(.statistics)
                nativeSettingsRow(.sasayaki)
            }

            #if HOSHI_VIDEO
            Section("Video") {
                nativeSettingsRow(.video)
            }
            #endif

            Section("Shortcuts & Controls") {
                nativeSettingsRow(.keyboardShortcuts)
                nativeSettingsRow(.gameController)
            }

            Section("Sync & Data") {
                nativeSettingsRow(.sync)
                nativeSettingsRow(.backup)
            }

            Section {
                nativeSettingsRow(.about)

                Link(destination: URL(string: "https://github.com/W1ght/Hoshi-Reader-for-Mac/issues")!) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }
                .foregroundStyle(.primary)
            }
        }
        .listStyle(.sidebar)
    }

    private func nativeSettingsRow(_ section: NativeSettingsSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
    }
}

enum NativeSettingsSection: String, CaseIterable, Identifiable {
    case profiles
    case appearance
    case dictionaries
    case anki
    case audio
    case statistics
    case sasayaki
    #if HOSHI_VIDEO
    case video
    #endif
    case keyboardShortcuts
    case gameController
    case sync
    case backup
    case about

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .profiles:
            "Profiles"
        case .appearance:
            "Appearance"
        case .dictionaries:
            "Dictionaries"
        case .anki:
            "Anki"
        case .audio:
            "Audio"
        case .statistics:
            "Statistics"
        case .sasayaki:
            "Sasayaki (Audiobooks)"
        #if HOSHI_VIDEO
        case .video:
            "Video"
        #endif
        case .keyboardShortcuts:
            "Keyboard Shortcuts"
        case .gameController:
            "Game Controller"
        case .sync:
            "ッツ Sync"
        case .backup:
            "Backup"
        case .about:
            "About"
        }
    }

    var systemImage: String {
        switch self {
        case .profiles:
            "person.crop.circle.badge.checkmark"
        case .appearance:
            "paintpalette"
        case .dictionaries:
            "character.book.closed.ja"
        case .anki:
            "tray.full"
        case .audio:
            "speaker.wave.2"
        case .statistics:
            "chart.xyaxis.line"
        case .sasayaki:
            "waveform"
        #if HOSHI_VIDEO
        case .video:
            "play.rectangle"
        #endif
        case .keyboardShortcuts:
            "keyboard"
        case .gameController:
            "gamecontroller"
        case .sync:
            "cloud"
        case .backup:
            "externaldrive"
        case .about:
            "info.circle"
        }
    }
}

struct NativeGlassSegmentedPicker<SelectionValue: Hashable, SegmentLabel: View>: View {
    @Binding var selection: SelectionValue
    let values: [SelectionValue]
    var minSegmentWidth: CGFloat = 76
    var fillsWidth = false
    @ViewBuilder var label: (SelectionValue) -> SegmentLabel
    @Namespace private var selectedSegmentNamespace

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                segmentedContent
            }
        } else {
            segmentedContent
        }
    }

    private var segmentedContent: some View {
        HStack(spacing: 0) {
            ForEach(Array(values.enumerated()), id: \.element) { index, value in
                segmentButton(value)
                    .layoutPriority(selection == value ? 1 : 0)

                if index < values.count - 1 {
                    Divider()
                        .frame(height: 16)
                        .padding(.vertical, 3)
                        .opacity(selection == value || selection == values[index + 1] ? 0 : 0.42)
                }
            }
        }
        .padding(2)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(.quaternary.opacity(0.58), lineWidth: 0.7)
                }
        }
        .nativeGlassSegmentContainer()
        .shadow(color: .black.opacity(0.045), radius: 7, x: 0, y: 2)
        .animation(.smooth(duration: 0.20), value: selection)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .fixedSize(horizontal: !fillsWidth, vertical: true)
    }

    private func segmentButton(_ value: SelectionValue) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                selection = value
            }
        } label: {
            label(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: minSegmentWidth, maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(selection == value ? .primary : .secondary)
        .background {
            if selection == value {
                Capsule()
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.30), lineWidth: 0.65)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
                    .matchedGeometryEffect(id: "native-glass-segment", in: selectedSegmentNamespace)
                    .nativeGlassSelectedSegment()
                    .transition(.identity)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func nativeGlassSegmentContainer() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self
        }
    }

    @ViewBuilder
    func nativeGlassSelectedSegment() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self
        }
    }
}

struct NativeSettingsDetailView: View {
    let section: NativeSettingsSection
    let userConfig: UserConfig
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .toggleStyle(.switch)
            .listStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .background(NativeSettingsPalette.pageBackground(colorScheme))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .profiles:
            ProfilesView()
        case .appearance:
            AppearanceView(userConfig: userConfig, showDismiss: false)
        case .dictionaries:
            DictionaryView()
        case .anki:
            AnkiView()
        case .audio:
            AudioView()
        case .statistics:
            StatisticsSettingsView()
        case .sasayaki:
            SasayakiSettingsView()
        #if HOSHI_VIDEO
        case .video:
            VideoSettingsView()
        #endif
        case .keyboardShortcuts:
            KeyboardShortcutsView()
        case .gameController:
            XboxControllerView()
        case .sync:
            SyncView()
        case .backup:
            BackupView()
        case .about:
            AboutView()
        }
    }
}

enum NativeSettingsPalette {
    static func pageBackground(_ colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            Color(nsColor: NSColor(calibratedWhite: 0.095, alpha: 1))
        } else {
            Color(nsColor: NSColor(calibratedWhite: 0.92, alpha: 1))
        }
    }

    static func cardBackground(_ colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            Color(nsColor: NSColor(calibratedWhite: 0.145, alpha: 1))
        } else {
            Color(nsColor: .textBackgroundColor)
        }
    }

    static func separator(_ colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            Color.white.opacity(0.105)
        } else {
            Color(nsColor: .separatorColor).opacity(0.42)
        }
    }
}

struct NativeSettingsForm<Content: View>: View {
    var horizontalPadding: CGFloat = 24
    var verticalPadding: CGFloat = 18
    var spacing: CGFloat = 22
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - horizontalPadding * 2, 0)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: spacing) {
                    content()
                }
                .frame(width: contentWidth, alignment: .topLeading)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
            }
            .scrollIndicators(.automatic)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NativeSettingsPalette.pageBackground(colorScheme))
    }
}

struct NativeSettingsSectionCard<Header: View, Content: View, Footer: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @Environment(\.colorScheme) private var colorScheme

    init(
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.header = header
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header()
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NativeSettingsPalette.cardBackground(colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.quaternary.opacity(0.65), lineWidth: 0.7)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .nativeSettingsCardGlass()

            footer()
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

extension NativeSettingsSectionCard where Header == Text, Footer == EmptyView {
    init(_ title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.init {
            Text(title)
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }
}

extension NativeSettingsSectionCard where Header == Text {
    init(
        _ title: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.init {
            Text(title)
        } content: {
            content()
        } footer: {
            footer()
        }
    }
}

extension NativeSettingsSectionCard where Header == Text, Footer == Text {
    init(
        _ title: LocalizedStringKey,
        footer: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init {
            Text(title)
        } content: {
            content()
        } footer: {
            Text(footer)
        }
    }
}

struct NativeSettingsRow<Label: View, Accessory: View>: View {
    @ViewBuilder var label: () -> Label
    @ViewBuilder var accessory: () -> Accessory

    init(
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.label = label
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 12) {
            label()
                .font(.body.weight(.medium))
            Spacer(minLength: 20)
            accessory()
        }
        .frame(minHeight: 46)
        .padding(.horizontal, 16)
    }
}

/// Keeps Settings row layout in SwiftUI while using AppKit's stable pasteboard
/// destination path. SwiftUI row-level drop destinations inside the custom
/// Settings scroll container do not consistently commit drops on macOS 26.
struct NativeSettingsReorderRow<Content: View>: NSViewRepresentable {
    @Binding private var isTargeted: Bool
    private let onDrop: (String) -> Bool
    private let content: Content

    init(
        isTargeted: Binding<Bool>,
        onDrop: @escaping (String) -> Bool,
        @ViewBuilder content: () -> Content
    ) {
        _isTargeted = isTargeted
        self.onDrop = onDrop
        self.content = content()
    }

    func makeNSView(context: Context) -> NativeSettingsReorderHostingView {
        NativeSettingsReorderHostingView(
            rootView: AnyView(content),
            onTargetedChanged: { isTargeted = $0 },
            onDrop: onDrop
        )
    }

    func updateNSView(_ nsView: NativeSettingsReorderHostingView, context: Context) {
        nsView.rootView = AnyView(content)
        nsView.onTargetedChanged = { isTargeted = $0 }
        nsView.onDrop = onDrop
    }
}

final class NativeSettingsReorderHostingView: NSHostingView<AnyView> {
    var onTargetedChanged: (Bool) -> Void
    var onDrop: (String) -> Bool

    init(
        rootView: AnyView,
        onTargetedChanged: @escaping (Bool) -> Void,
        onDrop: @escaping (String) -> Bool
    ) {
        self.onTargetedChanged = onTargetedChanged
        self.onDrop = onDrop
        super.init(rootView: rootView)
        registerForDraggedTypes([.string])
    }

    @available(*, unavailable)
    required init(rootView: AnyView) {
        fatalError("init(rootView:) has not been implemented")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.string(forType: .string) != nil else {
            return []
        }
        onTargetedChanged(true)
        return .move
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.string(forType: .string) == nil ? [] : .move
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onTargetedChanged(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { onTargetedChanged(false) }
        guard let payload = sender.draggingPasteboard.string(forType: .string) else {
            return false
        }
        return onDrop(payload)
    }
}

extension NativeSettingsRow where Label == Text {
    init(_ title: LocalizedStringKey, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init {
            Text(title)
        } accessory: {
            accessory()
        }
    }
}

struct NativeSettingsToggle: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        NativeSettingsRow(title) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct NativeSettingsButtonRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack {
            content()
            Spacer()
        }
        .frame(minHeight: 46)
        .padding(.horizontal, 16)
    }
}

struct NativeSettingsSliderRow<SliderContent: View>: View {
    let title: LocalizedStringKey
    let value: String
    @ViewBuilder var slider: () -> SliderContent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                Text(value)
                    .fontWeight(.semibold)
            }
            slider()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct NativeSettingsValuePill<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(.body.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
    }
}

struct NativeGlassCircleButton: View {
    let systemName: String
    var diameter: CGFloat = 38
    var fontSize: CGFloat = 16
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.12), radius: 9, x: 0, y: 3)
        }
        .nativeGlassCircleButton()
    }
}

private extension View {
    @ViewBuilder
    func nativeSettingsCardGlass() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            self
        }
    }

    @ViewBuilder
    func nativeGlassCircleButton() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self
        }
    }
}

struct NativeSettingsSeparator: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Divider()
            .overlay(NativeSettingsPalette.separator(colorScheme))
            .padding(.leading, 16)
    }
}
