import AppKit
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func approximatelyEqual(
    _ lhs: CGFloat,
    _ rhs: CGFloat,
    tolerance: CGFloat = 0.001
) -> Bool {
    abs(lhs - rhs) <= tolerance
}

@main
private enum VideoWindowAspectLayoutTests {
    static func main() {
        expect(
            VideoAspectRatio.ratio16x9.numericValue == 16.0 / 9.0,
            "explicit 16:9 override should expose its numeric aspect ratio"
        )
        expect(
            VideoAspectRatio.automatic.numericValue == nil,
            "automatic aspect ratio should defer to the media display size"
        )

        let automaticWide = VideoWindowAspectLayout.videoAspectRatio(
            displaySize: CGSize(width: 1920, height: 1080),
            override: .automatic,
            rotation: 0
        )
        expect(
            approximatelyEqual(automaticWide ?? 0, 16.0 / 9.0),
            "automatic window aspect should use mpv display dimensions"
        )

        let rotatedWide = VideoWindowAspectLayout.videoAspectRatio(
            displaySize: CGSize(width: 1920, height: 1080),
            override: .automatic,
            rotation: 90
        )
        expect(
            approximatelyEqual(rotatedWide ?? 0, 9.0 / 16.0),
            "90-degree rotation should swap media dimensions for window sizing"
        )

        let explicitOverride = VideoWindowAspectLayout.videoAspectRatio(
            displaySize: CGSize(width: 1920, height: 1080),
            override: .ratio4x3,
            rotation: 90
        )
        expect(
            approximatelyEqual(explicitOverride ?? 0, 3.0 / 4.0),
            "rotation should apply to explicit aspect-ratio overrides"
        )

        let fullScreenViewport = VideoWindowAspectLayout.videoViewport(
            in: CGSize(width: 1470, height: 923),
            renderGeometry: VideoRenderGeometry(
                osdSize: CGSize(width: 2940, height: 1846),
                topMargin: 96,
                bottomMargin: 96,
                leftMargin: 0,
                rightMargin: 0
            ),
            aspectRatio: 16.0 / 9.0
        )
        expect(
            approximatelyEqual(fullScreenViewport.minX, 0)
                && approximatelyEqual(fullScreenViewport.minY, 48)
                && approximatelyEqual(fullScreenViewport.width, 1470)
                && approximatelyEqual(fullScreenViewport.height, 827),
            "full-screen viewport should follow mpv's actual rounded letterbox margins"
        )

        let asymmetricViewport = VideoWindowAspectLayout.videoViewport(
            in: CGSize(width: 1200, height: 800),
            renderGeometry: VideoRenderGeometry(
                osdSize: CGSize(width: 2400, height: 1600),
                topMargin: 80,
                bottomMargin: 160,
                leftMargin: 120,
                rightMargin: 240
            ),
            aspectRatio: 16.0 / 9.0
        )
        expect(
            approximatelyEqual(asymmetricViewport.minX, 60)
                && approximatelyEqual(asymmetricViewport.minY, 40)
                && approximatelyEqual(asymmetricViewport.width, 1020)
                && approximatelyEqual(asymmetricViewport.height, 680),
            "mpv OSD margins should be scaled into the SwiftUI video surface"
        )

        let invalidRenderGeometryViewport = VideoWindowAspectLayout.videoViewport(
            in: CGSize(width: 1470, height: 923),
            renderGeometry: VideoRenderGeometry(
                osdSize: CGSize(width: 0, height: 0),
                topMargin: 0,
                bottomMargin: 0,
                leftMargin: 0,
                rightMargin: 0
            ),
            aspectRatio: 16.0 / 9.0
        )
        expect(
            approximatelyEqual(invalidRenderGeometryViewport.minY, 48.0625)
                && approximatelyEqual(invalidRenderGeometryViewport.height, 826.875),
            "unavailable mpv OSD dimensions should fall back to aspect-fit geometry"
        )

        let exactViewport = VideoWindowAspectLayout.videoViewport(
            in: CGSize(width: 1470, height: 826.875),
            renderGeometry: nil,
            aspectRatio: 16.0 / 9.0
        )
        expect(
            approximatelyEqual(exactViewport.minX, 0)
                && approximatelyEqual(exactViewport.minY, 0)
                && approximatelyEqual(exactViewport.width, 1470)
                && approximatelyEqual(exactViewport.height, 826.875),
            "an exact-aspect window should use the complete video surface"
        )

        let pillarboxedViewport = VideoWindowAspectLayout.videoViewport(
            in: CGSize(width: 1600, height: 900),
            renderGeometry: nil,
            aspectRatio: 4.0 / 3.0
        )
        expect(
            approximatelyEqual(pillarboxedViewport.minX, 200)
                && approximatelyEqual(pillarboxedViewport.minY, 0)
                && approximatelyEqual(pillarboxedViewport.width, 1200)
                && approximatelyEqual(pillarboxedViewport.height, 900),
            "a narrower picture should stay centered between equal pillarboxes"
        )

        let fallbackViewport = VideoWindowAspectLayout.videoViewport(
            in: CGSize(width: 1200, height: 700),
            renderGeometry: nil,
            aspectRatio: nil
        )
        expect(
            fallbackViewport == CGRect(x: 0, y: 0, width: 1200, height: 700),
            "missing media geometry should fall back to the complete video surface"
        )

        let invalidViewport = VideoWindowAspectLayout.videoViewport(
            in: CGSize(width: 1200, height: 700),
            renderGeometry: nil,
            aspectRatio: .nan
        )
        expect(
            invalidViewport == CGRect(x: 0, y: 0, width: 1200, height: 700),
            "invalid media geometry should fall back to the complete video surface"
        )

        let contentSize = VideoWindowAspectLayout.fittedContentSize(
            currentContentSize: CGSize(width: 1200, height: 760),
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 340,
            visibleContentFrame: CGRect(x: 0, y: 0, width: 2000, height: 1200)
        )
        expect(
            approximatelyEqual(contentSize.width, contentSize.height * 16.0 / 9.0 + 340),
            "windowed content width should reserve sidebar width after aspect-fitting the video"
        )

        let clampedContentSize = VideoWindowAspectLayout.fittedContentSize(
            currentContentSize: CGSize(width: 1600, height: 900),
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 340,
            visibleContentFrame: CGRect(x: 0, y: 0, width: 1280, height: 720)
        )
        expect(
            clampedContentSize.width <= 1280,
            "aspect-fitting should shrink oversized video windows to the visible display width"
        )
        expect(
            approximatelyEqual(
                clampedContentSize.width,
                clampedContentSize.height * 16.0 / 9.0 + 340
            ),
            "visible-display clamping should preserve the video-plus-sidebar aspect relationship"
        )

        let resolvedSidebar = VideoWindowAspectLayout.aspectFittingSidebarWidth(
            contentSize: CGSize(width: 1700, height: 765),
            videoAspectRatio: 16.0 / 9.0,
            proposedWidth: 340,
            minWidth: 320,
            maxWidth: 560
        )
        expect(
            approximatelyEqual(resolvedSidebar, 340),
            "study sidebar width should match the current window width when that preserves the video aspect"
        )

        let currentFrameSize = CGSize(width: 1280, height: 748)
        let titlebarDecoration = CGSize(width: 0, height: 28)
        let minimumFrameSize = CGSize(width: 900, height: 620)

        let horizontalResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: currentFrameSize,
            proposedFrameSize: CGSize(width: 1600, height: 748),
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 0,
            minimumFrameSize: minimumFrameSize
        )
        expect(
            approximatelyEqual(horizontalResize.width, 1600),
            "horizontal resizing should preserve the proposed width"
        )
        expect(
            approximatelyEqual(horizontalResize.height, 928),
            "horizontal resizing should derive content height before restoring title-bar height"
        )

