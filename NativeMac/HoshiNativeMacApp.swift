import SwiftUI

@main
struct HoshiNativeMacApp: App {
    @State private var userConfig = UserConfig()

    var body: some Scene {
        WindowGroup {
            NativeMacRootView()
                .frame(minWidth: 900, minHeight: 620)
                .environment(userConfig)
        }
    }
}
