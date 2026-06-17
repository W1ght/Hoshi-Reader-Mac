#if HOSHI_VIDEO
import SwiftUI

struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    let scanLength: Int
    let maskEnabled: Bool
    let maskMode: VideoSubtitleMaskMode
    let maskBlurRadius: Double
    let maskHiddenOpacity: Double
    var onSelection: ((SubtitleCue, SelectionData) -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(cues) { cue in
                SubtitleCueMaskRow(
                    cue: cue,
                    scanLength: scanLength,
                    maskEnabled: maskEnabled,
                    maskMode: maskMode,
                    maskBlurRadius: maskBlurRadius,
                    maskHiddenOpacity: maskHiddenOpacity,
                    onSelection: onSelection
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 84)
    }
}

private struct SubtitleCueMaskRow: View {
    let cue: SubtitleCue
    let scanLength: Int
    let maskEnabled: Bool
    let maskMode: VideoSubtitleMaskMode
    let maskBlurRadius: Double
    let maskHiddenOpacity: Double
    var onSelection: ((SubtitleCue, SelectionData) -> Void)?

    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            InteractiveSubtitleTextView(
                text: cue.text,
                scanLength: scanLength
            ) { lookupText, offset, localRect in
                let frame = geometry.frame(in: .named("video-player"))
                let selectionRect = CGRect(
                    x: frame.minX + localRect.minX,
                    y: frame.minY + localRect.minY,
                    width: max(localRect.width, 1),
                    height: max(localRect.height, 1)
                )
                onSelection?(
                    cue,
                    SelectionData(
                        text: lookupText,
                        sentence: cue.text,
                        rect: selectionRect,
                        normalizedOffset: offset
                    )
                )
            }
        }
        .shadow(color: .black.opacity(0.9), radius: 3, y: 1)
        .blur(radius: maskedBlurRadius)
        .opacity(maskedOpacity)
        .animation(.smooth(duration: 0.12), value: isHovering)
        .frame(height: max(32, CGFloat(cue.text.components(separatedBy: "\n").count) * 28))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var maskedBlurRadius: CGFloat {
        guard maskEnabled, !isHovering, maskMode == .blur else { return 0 }
        return CGFloat(min(max(maskBlurRadius, 0), 20))
    }

    private var maskedOpacity: Double {
        guard maskEnabled, !isHovering, maskMode == .transparent else { return 1 }
        return min(max(maskHiddenOpacity, 0), 1)
    }
}
#endif
