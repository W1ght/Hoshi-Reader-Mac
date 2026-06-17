#if HOSHI_VIDEO
import SwiftUI

struct SubtitleOverlayView: View {
    let cues: [SubtitleCue]
    let scanLength: Int
    var onSelection: ((SubtitleCue, SelectionData) -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(cues) { cue in
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
                    .frame(height: max(32, CGFloat(cue.text.components(separatedBy: "\n").count) * 28))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 84)
    }
}
#endif
