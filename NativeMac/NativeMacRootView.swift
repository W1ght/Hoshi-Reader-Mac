import SwiftUI

struct NativeMacRootView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hoshi Reader")
                    .font(.title.bold())

                Text("Native macOS migration shell")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Reader, dictionary, sync, Anki, audio, and release behavior remain in the Mac Catalyst target while native pieces are migrated incrementally.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            NativeShortcutCaptureProbeView()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
