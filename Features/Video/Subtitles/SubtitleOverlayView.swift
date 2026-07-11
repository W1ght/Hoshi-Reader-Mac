#if HOSHI_VIDEO
import SwiftUI

struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    let contextCues: [SubtitleCue]
    let scanLength: Int
    let hoverLookupDelayMs: Int
    let maskEnabled: Bool
    let maskMode: VideoSubtitleMaskMode
    let maskBlurRadius: Double
    let maskHiddenOpacity: Double
    let fontFamily: String
    let fontSize: Double
    let fontWeight: Int
    let edgeStyle: VideoSubtitleEdgeStyle
    let edgeStrength: Double
    let backgroundOpacity: Double
    let backgroundDisabled: Bool
    let verticalPosition: Double
    let subtitleColor: Color
    let lookupHighlightColor: Color
    let lookupHighlightTextColor: Color
    let isLookupPopupVisible: Bool
    let isPlaybackPaused: Bool
    let bottomClearance: CGFloat
    var onSelection: ((SubtitleCue, SelectionData) -> Int?)?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(cues) { cue in
                SubtitleCueMaskRow(
                    cue: cue,
                    contextCues: contextCues,
                    scanLength: scanLength,
                    hoverLookupDelayMs: hoverLookupDelayMs,
                    maskEnabled: maskEnabled,
                    maskMode: maskMode,
                    maskBlurRadius: maskBlurRadius,
                    maskHiddenOpacity: maskHiddenOpacity,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    edgeStyle: edgeStyle,
                    edgeStrength: edgeStrength,
                    backgroundOpacity: backgroundOpacity,
                    backgroundDisabled: backgroundDisabled,
                    subtitleColor: subtitleColor,
                    lookupHighlightColor: lookupHighlightColor,
                    lookupHighlightTextColor: lookupHighlightTextColor,
                    isLookupPopupVisible: isLookupPopupVisible,
                    isPlaybackPaused: isPlaybackPaused,
                    onSelection: onSelection
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, bottomClearance + verticalPositionOffset)
    }

    private var verticalPositionOffset: CGFloat {
        CGFloat(min(max(verticalPosition, -200), 200) * 3)
    }
}

private struct SubtitleCueMaskRow: View {
    let cue: SubtitleCue
    let contextCues: [SubtitleCue]
    let scanLength: Int
    let hoverLookupDelayMs: Int
    let maskEnabled: Bool
    let maskMode: VideoSubtitleMaskMode
    let maskBlurRadius: Double
    let maskHiddenOpacity: Double
    let fontFamily: String
    let fontSize: Double
    let fontWeight: Int
    let edgeStyle: VideoSubtitleEdgeStyle
    let edgeStrength: Double
    let backgroundOpacity: Double
    let backgroundDisabled: Bool
    let subtitleColor: Color
    let lookupHighlightColor: Color
    let lookupHighlightTextColor: Color
    let isLookupPopupVisible: Bool
    let isPlaybackPaused: Bool
    var onSelection: ((SubtitleCue, SelectionData) -> Int?)?

    @State private var isHovering = false
    @State private var availableTextWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            InteractiveSubtitleTextView(
                text: cue.text,
                scanLength: scanLength,
                hoverLookupDelayMs: hoverLookupDelayMs,
                fontFamily: fontFamily,
                fontSize: fontSize,
                fontWeight: fontWeight,
                edgeRecipe: edgeRecipe,
                subtitleColor: subtitleColor,
                lookupHighlightColor: lookupHighlightColor,
                lookupHighlightTextColor: lookupHighlightTextColor,
                isLookupPopupVisible: isLookupPopupVisible,
                onHoverChanged: { hovering in
                    isHovering = hovering
                }
            ) { lookupText, offset, localRect in
                let frame = geometry.frame(in: .named("video-player"))
                let selectionRect = CGRect(
                    x: frame.minX + localRect.minX,
                    y: frame.minY + localRect.minY,
                    width: max(localRect.width, 1),
                    height: max(localRect.height, 1)
                )
                let miningContext = VideoMiningContextSelectionBuilder.build(
                    cues: contextCues,
                    currentCueID: cue.id,
                    targetUTF16Location: offset
                )
                return onSelection?(
                    cue,
                    SelectionData(
                        text: lookupText,
                        sentence: cue.text,
                        rect: selectionRect,
                        normalizedOffset: offset,
                        miningContext: miningContext
                    )
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            max(proxy.size.width, 1)
        } action: { width in
            availableTextWidth = width
        }
        .background {
            if !backgroundDisabled && normalizedBackgroundOpacity > 0 {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(normalizedBackgroundOpacity))
            }
        }
        .blur(radius: maskedBlurRadius)
        .opacity(maskedOpacity)
        .animation(.smooth(duration: 0.12), value: isHovering)
        .animation(.smooth(duration: 0.12), value: isLookupPopupVisible)
        .frame(height: rowHeight)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var maskedBlurRadius: CGFloat {
        guard maskEnabled, !isMaskRevealed, maskMode == .blur else { return 0 }
        return CGFloat(min(max(maskBlurRadius, 0), 20))
    }

    private var maskedOpacity: Double {
        guard maskEnabled, !isMaskRevealed, maskMode == .transparent else { return 1 }
        return min(max(maskHiddenOpacity, 0), 1)
    }

    private var edgeRecipe: VideoSubtitleEdgeRecipe {
        VideoSubtitleEdgeRecipe.make(
            style: edgeStyle,
            strength: edgeStrength,
            fontSize: CGFloat(min(max(fontSize, 12), 72))
        )
    }

    private var normalizedBackgroundOpacity: Double {
        min(max(backgroundOpacity, 0), 1)
    }

    private var isMaskRevealed: Bool {
        isHovering || isLookupPopupVisible || isPlaybackPaused
    }

    private var rowHeight: CGFloat {
        SubtitleOverlayRowHeightMeasurer.height(
            for: cue.text,
            availableWidth: availableTextWidth > 0 ? availableTextWidth : 640,
            fontFamily: fontFamily,
            fontSize: fontSize,
            fontWeight: fontWeight,
            edgeAllowance: edgeRecipe.layoutAllowance
        )
    }
}
#endif
