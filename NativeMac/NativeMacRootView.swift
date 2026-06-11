import SwiftUI

struct NativeMacRootView: View {
    @State private var selection: NativeMacSection? = .bookshelf
    @State private var selectedReaderBook: BookMetadata?

    var body: some View {
        ZStack {
            NavigationSplitView {
                NativeMacSidebarView(selection: $selection)
            } detail: {
                NativeMacDetailView(
                    section: selectedSection,
                    selectedReaderBook: $selectedReaderBook
                )
            }

            if let book = selectedReaderBook {
                NativeReaderLoader(book: book) {
                    selectedReaderBook = nil
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .toolbar(selectedReaderBook == nil ? .visible : .hidden, for: .windowToolbar)
    }

    private var selectedSection: NativeMacSection {
        selection ?? .bookshelf
    }

}
