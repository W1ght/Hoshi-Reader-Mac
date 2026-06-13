import SwiftUI

struct NativeMacDetailView: View {
    let section: NativeMacSection
    @Binding var selectedReaderBook: BookMetadata?
    @Binding var showReaderRegressionLab: Bool

    var body: some View {
        Group {
            switch section {
            case .bookshelf:
                NativeBookshelfPlaceholderView(
                    selectedReaderBook: $selectedReaderBook,
                    showReaderRegressionLab: $showReaderRegressionLab
                )
            case .dictionary:
                NativeDictionaryPlaceholderView()
            case .settings:
                NativeSettingsPlaceholderView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(section.title)
    }
}
