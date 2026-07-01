import AppKit
import MetalKit
import QuartzCore
import SwiftUI

private final class ReaderLyricsHitTestTextView: NSTextView {
    var onCharacterClicked: ((Int, CGRect) -> NSRange?)?
    var lookupHighlightColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.72)
    var lookupHighlightTextColor = NSColor.textColor

    private var lookupHighlightRange: NSRange?
    private var lastLayoutSignature: ReaderLyricsHitTestLayoutSignature?

    func clearLookupHighlight() {
        guard let lookupHighlightRange else { return }
        layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: lookupHighlightRange)
        layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: lookupHighlightRange)
        self.lookupHighlightRange = nil
    }

    func updateLookupHighlightColor(_ color: NSColor) {
        lookupHighlightColor = color
        guard let lookupHighlightRange else { return }
        layoutManager?.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: lookupHighlightRange)
    }

    func updateLookupHighlightTextColor(_ color: NSColor) {
        lookupHighlightTextColor = color
        guard let lookupHighlightRange else { return }
        layoutManager?.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: lookupHighlightRange)
    }

    func updateHitTestText(
        _ text: String,
        fontSize: CGFloat,
        weight: NSFont.Weight
    ) -> Bool {
        let isRightToLeft = ReaderLyricsTextDirection.isRightToLeft(text)
        let signature = ReaderLyricsHitTestLayoutSignature(
            text: text,
            fontSize: fontSize.rounded(.toNearestOrAwayFromZero),
            fontWeight: weight.rawValue,
            isRightToLeft: isRightToLeft
        )
        guard signature != lastLayoutSignature else {
            return false
        }
        lastLayoutSignature = signature

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = isRightToLeft ? .right : .left
        paragraphStyle.baseWritingDirection = isRightToLeft ? .rightToLeft : .leftToRight

        textStorage?.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: min(max(fontSize, 12), 72), weight: weight),
                    .foregroundColor: NSColor.clear,
                    .paragraphStyle: paragraphStyle
                ]
            )
        )
        alignment = paragraphStyle.alignment
        baseWritingDirection = paragraphStyle.baseWritingDirection
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
        guard selectedRange().length == 0, event.clickCount == 1 else { return }
        performLookup(at: point)
    }

    private func performLookup(at point: CGPoint) {
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)

        let containerPoint = CGPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else {
            clearLookupHighlight()
            return
        }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: characterIndex, length: 1),
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y

        if let range = onCharacterClicked?(characterIndex, rect) {
            setLookupHighlight(range)
        } else {
            clearLookupHighlight()
        }
    }

    private func setLookupHighlight(_ range: NSRange) {
        clearLookupHighlight()
        guard range.location >= 0,
              range.length > 0,
              NSMaxRange(range) <= string.utf16.count else { return }
        layoutManager?.addTemporaryAttribute(.backgroundColor, value: lookupHighlightColor, forCharacterRange: range)
        layoutManager?.addTemporaryAttribute(.foregroundColor, value: lookupHighlightTextColor, forCharacterRange: range)
        lookupHighlightRange = range
    }
}

private struct ReaderLyricsHitTestLayoutSignature: Equatable {
    let text: String
    let fontSize: CGFloat
    let fontWeight: CGFloat
    let isRightToLeft: Bool
}

private struct ReaderLyricsMetalTexturePair {
    let selected: MTLTexture
    let upcoming: MTLTexture
    let pixelSize: CGSize
    let isRightToLeft: Bool
}

private struct ReaderLyricsRenderSignature: Equatable {
    let text: String
    let fontSize: CGFloat
    let fontWeight: CGFloat
    let selectedColor: String
    let upcomingColor: String
    let pixelWidth: Int
    let pixelHeight: Int
    let isRightToLeft: Bool
}

private struct ReaderLyricsMetalUniforms {
    var progressFraction: Float
    var featherFraction: Float
    var isRightToLeft: Float
    var drawsSelectedTexture: Float
}

