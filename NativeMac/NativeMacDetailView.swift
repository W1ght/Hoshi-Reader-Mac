import SwiftUI

struct NativeMacDetailView: View {
    let section: NativeMacSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                switch section {
                case .bookshelf:
                    NativeBookshelfPlaceholderView()
                case .dictionary:
                    NativeDictionaryPlaceholderView()
                case .reader:
                    NativeReaderPlaceholderView()
                case .settings:
                    NativeSettingsPlaceholderView()
                }
            }
            .padding(28)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .navigationTitle(section.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(section.title, systemImage: section.systemImage)
                .font(.title2.bold())

            Text(section.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
