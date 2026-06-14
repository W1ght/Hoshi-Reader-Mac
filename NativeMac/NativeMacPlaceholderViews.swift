import SwiftUI

struct NativeBookshelfPlaceholderView: View {
    @Binding var selectedReaderBook: BookMetadata?
    @Binding var showReaderRegressionLab: Bool
    @Binding var pendingImportURL: URL?
    @Binding var pendingRemoteImportURL: URL?

    var body: some View {
        NativeBookshelfReuseView(
            selectedReaderBook: $selectedReaderBook,
            showReaderRegressionLab: $showReaderRegressionLab,
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