        let verticalResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: currentFrameSize,
            proposedFrameSize: CGSize(width: 1280, height: 928),
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 0,
            minimumFrameSize: minimumFrameSize
        )
        expect(
            approximatelyEqual(verticalResize.width, 1600),
            "vertical resizing should derive width from the proposed content height"
        )
        expect(
            approximatelyEqual(verticalResize.height, 928),
            "vertical resizing should preserve the proposed frame height"
        )

        let cornerResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: currentFrameSize,
            proposedFrameSize: CGSize(width: 1480, height: 808),
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 0,
            minimumFrameSize: minimumFrameSize
        )
        expect(
            approximatelyEqual(cornerResize.width, 1480),
            "corner resizing should honor the dominant normalized width delta"
        )
        expect(
            approximatelyEqual(cornerResize.height, 860.5),
            "corner resizing should derive the paired dimension from the dominant delta"
        )

        let sidebarResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: CGSize(width: 1620, height: 748),
            proposedFrameSize: CGSize(width: 1940, height: 748),
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 340,
            minimumFrameSize: minimumFrameSize
        )
        expect(
            approximatelyEqual(sidebarResize.width, 1940),
            "study-sidebar resizing should preserve the proposed total width"
        )
        expect(
            approximatelyEqual(sidebarResize.height, 928),
            "study-sidebar resizing should keep only the video surface aspect-correct"
        )

        let minimumResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: currentFrameSize,
            proposedFrameSize: CGSize(width: 800, height: 500),
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: 16.0 / 9.0,
            sidebarWidth: 0,
            minimumFrameSize: minimumFrameSize
        )
        expect(
            approximatelyEqual(minimumResize.width, 592 * 16.0 / 9.0),
            "minimum height should grow width along the video ratio"
        )
        expect(
            approximatelyEqual(minimumResize.height, 620),
            "live resizing should respect the minimum frame height"
        )

        let invalidResizeProposal = CGSize(width: 1400, height: 900)
        let invalidResize = VideoWindowAspectLayout.constrainedFrameSize(
            currentFrameSize: currentFrameSize,
            proposedFrameSize: invalidResizeProposal,
            frameDecorationSize: titlebarDecoration,
            videoAspectRatio: .nan,
            sidebarWidth: 0,
            minimumFrameSize: minimumFrameSize
        )
        expect(
            invalidResize == invalidResizeProposal,
            "invalid layout inputs should leave AppKit's proposal unchanged"
        )

        print("Video window aspect layout tests passed")
    }
}
