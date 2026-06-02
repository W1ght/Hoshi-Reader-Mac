import SwiftUI

struct NativeBookshelfPlaceholderView: View {
    var body: some View {
        NativeBookshelfHomeView()
    }
}

struct NativeDictionaryPlaceholderView: View {
    var body: some View {
        NativeDictionaryLookupView()
    }
}

struct NativeReaderPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NativeMigrationStatusView(
                title: "阅读器暂缓",
                rows: [
                    "Reader / WKWebView / JS / CSS 仍是最高风险区域",
                    "native shell 先验证窗口、toolbar、导航和设置承载方式",
                    "真正迁移 Reader 前必须走回归 fixture 和截图验证"
                ]
            )

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)

                HStack(alignment: .top, spacing: 24) {
                    ForEach(0..<8) { index in
                        VStack(spacing: 5) {
                            ForEach(0..<18) { _ in
                                Capsule()
                                    .fill(index == 0 ? Color.secondary.opacity(0.38) : Color.secondary.opacity(0.24))
                                    .frame(width: 2, height: 18)
                            }
                        }
                    }
                }
                .padding(28)

                Text("Reader placeholder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            .frame(height: 300)
        }
    }
}

struct NativeSettingsPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            NativeMigrationStatusView(
                title: "设置迁移分组",
                rows: [
                    "外观、Anki、音频、Sasayaki、快捷键仍优先复用现有 SwiftUI 页面",
                    "平台差异只落在窄 AppKit bridge",
                    "新增用户可见文案接入真实页面前再同步 Localizable.xcstrings"
                ]
            )

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                NativeSettingsRow(icon: "paintpalette", title: "外观", detail: "Theme, layout, reader CSS")
                NativeSettingsRow(icon: "rectangle.stack.badge.plus", title: "Anki", detail: "AnkiConnect mining path")
                NativeSettingsRow(icon: "speaker.wave.2", title: "音频", detail: "Word audio and local sources")
                NativeSettingsRow(icon: "keyboard", title: "快捷键", detail: "Keyboard and controller bindings")
            }

            GroupBox {
                StatisticsSettingsView()
                    .frame(minHeight: 320)
            } label: {
                Text("复用现有 StatisticsSettingsView")
                    .font(.headline)
            }

            Divider()

            NativeShortcutCaptureProbeView()
        }
    }
}

struct NativeMigrationStatusView: View {
    let title: String
    let rows: [String]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.self) { row in
                    Label(row, systemImage: "checkmark.circle")
                        .labelStyle(.titleAndIcon)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

private struct NativeSettingsRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        GridRow {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(title)
                .fontWeight(.medium)

            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}
