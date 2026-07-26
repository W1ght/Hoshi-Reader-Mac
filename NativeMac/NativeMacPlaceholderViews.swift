import SwiftUI

struct NativeBookshelfPlaceholderView: View {
    let viewModel: BookshelfViewModel
    let onOpenBook: (BookMetadata) -> Void
    @Binding var pendingImportURL: URL?
    @Binding var pendingRemoteImportURL: URL?

    var body: some View {
        NativeBookshelfReuseView(
            viewModel: viewModel,
            onOpenBook: onOpenBook,
            pendingImportURL: $pendingImportURL,
            pendingRemoteImportURL: $pendingRemoteImportURL
        )
    }
}

struct NativeDictionaryPlaceholderView: View {
    let request: NativeDictionaryOpenRequest?

    var body: some View {
        NativeDictionaryReuseView(request: request)
    }
}

struct NativeSettingsPlaceholderView: View {
    var body: some View {
        NativeSettingsReuseView()
    }
}
