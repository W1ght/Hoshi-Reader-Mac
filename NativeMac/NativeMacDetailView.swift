import SwiftUI

struct NativeMacDetailView: View {
    let section: NativeMacSection
    @Binding var selectedReaderBook: BookMetadata?
    @Binding var pendingImportURL: URL?
    @Binding var pendingRemoteImportURL: URL?
    let dictionaryRequest: NativeDictionaryOpenRequest?

    var body: some View {
        ZStack {
            #if HOSHI_VIDEO
            VideoPlayerScreen(isActive: section == .video)
                .opacity(section == .video ? 1 : 0)
                .allowsHitTesting(section == .video)
                .accessibilityHidden(section != .video)
            #endif

            #if HOSHI_VIDEO
            if section != .video {
                selectedNonVideoContent
            }
            #else
            selectedNonVideoContent
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(section.title)
    }

    @ViewBuilder
    private var selectedNonVideoContent: some View {
        Group {
            switch section {
            case .bookshelf:
                NativeBookshelfPlaceholderView(
                    selectedReaderBook: $selectedReaderBook,
                    pendingImportURL: $pendingImportURL,
                    pendingRemoteImportURL: $pendingRemoteImportURL
                )
            case .dictionary:
                NativeDictionaryPlaceholderView(request: dictionaryRequest)
            #if HOSHI_VIDEO
            case .video:
                EmptyView()
            #endif
            case .settings:
                NativeSettingsPlaceholderView()
            }
        }
    }
}
