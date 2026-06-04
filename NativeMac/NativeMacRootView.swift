import SwiftUI

struct NativeMacRootView: View {
    @State private var selection: NativeMacSection? = .bookshelf

    var body: some View {
        NavigationSplitView {
            NativeMacSidebarView(selection: $selection)
        } detail: {
            NativeMacDetailView(section: selectedSection)
        }
    }

    private var selectedSection: NativeMacSection {
        selection ?? .bookshelf
    }

}
