import SwiftUI

struct NativeMacDetailView: View {
    let section: NativeMacSection
    @Binding var selectedReaderBook: BookMetadata?
    @Binding var showReaderRegressionLab: Bool
    @Binding var pendingImportURL: URL?
    @Binding var pendingRemoteImportURL: URL?
    let dictionaryRequest: NativeDictionaryOpenRequest?

    var body: some View {
        Group {
            switch section {
            case .bookshelf:
                NativeBookshelfPlaceholderView(
                    selectedReaderBook: $selectedReaderBook,
                    showReaderRegressionLab: $showReaderRegressionLab,
                    pendingImportURL: $pendingImportURL,
                    pendingRemoteImportURL: $pendingRemoteImportURL
                )
            case .dictionary:
                NativeDictionaryPlaceholderView(request: dictionaryRequest)
            case .settings:
                NativeSettingsPlaceholderView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(section.title)
    }
}
