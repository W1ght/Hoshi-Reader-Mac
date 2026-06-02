import SwiftUI

struct NativeBookshelfReuseView: View {
    var body: some View {
        NativeMigrationStatusView(
            title: "书架复用待接入",
            rows: [
                "下一步直接复用 BookshelfView / ShelfView / BookCell",
                "先抽掉 Reader、Sync、Sasayaki、Anki 的平台边界",
                "不再维护 native 手写书架 UI"
            ]
        )
    }
}

struct NativeDictionaryReuseView: View {
    var body: some View {
        NativeMigrationStatusView(
            title: "词典查询复用待接入",
            rows: [
                "下一步直接复用 DictionarySearchView",
                "PopupWebView 从 UIViewRepresentable 抽成 NSViewRepresentable bridge",
                "不再维护 native 手写词典渲染"
            ]
        )
    }
}

struct NativeSettingsReuseView: View {
    @Environment(UserConfig.self) private var userConfig

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    DictionaryView()
                } label: {
                    Label("Dictionaries", systemImage: "character.book.closed.ja")
                }

                NavigationLink {
                    AnkiView()
                } label: {
                    Label("Anki", systemImage: "tray.full")
                }

                NavigationLink {
                    AppearanceView(userConfig: userConfig, showDismiss: false)
                } label: {
                    Label("Appearance", systemImage: "paintpalette")
                }

                NavigationLink {
                    AdvancedView()
                } label: {
                    Label("Advanced", systemImage: "gearshape.2")
                }

                Section {
                    Link(destination: URL(string: "https://github.com/W1ght/Hoshi-Reader-for-Mac/issues")!) {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                    }

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
