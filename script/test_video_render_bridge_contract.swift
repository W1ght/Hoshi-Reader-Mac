import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func source(_ path: String) throws -> String {
    try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let clientHeader = try source("Features/Video/Playback/HSMpvClient.h")
let clientImpl = try source("Features/Video/Playback/HSMpvClient.mm")
let renderView = try source("Features/Video/Playback/MpvRenderView.swift")
let engine = try source("Features/Video/Playback/MpvPlayerEngine.swift")
let displayLinkStopRange = clientImpl.range(of: "[view stopDisplayLink]")
let renderContextFreeRange = clientImpl.range(of: "mpv_render_context_free(contextToFree)")

require(
    clientHeader.contains("@interface HSMpvOpenGLView : NSView")
        && !clientHeader.contains("@interface HSMpvOpenGLView : NSOpenGLView"),
    "video render host should be an NSView backed by a CAOpenGLLayer, not an NSOpenGLView"
)
require(
    clientImpl.contains("@interface HSMpvOpenGLLayer : CAOpenGLLayer")
        && clientImpl.contains("copyCGLPixelFormatForDisplayMask:")
        && clientImpl.contains("copyCGLContextForPixelFormat:")
        && clientImpl.contains("drawInCGLContext:(CGLContextObj)context")
        && clientImpl.contains("forLayerTime:(CFTimeInterval)time")
        && clientImpl.contains("displayTime:(const CVTimeStamp *)timeStamp")
        && !clientImpl.contains("- (void)drawRect:"),
    "video rendering should move from NSOpenGLView.drawRect to a CAOpenGLLayer draw path"
)
require(
    clientImpl.contains("MPV_RENDER_PARAM_ADVANCED_CONTROL")
        && clientImpl.contains("mpv_render_context_update")
        && clientImpl.contains("mpv_render_context_report_swap")
        && clientImpl.contains("MPV_RENDER_PARAM_DEPTH")
        && clientImpl.contains("MPV_RENDER_PARAM_SKIP_RENDERING")
        && clientImpl.contains("MPV_RENDER_UPDATE_FRAME"),
    "video render bridge should use libmpv advanced_control with update/report_swap so mpv does not wait on stale draws"
)
require(
    clientImpl.contains("dispatch_queue_create(\"moe.shishamo.hoshi.video.mpvgl\"")
        && clientImpl.contains("dispatch_async(_mpvGLQueue")
        && clientImpl.contains("- (void)display")
        && clientImpl.contains("[CATransaction begin]")
        && !clientImpl.contains("dispatch_async(dispatch_get_main_queue(), ^{\n        if (target.generation != generation) {\n            return;\n        }\n        HSMpvOpenGLView *view = target.view;\n        [view setNeedsDisplay:YES];")
        && !clientImpl.contains("dispatch_async(dispatch_get_main_queue(), ^{\n        self.renderScheduled = NO;\n        [self setNeedsDisplay];"),
    "mpv render updates should run through a dedicated layer GL queue and display path instead of forcing every frame onto the main queue"
)
require(
    clientImpl.contains("kCGLPFAOpenGLProfile")
        && clientImpl.contains("kCGLOGLPVersion_3_2_Core")
        && clientImpl.contains("kCGLPFAAccelerated")
        && !clientImpl.contains("fallbackAttributes")
        && !clientImpl.contains("kCGLRendererGenericFloatID"),
    "video render bridge should take the IINA-style accelerated OpenGL layer path directly instead of falling back to a software/legacy pixel format"
)
require(
    clientImpl.contains("wantsBestResolutionOpenGLSurface = YES"),
    "video render host should request a best-resolution OpenGL surface"
)
require(
    clientImpl.contains("backingScaleFactor")
        && clientImpl.contains("contentsScale")
        && clientImpl.contains("NSWindowDidChangeBackingPropertiesNotification"),
    "video render host should follow the active window backing scale"
)
require(
    clientImpl.contains("kCGLPFAColorSize")
        && clientImpl.contains("kCGLPFAColorFloat")
        && clientImpl.contains("kCAContentsFormatRGBA16Float")
        && clientImpl.contains("_bufferDepth = 16")
        && clientImpl.contains("_bufferDepth = 8"),
    "video render host should prefer a half-float framebuffer and fall back to 8-bit"
)
require(
    clientImpl.contains("MPV_RENDER_PARAM_ICC_PROFILE")
        && clientImpl.contains("icc-profile-auto"),
    "SDR output should provide the active display ICC profile to libmpv"
)
require(
    clientImpl.contains("wantsExtendedDynamicRangeOpenGLSurface = YES")
        && clientImpl.contains("wantsExtendedDynamicRangeContent"),
    "the render host should support EDR while keeping content state explicit"
)
require(
    clientImpl.contains("target-prim")
        && clientImpl.contains("target-trc")
        && clientImpl.contains("kCGColorSpaceITUR_2100_PQ"),
    "HDR output should configure mpv and the layer for PQ EDR"
)
require(
    clientImpl.contains("applySDRDisplayColorConfiguration"),
    "HDR disable or fallback should restore calibrated SDR output"
)
require(
    clientImpl.contains("CVDisplayLinkCreateWithActiveCGDisplays")
        && clientImpl.contains("CVDisplayLinkSetCurrentCGDisplay")
        && clientImpl.contains("CVDisplayLinkSetOutputCallback"),
    "video render pacing should follow the active display"
)
require(
    clientImpl.contains("display-fps-override"),
    "libmpv should receive the active display refresh rate"
)
require(
    displayLinkStopRange != nil
        && renderContextFreeRange != nil
        && displayLinkStopRange!.lowerBound < renderContextFreeRange!.lowerBound,
    "display link should stop before the render context is freed"
)
require(
    clientImpl.contains("usesImmediateSwapReporting"),
    "display-link failure should preserve immediate swap reporting"
)
require(
    renderView.contains("HSMpvOpenGLView(frame:")
        && engine.contains("func attach(to view: HSMpvOpenGLView) -> Bool"),
    "SwiftUI should keep the same narrow NSViewRepresentable boundary around the native mpv render host"
)

print("Video render bridge contract tests passed")