final class ReaderLyricsMetalRenderView: MTKView {
    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLRenderPipelineState?
    private var texturePair: ReaderLyricsMetalTexturePair?
    private var lastLyricsRenderSignature: ReaderLyricsRenderSignature?
    private var displayedProgressFraction: CGFloat = 1
    private var sourceProgressFraction: CGFloat = 1
    private var progressRatePerSecond: CGFloat = 0
    private var isProgressAnimating = false
    private var lastProgressSourceUpdateTime: CFTimeInterval?
    private var progressDisplayLink: CADisplayLink?
    private var currentText = ""
    private var currentFontSize: CGFloat = 34
    private var currentWeight: NSFont.Weight = .bold
    private var currentSelectedColor = NSColor.white
    private var currentUpcomingColor = NSColor.white.withAlphaComponent(0.6)
    private let progressEpsilon: CGFloat = 0.0005
    private let progressStaleFrameInterval: CFTimeInterval = 0.35

    init() {
        let device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        pipelineState = device.flatMap {
            Self.makeRenderPipelineState(device: $0, pixelFormat: .bgra8Unorm)
        }
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        layer?.isOpaque = false
    }

    deinit {
        MainActor.assumeIsolated {
            stopProgressDisplayLink()
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var isOpaque: Bool {
        false
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
        if rebuildTexturesIfNeeded() {
            needsDisplay = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopProgressDisplayLink()
        } else if isProgressAnimationActive {
            startProgressDisplayLinkIfNeeded()
        }
    }

    func updateLyrics(
        text: String,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        selectedColor: NSColor,
        upcomingColor: NSColor,
        progressFraction: CGFloat,
        progressRatePerSecond: CGFloat,
        isProgressAnimating: Bool
    ) {
        let clampedProgress = min(max(progressFraction, 0), 1)
        let clampedProgressRate = max(progressRatePerSecond, 0)
        let contentChanged = text != currentText
            || currentFontSize.rounded(.toNearestOrAwayFromZero) != fontSize.rounded(.toNearestOrAwayFromZero)
            || currentWeight.rawValue != weight.rawValue
            || Self.colorSignature(currentSelectedColor) != Self.colorSignature(selectedColor)
            || Self.colorSignature(currentUpcomingColor) != Self.colorSignature(upcomingColor)
        let progressInputsUnchanged = abs(clampedProgress - sourceProgressFraction) <= progressEpsilon
            && abs(clampedProgress - displayedProgressFraction) <= progressEpsilon
            && abs(clampedProgressRate - self.progressRatePerSecond) <= progressEpsilon
            && isProgressAnimating == self.isProgressAnimating

        currentText = text
        currentFontSize = fontSize
        currentWeight = weight
        currentSelectedColor = selectedColor
        currentUpcomingColor = upcomingColor
        self.progressRatePerSecond = clampedProgressRate
        self.isProgressAnimating = isProgressAnimating

        let rebuiltTextures = rebuildTexturesIfNeeded()
        guard contentChanged || rebuiltTextures || !progressInputsUnchanged else {
            return
        }
        updateProgressSource(
            clampedProgress,
            resetDisplayProgress: contentChanged || rebuiltTextures
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let commandQueue,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            if let texturePair, let pipelineState {
                renderEncoder.setRenderPipelineState(pipelineState)
                drawTextTexture(
                    texturePair.upcoming,
                    texturePair: texturePair,
                    drawsSelectedTexture: false,
                    using: renderEncoder
                )
                drawTextTexture(
                    texturePair.selected,
                    texturePair: texturePair,
                    drawsSelectedTexture: true,
                    using: renderEncoder
                )
            }
            renderEncoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        drawableSize = CGSize(
            width: max(bounds.width * scale, 1),
            height: max(bounds.height * scale, 1)
        )
    }

    private func rebuildTexturesIfNeeded() -> Bool {
        guard let device, bounds.width > 0, bounds.height > 0 else { return false }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelWidth = max(Int((bounds.width * scale).rounded(.up)), 1)
        let pixelHeight = max(Int((bounds.height * scale).rounded(.up)), 1)
        let isRightToLeft = ReaderLyricsTextDirection.isRightToLeft(currentText)
        let signature = ReaderLyricsRenderSignature(
            text: currentText,
            fontSize: currentFontSize.rounded(.toNearestOrAwayFromZero),
            fontWeight: currentWeight.rawValue,
            selectedColor: Self.colorSignature(currentSelectedColor),
            upcomingColor: Self.colorSignature(currentUpcomingColor),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            isRightToLeft: isRightToLeft
        )
        guard signature != lastLyricsRenderSignature else {
            return false
        }
        lastLyricsRenderSignature = signature

        guard let selected = makeTextTexture(
            device: device,
            text: currentText,
            size: bounds.size,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            scale: scale,
            fontSize: currentFontSize,
            weight: currentWeight,
            color: currentSelectedColor,
            isRightToLeft: isRightToLeft
        ),
        let upcoming = makeTextTexture(
            device: device,
            text: currentText,
            size: bounds.size,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            scale: scale,
            fontSize: currentFontSize,
            weight: currentWeight,
            color: currentUpcomingColor,
            isRightToLeft: isRightToLeft
        ) else { return false }

        texturePair = ReaderLyricsMetalTexturePair(
            selected: selected,
            upcoming: upcoming,
            pixelSize: CGSize(width: pixelWidth, height: pixelHeight),
            isRightToLeft: isRightToLeft
        )
        return true
    }

    private func makeTextTexture(
        device: MTLDevice,
        text: String,
        size: CGSize,
        pixelWidth: Int,
        pixelHeight: Int,
        scale: CGFloat,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        isRightToLeft: Bool
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: pixelWidth,
            height: pixelHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let bytesPerRow = pixelWidth * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * pixelHeight)
        pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: pixelWidth,
                    height: pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue
                  ) else {
                return
            }

            context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            context.setShouldAntialias(true)
            context.setAllowsAntialiasing(true)
            context.interpolationQuality = .high
            context.translateBy(x: 0, y: CGFloat(pixelHeight))
            context.scaleBy(x: scale, y: -scale)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = isRightToLeft ? .right : .left
            paragraphStyle.baseWritingDirection = isRightToLeft ? .rightToLeft : .leftToRight
            let attributed = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: min(max(fontSize, 12), 72), weight: weight),
                    .foregroundColor: color,
                    .paragraphStyle: paragraphStyle
                ]
            )

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            attributed.draw(
                with: CGRect(origin: .zero, size: size),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            NSGraphicsContext.restoreGraphicsState()

            texture.replace(
                region: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight),
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: bytesPerRow
            )
        }
        return texture
    }

    private func drawTextTexture(
        _ texture: MTLTexture,
        texturePair: ReaderLyricsMetalTexturePair,
        drawsSelectedTexture: Bool,
        using encoder: MTLRenderCommandEncoder
    ) {
        var uniforms = ReaderLyricsMetalUniforms(
            progressFraction: Float(min(max(displayedProgressFraction, 0), 1)),
            featherFraction: normalizedFeatherFraction(for: texturePair),
            isRightToLeft: texturePair.isRightToLeft ? 1 : 0,
            drawsSelectedTexture: drawsSelectedTexture ? 1 : 0
        )
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<ReaderLyricsMetalUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    private func normalizedFeatherFraction(for texturePair: ReaderLyricsMetalTexturePair) -> Float {
        let width = max(texturePair.pixelSize.width, 1)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let featherPixels = ReaderLyricsVisualSpec.lineProgressionGradientFeather * scale
        return Float(min(max(featherPixels / width, 0), 0.25))
    }

    private var isProgressAnimationActive: Bool {
        isProgressAnimating
            && progressRatePerSecond > 0
            && displayedProgressFraction < 1 - progressEpsilon
    }

    private func updateProgressSource(
        _ progressFraction: CGFloat,
        resetDisplayProgress: Bool
    ) {
        let now = CACurrentMediaTime()
        let predictedProgress = displayProgress(at: now)
        let shouldJump = resetDisplayProgress
            || !isProgressAnimationActive
            || progressFraction < predictedProgress - 0.02
            || abs(progressFraction - predictedProgress) > 0.08

        sourceProgressFraction = progressFraction
        lastProgressSourceUpdateTime = now
        displayedProgressFraction = shouldJump ? progressFraction : max(predictedProgress, progressFraction)

        if isProgressAnimationActive {
            startProgressDisplayLinkIfNeeded()
        } else {
            stopProgressDisplayLink()
        }
        needsDisplay = true
    }

    private func displayProgress(at timestamp: CFTimeInterval) -> CGFloat {
        guard isProgressAnimating,
              progressRatePerSecond > 0,
              let lastProgressSourceUpdateTime else {
            return displayedProgressFraction
        }
        let elapsed = timestamp - lastProgressSourceUpdateTime
        guard elapsed >= 0, elapsed <= progressStaleFrameInterval else {
            return displayedProgressFraction
        }
        return min(max(sourceProgressFraction + CGFloat(elapsed) * progressRatePerSecond, 0), 1)
    }

    @objc private func advanceProgressDisplayLinkFrame(_ displayLink: CADisplayLink) {
        guard window != nil else {
            stopProgressDisplayLink()
            return
        }
        guard isProgressAnimationActive,
              let lastProgressSourceUpdateTime else {
            stopProgressDisplayLink()
            return
        }

        let now = CACurrentMediaTime()
        guard now - lastProgressSourceUpdateTime <= progressStaleFrameInterval else {
            stopProgressDisplayLink()
            return
        }

        let nextProgress = displayProgress(at: now)
        guard abs(nextProgress - displayedProgressFraction) > progressEpsilon else {
            if nextProgress >= 1 - progressEpsilon {
                stopProgressDisplayLink()
            }
            return
        }
        displayedProgressFraction = nextProgress
        needsDisplay = true
    }

    private func startProgressDisplayLinkIfNeeded() {
        guard window != nil else { return }
        guard progressDisplayLink == nil else { return }
        let link = self.displayLink(target: self, selector: #selector(advanceProgressDisplayLinkFrame(_:)))
        link.add(to: .main, forMode: .common)
        progressDisplayLink = link
    }

    private func stopProgressDisplayLink() {
        progressDisplayLink?.invalidate()
        progressDisplayLink = nil
    }

    private static func makeRenderPipelineState(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineState? {
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFunction = library.makeFunction(name: "readerLyricsVertex"),
              let fragmentFunction = library.makeFunction(name: "readerLyricsFragment") else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func colorSignature(_ color: NSColor) -> String {
        guard let converted = color.usingColorSpace(.deviceRGB) else {
            return color.description
        }
        return [
            converted.redComponent,
            converted.greenComponent,
            converted.blueComponent,
            converted.alphaComponent
        ]
        .map { String(Int(($0 * 1000).rounded())) }
        .joined(separator: ":")
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct ReaderLyricsVertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    struct ReaderLyricsMetalUniforms {
        float progressFraction;
        float featherFraction;
        float isRightToLeft;
        float drawsSelectedTexture;
    };

    vertex ReaderLyricsVertexOut readerLyricsVertex(uint vertexID [[vertex_id]]) {
        const float2 positions[6] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0, -1.0),
            float2( 1.0,  1.0),
            float2(-1.0,  1.0)
        };
        const float2 texCoords[6] = {
            float2(0.0, 1.0),
            float2(1.0, 1.0),
            float2(0.0, 0.0),
            float2(1.0, 1.0),
            float2(1.0, 0.0),
            float2(0.0, 0.0)
        };

        ReaderLyricsVertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.texCoord = texCoords[vertexID];
        return out;
    }

    fragment float4 readerLyricsFragment(
        ReaderLyricsVertexOut in [[stage_in]],
        texture2d<float> textTexture [[texture(0)]],
        constant ReaderLyricsMetalUniforms &uniforms [[buffer(0)]]
    ) {
        constexpr sampler textSampler(coord::normalized, address::clamp_to_edge, filter::linear);
        float4 color = textTexture.sample(textSampler, in.texCoord);

        if (uniforms.drawsSelectedTexture > 0.5) {
            const float progress = clamp(uniforms.progressFraction, 0.0, 1.0);
            if (progress <= 0.0) {
                return float4(0.0);
            }
            if (progress < 1.0) {
                const float feather = max(uniforms.featherFraction, 0.0001);
                const float edge = uniforms.isRightToLeft > 0.5 ? 1.0 - progress : progress;
                float mask;
                if (uniforms.isRightToLeft > 0.5) {
                    mask = smoothstep(edge - feather, edge + feather, in.texCoord.x);
                } else {
                    mask = 1.0 - smoothstep(edge - feather, edge + feather, in.texCoord.x);
                }
                color.rgb *= mask;
                color.a *= mask;
            }
        }

        return color;
    }
    """
}

final class ReaderLyricsScrollView: NSScrollView {
    private var lastSyncedDocumentBounds: NSRect?
    private var needsDocumentFrameSync = true

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point),
              let textView = documentView as? ReaderLyricsHitTestTextView,
              let hitBounds = renderedTextHitBounds(in: textView) else {
            return nil
        }

        let textPoint = textView.convert(point, from: self)
        guard hitBounds.contains(textPoint) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func layout() {
        super.layout()
        syncDocumentViewFrame()
    }

    func markNeedsDocumentFrameSync() {
        needsDocumentFrameSync = true
    }

    func syncDocumentViewFrame() {
        guard let textView = documentView as? ReaderLyricsHitTestTextView else { return }
        let bounds = contentView.bounds
        guard needsDocumentFrameSync || lastSyncedDocumentBounds != bounds else { return }
        textView.frame = contentView.bounds
        textView.textContainer?.containerSize = NSSize(
            width: max(contentView.bounds.width, 1),
            height: max(contentView.bounds.height, 1)
        )
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }
        contentView.scroll(to: .zero)
        reflectScrolledClipView(contentView)
        lastSyncedDocumentBounds = bounds
        needsDocumentFrameSync = false
    }

    private func renderedTextHitBounds(in textView: ReaderLyricsHitTestTextView) -> NSRect? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              layoutManager.numberOfGlyphs > 0 else {
            return nil
        }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        return rect.insetBy(dx: -10, dy: -8)
    }
}

final class ReaderLyricsMetalTextContainerView: NSView {
    private let metalView = ReaderLyricsMetalRenderView()
    private let hitTestScrollView = ReaderLyricsScrollView()
    private let hitTestTextView = ReaderLyricsHitTestTextView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        hitTestScrollView.drawsBackground = false
        hitTestScrollView.hasVerticalScroller = false
        hitTestScrollView.hasHorizontalScroller = false
        hitTestScrollView.borderType = .noBorder

        hitTestTextView.isEditable = false
        hitTestTextView.isSelectable = true
        hitTestTextView.drawsBackground = false
        hitTestTextView.textContainerInset = .zero
        hitTestTextView.textContainer?.lineFragmentPadding = 0
        hitTestTextView.textContainer?.widthTracksTextView = true
        hitTestTextView.textContainer?.heightTracksTextView = true
        hitTestTextView.isHorizontallyResizable = false
        hitTestTextView.isVerticallyResizable = false
        hitTestTextView.autoresizingMask = [.width, .height]

        hitTestScrollView.documentView = hitTestTextView
        addSubview(metalView)
        addSubview(hitTestScrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        metalView.frame = bounds
        hitTestScrollView.frame = bounds
        hitTestScrollView.syncDocumentViewFrame()
    }

    func configure(
        text: String,
        scanLength: Int,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        textColor: NSColor,
        upcomingTextColor: NSColor,
        progressFraction: CGFloat,
        progressRatePerSecond: CGFloat,
        isProgressAnimating: Bool,
        lookupHighlightColor: NSColor,
        lookupHighlightTextColor: NSColor,
        isLookupPopupVisible: Bool,
        onSelection: @escaping (String, Int, CGRect) -> Int?
    ) {
        metalView.updateLyrics(
            text: text,
            fontSize: fontSize,
            weight: weight,
            selectedColor: textColor,
            upcomingColor: upcomingTextColor,
            progressFraction: progressFraction,
            progressRatePerSecond: progressRatePerSecond,
            isProgressAnimating: isProgressAnimating
        )

        if hitTestTextView.updateHitTestText(text, fontSize: fontSize, weight: weight) {
            hitTestScrollView.markNeedsDocumentFrameSync()
        }
        hitTestScrollView.syncDocumentViewFrame()
        hitTestTextView.updateLookupHighlightColor(lookupHighlightColor)
        hitTestTextView.updateLookupHighlightTextColor(lookupHighlightTextColor)
        hitTestTextView.onCharacterClicked = { [weak self, weak hitTestTextView] offset, rect in
            guard let self,
                  let hitTestTextView else { return nil }
            guard let candidate = ReaderLyricsSelectionResolver.lookupCandidate(
                in: text,
                utf16Offset: offset,
                scanLength: scanLength
            ) else { return nil }
            let popupRect = popupCoordinateRect(rect, from: hitTestTextView)
            guard let matchedCount = onSelection(candidate.text, candidate.utf16Start, popupRect) else {
                return nil
            }
            let matchedText = String(candidate.text.prefix(matchedCount))
            return ReaderLyricsSelectionResolver.highlightRange(for: candidate, matchedText: matchedText)
        }

        if !isLookupPopupVisible {
            hitTestTextView.clearLookupHighlight()
        }
    }

    private func popupCoordinateRect(_ rect: NSRect, from sourceView: NSView) -> CGRect {
        guard let contentView = window?.contentView else {
            let converted = convert(rect, from: sourceView)
            return CGRect(
                x: converted.minX,
                y: converted.minY,
                width: max(converted.width, 1),
                height: max(converted.height, 1)
            )
        }

        let converted = contentView.convert(rect, from: sourceView)
        let topSafeAreaInset = contentView.safeAreaInsets.top
        return ReaderLyricsPopupCoordinateSpace.popupRect(
            convertedRect: converted,
            contentBounds: contentView.bounds,
            isContentViewFlipped: contentView.isFlipped,
            topSafeAreaInset: topSafeAreaInset
        )
    }
}

struct ReaderLyricsSelectableTextView: NSViewRepresentable {
    let text: String
    let scanLength: Int
    let fontSize: CGFloat
    let weight: NSFont.Weight
    let textColor: Color
    let upcomingTextColor: Color
    let progressFraction: CGFloat
    let progressRatePerSecond: CGFloat
    let isProgressAnimating: Bool
    let lookupHighlightColor: Color
    let lookupHighlightTextColor: Color
    let isLookupPopupVisible: Bool
    var onSelection: (String, Int, CGRect) -> Int?

    func makeNSView(context: Context) -> ReaderLyricsMetalTextContainerView {
        let container = ReaderLyricsMetalTextContainerView()
        updateContainer(container)
        return container
    }

    func updateNSView(_ container: ReaderLyricsMetalTextContainerView, context: Context) {
        updateContainer(container)
    }

    private func updateContainer(_ container: ReaderLyricsMetalTextContainerView) {
        container.configure(
            text: text,
            scanLength: scanLength,
            fontSize: fontSize,
            weight: weight,
            textColor: NSColor(textColor),
            upcomingTextColor: NSColor(upcomingTextColor),
            progressFraction: progressFraction,
            progressRatePerSecond: progressRatePerSecond,
            isProgressAnimating: isProgressAnimating,
            lookupHighlightColor: NSColor(lookupHighlightColor),
            lookupHighlightTextColor: NSColor(lookupHighlightTextColor),
            isLookupPopupVisible: isLookupPopupVisible,
            onSelection: onSelection
        )
    }
}

private struct ReaderLyricsVerticalGlyphLayout {
    let text: String
    let utf16Start: Int
    let utf16Length: Int
    let rect: NSRect
}

final class ReaderLyricsVerticalHitTestView: NSView {
    var onCharacterClicked: ((Int, CGRect) -> NSRange?)?

    private var text = ""
    private var scanLength = 0
    private var fontSize: CGFloat = 34
    private var weight = NSFont.Weight.bold
    private var textColor = NSColor.white
    private var lookupHighlightColor = NSColor.white.withAlphaComponent(0.18)
    private var lookupHighlightTextColor = NSColor.white
    private var lookupHighlightRange: NSRange?
    private var lastSignature: ReaderLyricsVerticalLayoutSignature?

    override var isFlipped: Bool {
        true
    }

    func clearLookupHighlight() {
        guard lookupHighlightRange != nil else { return }
        lookupHighlightRange = nil
        needsDisplay = true
    }

    func configure(
        text: String,
        scanLength: Int,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        textColor: NSColor,
        lookupHighlightColor: NSColor,
        lookupHighlightTextColor: NSColor,
        isLookupPopupVisible: Bool,
        onSelection: @escaping (String, Int, CGRect) -> Int?
    ) {
        let signature = ReaderLyricsVerticalLayoutSignature(
            text: text,
            scanLength: scanLength,
            fontSize: fontSize.rounded(.toNearestOrAwayFromZero),
            fontWeight: weight.rawValue,
            textColor: Self.colorSignature(textColor),
            lookupHighlightColor: Self.colorSignature(lookupHighlightColor),
            lookupHighlightTextColor: Self.colorSignature(lookupHighlightTextColor)
        )
        if signature != lastSignature {
            lastSignature = signature
            self.text = text
            self.scanLength = scanLength
            self.fontSize = fontSize
            self.weight = weight
            self.textColor = textColor
            self.lookupHighlightColor = lookupHighlightColor
            self.lookupHighlightTextColor = lookupHighlightTextColor
            needsDisplay = true
        }

        onCharacterClicked = { offset, rect in
            guard let candidate = ReaderLyricsSelectionResolver.lookupCandidate(
                    in: text,
                    utf16Offset: offset,
                    scanLength: scanLength
                  ) else { return nil }
            guard let matchedCount = onSelection(candidate.text, candidate.utf16Start, rect) else {
                return nil
            }
            let matchedText = String(candidate.text.prefix(matchedCount))
            return ReaderLyricsSelectionResolver.highlightRange(for: candidate, matchedText: matchedText)
        }

        if !isLookupPopupVisible {
            clearLookupHighlight()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        glyphLayout(at: point) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let glyph = glyphLayout(at: point) else {
            clearLookupHighlight()
            return
        }
        let popupRect = popupCoordinateRect(glyph.rect)
        if let range = onCharacterClicked?(glyph.utf16Start, popupRect) {
            lookupHighlightRange = range
        } else {
            lookupHighlightRange = nil
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let font = NSFont.systemFont(ofSize: min(max(fontSize, 12), 72), weight: weight)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        for glyph in glyphLayouts() {
            let isHighlighted = lookupHighlightRange.map {
                NSIntersectionRange($0, NSRange(location: glyph.utf16Start, length: glyph.utf16Length)).length > 0
            } ?? false
            if isHighlighted {
                let highlightRect = glyph.rect.insetBy(dx: max(glyph.rect.width * 0.12, 2), dy: 1)
                let path = NSBezierPath(roundedRect: highlightRect, xRadius: 4, yRadius: 4)
                lookupHighlightColor.setFill()
                path.fill()
            }

            let color = isHighlighted ? lookupHighlightTextColor : textColor
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle
            ]
            let size = (glyph.text as NSString).size(withAttributes: attributes)
            let drawRect = NSRect(
                x: glyph.rect.midX - size.width / 2,
                y: glyph.rect.midY - size.height / 2,
                width: max(size.width, 1),
                height: max(size.height, 1)
            )
            (glyph.text as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin], attributes: attributes)
        }
    }

    private func glyphLayout(at point: NSPoint) -> ReaderLyricsVerticalGlyphLayout? {
        glyphLayouts().first { $0.rect.insetBy(dx: -2, dy: -1).contains(point) }
    }

    private func popupCoordinateRect(_ rect: NSRect) -> CGRect {
        guard let contentView = window?.contentView else {
            return CGRect(
                x: rect.minX,
                y: rect.minY,
                width: max(rect.width, 1),
                height: max(rect.height, 1)
            )
        }

        let converted = contentView.convert(rect, from: self)
        let topSafeAreaInset = contentView.safeAreaInsets.top
        return ReaderLyricsPopupCoordinateSpace.popupRect(
            convertedRect: converted,
            contentBounds: contentView.bounds,
            isContentViewFlipped: contentView.isFlipped,
            topSafeAreaInset: topSafeAreaInset
        )
    }

    private func glyphLayouts() -> [ReaderLyricsVerticalGlyphLayout] {
        var glyphs: [(text: String, utf16Start: Int, utf16Length: Int)] = []
        var utf16Offset = 0
        for character in text {
            let glyph = String(character)
            let length = glyph.utf16.count
            glyphs.append((glyph, utf16Offset, length))
            utf16Offset += length
        }

        guard !glyphs.isEmpty else { return [] }
        let rowHeight = max(fontSize * 1.08, fontSize + 2)
        let totalHeight = CGFloat(glyphs.count) * rowHeight
        let startY = max((bounds.height - totalHeight) / 2, 0)
        return glyphs.enumerated().map { index, glyph in
            ReaderLyricsVerticalGlyphLayout(
                text: glyph.text,
                utf16Start: glyph.utf16Start,
                utf16Length: glyph.utf16Length,
                rect: NSRect(
                    x: 0,
                    y: startY + CGFloat(index) * rowHeight,
                    width: max(bounds.width, 1),
                    height: rowHeight
                )
            )
        }
    }

    private static func colorSignature(_ color: NSColor) -> String {
        guard let converted = color.usingColorSpace(.deviceRGB) else {
            return color.description
        }
        return [
            converted.redComponent,
            converted.greenComponent,
            converted.blueComponent,
            converted.alphaComponent
        ]
        .map { String(Int(($0 * 1000).rounded())) }
        .joined(separator: ":")
    }
}

private struct ReaderLyricsVerticalLayoutSignature: Equatable {
    let text: String
    let scanLength: Int
    let fontSize: CGFloat
    let fontWeight: CGFloat
    let textColor: String
    let lookupHighlightColor: String
    let lookupHighlightTextColor: String
}

struct ReaderLyricsVerticalSelectableTextView: NSViewRepresentable {
    let text: String
    let scanLength: Int
    let fontSize: CGFloat
    let weight: NSFont.Weight
    let textColor: Color
    let lookupHighlightColor: Color
    let lookupHighlightTextColor: Color
    let isLookupPopupVisible: Bool
    var onSelection: (String, Int, CGRect) -> Int?

    func makeNSView(context: Context) -> ReaderLyricsVerticalHitTestView {
        let view = ReaderLyricsVerticalHitTestView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        updateVerticalView(view)
        return view
    }

    func updateNSView(_ verticalView: ReaderLyricsVerticalHitTestView, context: Context) {
        updateVerticalView(verticalView)
    }

    private func updateVerticalView(_ verticalView: ReaderLyricsVerticalHitTestView) {
        verticalView.configure(
            text: text,
            scanLength: scanLength,
            fontSize: fontSize,
            weight: weight,
            textColor: NSColor(textColor),
            lookupHighlightColor: NSColor(lookupHighlightColor),
            lookupHighlightTextColor: NSColor(lookupHighlightTextColor),
            isLookupPopupVisible: isLookupPopupVisible,
            onSelection: onSelection
        )
    }
}

enum ReaderLyricsTextDirection {
    static func isRightToLeft(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            guard !scalar.properties.isWhitespace,
                  !CharacterSet.punctuationCharacters.contains(scalar),
                  !CharacterSet.symbols.contains(scalar) else {
                continue
            }
            if isRightToLeftScalar(scalar) {
                return true
            }
            if isLeftToRightScalar(scalar) {
                return false
            }
        }
        return false
    }

    private static func isRightToLeftScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF:
            return true
        default:
            return false
        }
    }

    private static func isLeftToRightScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x02AF, 0x0370...0x052F, 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }
}
