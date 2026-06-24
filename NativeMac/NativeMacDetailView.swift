import SwiftUI

struct NativeMacDetailView: View {
    let section: NativeMacSection
    @Binding var selectedReaderBook: BookMetadata?
    @Binding var pendingImportURL: URL?
    @Binding var pendingRemoteImportURL: URL?
    let dictionaryRequest: NativeDictionaryOpenRequest?
    #if HOSHI_VIDEO
    let onOpenVideo: (URL) -> Void
    #endif

    var body: some View {
        selectedContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(section.title)
    }

    @ViewBuilder
    private var selectedContent: some View {
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
                VideoLibraryView(onOpenVideo: onOpenVideo)
            #endif
            case .settings:
                NativeSettingsPlaceholderView()
            }
        }
    }
}
