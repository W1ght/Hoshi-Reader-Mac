#if HOSHI_VIDEO
import SwiftUI

struct VideoStudyListCard<Content: View, Accessories: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let accessories: () -> Accessories

    @State private var isHovered = false

    init(
        isSelected: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder accessories: @escaping () -> Accessories
    ) {
        self.isSelected = isSelected
        self.action = action
        self.content = content
        self.accessories = accessories
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            accessories()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .modifier(VideoStudyListCardSurface(isSelected: isSelected, isHovered: isHovered))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

extension VideoStudyListCard where Accessories == EmptyView {
    init(
        isSelected: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            isSelected: isSelected,
            action: action,
            content: content,
            accessories: { EmptyView() }
        )
    }
}

private struct VideoStudyListCardSurface: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(backgroundTint)
                    .overlay {
                        shape.strokeBorder(borderTint, lineWidth: 0.7)
                    }
            }
    }

    private var backgroundTint: Color {
        if isSelected {
            return Color.accentColor.opacity(0.18)
        }
        return Color.primary.opacity(isHovered ? 0.08 : 0.025)
    }

    private var borderTint: Color {
        if isSelected {
            return Color.accentColor.opacity(0.38)
        }
        return Color.white.opacity(isHovered ? 0.22 : 0.12)
    }
}
#endif
