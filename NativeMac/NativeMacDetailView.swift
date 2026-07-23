import SwiftUI

struct NativeMacDetailView: View {
    let section: NativeMacSection
    let onOpenBook: (BookMetadata) -> Void
    @Binding var pendingImportURL: URL?
    @Binding var pendingRemoteImportURL: URL?
    let dictionaryRequest: NativeDictionaryOpenRequest?
    let onOpenVideo: (VideoPlaybackSource, URL?) -> Void

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
            case .video:
                VideoLibraryView(onOpenVideo: onOpenVideo)
            case .settings:
                NativeSettingsPlaceholderView()
            }
        }
    }
}
