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

        print("Video window aspect layout tests passed")
    }
}
