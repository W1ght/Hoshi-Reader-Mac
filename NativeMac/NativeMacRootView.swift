import SwiftUI

struct NativeMacRootView: View {
    @State private var selection: NativeMacSection? = .bookshelf

    var body: some View {
        NavigationSplitView {
            NativeMacSidebarView(selection: $selection)
        } detail: {
            NativeMacDetailView(section: selectedSection)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("Navigation", selection: toolbarSelection) {
                            ForEach(NativeMacSection.allCases) { section in
                                Text(section.title)
                                    .tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                }
        }
    }

    private var selectedSection: NativeMacSection {
        selection ?? .bookshelf
    }

    private var toolbarSelection: Binding<NativeMacSection> {
        Binding {
            selectedSection
        } set: { newValue in
            selection = newValue
        }
    }
}
