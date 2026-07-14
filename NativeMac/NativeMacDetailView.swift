import SwiftUI

struct NativeMacDetailView: View {
    let section: NativeMacSection
    let onOpenBook: (BookMetadata) -> Void
    @Binding var pendingImportURL: URL?
    @Binding var pendingRemoteImportURL: URL?
    let dictionaryRequest: NativeDictionaryOpenRequest?
    #if HOSHI_VIDEO
    let onOpenVideo: (VideoPlaybackSource, URL?) -> Void
    #endif

    var body: some View {
        selectedContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                NativeGlassPageBackground()
            }
            .navigationTitle(section.title)
    }

    @ViewBuilder
    private var selectedContent: some View {
        Group {
            switch section {
            case .bookshelf:
                NativeBookshelfPlaceholderView(
                    onOpenBook: onOpenBook,
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
