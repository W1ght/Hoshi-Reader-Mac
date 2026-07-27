import SwiftUI

struct NativeMacSidebarView: View {
    @Binding var selection: NativeMacSection?

    var body: some View {
        List(selection: $selection) {
            Section("Niratan") {
                ForEach(NativeMacSection.allCases) { section in
                    HStack(spacing: 10) {
                        Image(systemName: section.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .lineLimit(1)

                            Text(section.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .contentMargins(.leading, 16, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .background {
            NativeGlassPageBackground(isolatesContainerMaterial: true)
                .ignoresSafeArea(.container, edges: .top)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
    }
}
