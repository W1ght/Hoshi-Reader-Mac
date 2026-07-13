#if HOSHI_VIDEO
import SwiftUI

struct SubtitleVerticalPositionLayout: Layout {
    let position: Double

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let fallback = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(
            width: max(proposal.width ?? fallback.width, 0),
            height: max(proposal.height ?? fallback.height, 0)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subtitle = subviews.first else { return }
        let childProposal = ProposedViewSize(width: max(bounds.width, 0), height: nil)
        let subtitleSize = subtitle.sizeThatFits(childProposal)
        let y = VideoSubtitlePositionPolicy.originY(
            viewportHeight: bounds.height,
            subtitleHeight: subtitleSize.height,
            position: position
        )
        subtitle.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: subtitleSize.height)
        )
    }
}
#endif
