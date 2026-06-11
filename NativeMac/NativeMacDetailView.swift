import SwiftUI

struct NativeMacDetailView: View {
    let section: NativeMacSection
    @Binding var selectedReaderBook: BookMetadata?

    var body: some View {
        Group {
            switch section {
            case .bookshelf:
                NativeBookshelfPlaceholderView(selectedReaderBook: $selectedReaderBook)
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
