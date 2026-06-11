import SwiftUI

struct NativeBookshelfPlaceholderView: View {
    @Binding var selectedReaderBook: BookMetadata?

    var body: some View {
        NativeBookshelfReuseView(selectedReaderBook: $selectedReaderBook)
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
