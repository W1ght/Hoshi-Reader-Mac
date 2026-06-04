import SwiftUI

struct NativeMacDetailView: View {
    let section: NativeMacSection

    var body: some View {
        ZStack {
            if section == .bookshelf {
                NativeBookshelfPlaceholderView()
            }

            NativeDictionaryPlaceholderView()
                .nativeDetailVisible(section == .dictionary)

            if section == .reader {
                NativeReaderPlaceholderView()
            }

            if section == .settings {
                NativeSettingsPlaceholderView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(section.title)
    }
}

private extension View {
    func nativeDetailVisible(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}
