#if HOSHI_VIDEO
import AppKit
import SwiftUI

struct VideoMiningHistorySidebar: View {
    let items: [VideoMiningHistoryItem]
    var onClose: () -> Void
    var onSeek: (TimeInterval) -> Void
    var onDelete: (String) -> Void
    var onClear: () -> Void

    private var sections: [(fileName: String, items: [VideoMiningHistoryItem])] {
        var result: [(String, [VideoMiningHistoryItem])] = []
        for item in items.sorted(by: { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id > rhs.id
            }
            return lhs.createdAt > rhs.createdAt
        }) {
            if let index = result.firstIndex(where: { $0.0 == item.videoFileName }) {
                result[index].1.append(item)
            } else {
                result.append((item.videoFileName, [item]))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.5)

            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(sections, id: \.fileName) { section in
                            historySection(section)
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.hidden)

                Divider()
                    .opacity(0.5)

                Button(role: .destructive, action: onClear) {
                    Label("Clear Mining History", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(VideoMiningHistoryButtonStyle())
                .padding(14)
            }
        }
        .frame(minWidth: 320, idealWidth: 340, maxWidth: 380)
        .background(.regularMaterial)
        .overlay(alignment: .leading) {
            Divider()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Mining History", systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .labelStyle(.titleAndIcon)

            Spacer()

            Text("\(items.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(VideoMiningHistoryIconButtonStyle())
            .help("Close")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Mining History Empty", systemImage: "tray")
        } description: {
            Text("Mined video subtitles will appear here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func historySection(
        _ section: (fileName: String, items: [VideoMiningHistoryItem])
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.fileName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 2)

            ForEach(section.items) { item in
                historyRow(item)
            }
        }
    }

    private func historyRow(_ item: VideoMiningHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.expression.isEmpty ? item.subtitleText : item.expression)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    if let reading = item.reading {
                        Text(reading)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                statusLabel(item.status)
            }

            Text(item.subtitleText)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack(spacing: 8) {
                Label(VideoTimeFormatter.string(from: item.cueStart), systemImage: "play.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    onSeek(item.cueStart)
                } label: {
                    Image(systemName: "arrowshape.turn.up.forward")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(VideoMiningHistoryIconButtonStyle())
                .help("Jump to Subtitle")

                Button {
                    copy(item.subtitleText)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(VideoMiningHistoryIconButtonStyle())
                .help("Copy Subtitle")

                Button(role: .destructive) {
                    onDelete(item.id)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(VideoMiningHistoryIconButtonStyle())
                .help("Delete")
            }

            if let message = item.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private func statusLabel(_ status: VideoMiningHistoryStatus) -> some View {
        Text(status.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(status.tint.opacity(0.14), in: Capsule())
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private extension VideoMiningHistoryStatus {
    var title: LocalizedStringKey {
        switch self {
        case .pending: "Pending"
        case .added: "Added"
        case .duplicate: "Duplicate"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .pending: .blue
        case .added: .green
        case .duplicate: .orange
        case .failed: .red
        }
    }
}

private struct VideoMiningHistoryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                configuration.isPressed ? Color.primary.opacity(0.14) : Color.primary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}

private struct VideoMiningHistoryIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                configuration.isPressed ? Color.primary.opacity(0.14) : Color.primary.opacity(0.08),
                in: Circle()
            )
    }
}
#endif
