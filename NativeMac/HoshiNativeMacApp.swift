import SwiftUI

@main
struct HoshiNativeMacApp: App {
    var body: some Scene {
        WindowGroup {
            NativeMacRootView()
                .frame(minWidth: 900, minHeight: 620)
        }
    }
}
