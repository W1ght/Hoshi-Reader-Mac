import SwiftUI

@main
struct HoshiNativeMacApp: App {
    var body: some Scene {
        WindowGroup {
            NativeMacRootView()
                .frame(minWidth: 640, minHeight: 420)
        }
    }
}
