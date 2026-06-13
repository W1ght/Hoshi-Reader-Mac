import SwiftUI

struct NativeBookshelfPlaceholderView: View {
    @Binding var selectedReaderBook: BookMetadata?
    @Binding var showReaderRegressionLab: Bool

    var body: some View {
        NativeBookshelfReuseView(
            selectedReaderBook: $selectedReaderBook,
            showReaderRegressionLab: $showReaderRegressionLab
        )
    }
}

struct NativeDictionaryPlaceholderView: View {
    var body: some View {
        NativeDictionaryReuseView()
    }
}

struct NativeSettingsPlaceholderView: View {
    var body: some View {
        NativeSettingsReuseView()
    }
}
