#if HOSHI_VIDEO
import AppKit
import SwiftUI

private final class ClickableSubtitleTextView: NSTextView {
    var onCharacterClicked: ((Int, CGRect) -> Void)?

    func containsInteractiveText(at point: CGPoint) -> Bool {
        guard let layoutManager, let textContainer else { return false }
        layoutManager.ensureLayout(for: textContainer)
        var textBounds = layoutManager.usedRect(for: textContainer)
        textBounds.origin.x += textContainerOrigin.x
        textBounds.origin.y += textContainerOrigin.y
        return textBounds.insetBy(dx: -10, dy: -8).contains(point)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        containsInteractiveText(at: point) ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let layoutManager, let textContainer else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard containsInteractiveText(at: point) else { return }
        let containerPoint = CGPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return }
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterIndex, length: 1),
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        onCharacterClicked?(characterIndex, rect)
    }
}

private final class PassThroughSubtitleScrollView: NSScrollView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let textView = documentView as? ClickableSubtitleTextView else {
            return nil
        }
        let textPoint = textView.convert(point, from: self)
        guard textView.containsInteractiveText(at: textPoint) else {
            return nil
        }
        return super.hitTest(point)
    }
}

struct InteractiveSubtitleTextView: NSViewRepresentable {
    let text: String
    let scanLength: Int
    var onSelection: (String, Int, CGRect) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PassThroughSubtitleScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        let textView = ClickableSubtitleTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.frame = scrollView.bounds
        textView.autoresizingMask = [.width, .height]
        textView.alignment = .center
        textView.textColor = .white
        textView.font = .systemFont(ofSize: 20, weight: .medium)
        textView.onCharacterClicked = { offset, rect in
            let lookupText = SubtitleSelectionResolver.lookupText(
                in: text,
                utf16Offset: offset,
                scanLength: scanLength
            )
            guard !lookupText.isEmpty else { return }
            onSelection(lookupText, offset, rect)
        }
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ClickableSubtitleTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.onCharacterClicked = { offset, rect in
            let lookupText = SubtitleSelectionResolver.lookupText(
                in: text,
                utf16Offset: offset,
                scanLength: scanLength
            )
            guard !lookupText.isEmpty else { return }
            onSelection(lookupText, offset, rect)
        }
    }
}
#endif
