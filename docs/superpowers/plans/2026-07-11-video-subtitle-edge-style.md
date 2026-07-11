# Video Subtitle Edge Style Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Use superpowers:subagent-driven-development only if the user explicitly requests agent delegation. Steps use checkbox (`- [ ]`) syntax for tracking. Repository policy forbids commits unless the user explicitly requests one, so this plan leaves changes uncommitted by default.

**Goal:** Replace Video's single soft-shadow control with a compact edge-style selector and one strength slider that provide a darker asbplayer-inspired glyph shadow, optional glyph outline, and a readable high-contrast default.

**Architecture:** Add a small Video-only value layer that owns the four style cases, migration resolution, and deterministic font-size-aware rendering recipe. Persist the selected style and normalized strength in `UserConfig`, pass the recipe through the existing `SubtitleOverlayView`, and apply native TextKit shadow/outline attributes to the existing interactive `NSTextView` without changing text layout, hit testing, lookup offsets, subtitle parsing, or libmpv.

**Tech Stack:** Swift 6, SwiftUI, AppKit/TextKit 1 (`NSTextView`, `NSLayoutManager`, attributed-string stroke attributes), Core Graphics shadow compositing, `UserDefaults`, String Catalog localization, standalone Swift tests and source-contract scripts, Xcode Light/Video schemes.

## Global Constraints

- Native macOS 26.0+ is the only target.
- Keep Video subtitle backgrounds transparent by default; do not add glass, material, a rectangle, or a subtitle card.
- Edge colors are fixed black. Do not add shadow color, outline color, shadow offset, blur, opacity, or outline-width controls.
- New users default to `highContrast` with strength `0.5`; legacy users with an explicit `videoSubtitleShadowRadius` migrate to `softShadow` with `legacyRadius / 10` strength.
- The default 36pt/50% High Contrast recipe is a 1.875pt glyph outline; Soft Shadow at the same settings uses one zero-offset 3pt native glyph shadow.
- Keep lookup highlights, native selection, click lookup, Shift-hover lookup, masking, popup geometry, cue timing, transcript, mining, and mpv subtitle behavior unchanged.
- Light must not link, copy, or runtime-discover Video/libmpv code.
- Add Chinese and English user-visible strings through `Localizable.xcstrings`.
- Use `apply_patch` for hand edits. Do not commit, push, tag, or release unless the user explicitly authorizes it.

### Verified implementation adjustment

The original Task 1/Task 3 examples below describe a four-pass custom-layout-manager experiment. Render QA showed that repeated `NSLayoutManager` glyph drawing, destination-over compositing, and parallel sibling text layers could darken the white glyph fill, create black blocks in transparent renders, or produce visible duplicate glyphs. The publishable implementation therefore keeps one interactive `NSTextView`: Soft Shadow applies one native zero-offset `NSShadow`, Clear Outline applies the calculated native negative stroke width, and High Contrast applies a stronger outline capped at 2.5pt without combining it with a shadow. The focused tests and source contracts were updated to lock this stable behavior; any four-pass assertions or sample code retained in the original RED/GREEN record are superseded by this adjustment.

## File Map

- Create `Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift`: style enum, migration resolver, normalized preference value, font-size-aware recipe, and shared localized style titles.
- Create `script/test_video_subtitle_edge_style.swift`: executable unit tests for defaults, migration, clamping, invalid data, and all rendering recipes.
- Modify `Core/UserConfig.swift`: persistence, legacy projection, initialization/migration, and Restore Defaults.
- Modify `Features/Video/Subtitles/SubtitleOverlayView.swift`: replace row-level shadow with edge-style/strength flow and glyph recipe.
- Modify `Features/Video/Subtitles/InteractiveSubtitleTextView.swift`: apply a native zero-offset `NSShadow` or negative stroke-width attribute to the existing TextKit storage without changing layout or adding sibling text layers.
- Modify `Features/Video/Subtitles/SubtitleOverlayRowHeightMeasurer.swift`: reserve recipe-derived vertical allowance instead of legacy shadow radius.
- Modify `Features/Video/VideoPlayerScreen.swift`: pass the new shared preferences into the overlay.
- Modify `Features/Settings/VideoSettingsView.swift`: full-settings style picker and strength slider.
- Modify `Features/Video/VideoInspectorView.swift`: compact in-player style picker and strength slider.
- Modify `Localizable.xcstrings`: edge-control labels and style names.
- Modify `script/test_video_settings_contract.swift`, `script/test_video_liquid_glass_contract.swift`, and `script/test_video_subtitles.swift`: persistence/UI/rendering contracts and height regression coverage.
- Modify `docs/TODO.md`, `docs/ARCHITECTURE_REFACTORING.md`, and `docs/CHANGELOG.md`: current state, architecture boundary, and user-visible change.

---

### Task 1: Add the pure edge preference, migration, and rendering recipe

**Files:**
- Create: `Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift`
- Create: `script/test_video_subtitle_edge_style.swift`

**Interfaces:**
- Consumes: only `Foundation`, `CoreGraphics`, and SwiftUI's `LocalizedStringKey`.
- Produces: `VideoSubtitleEdgeStyle`, `VideoSubtitleEdgePreference`, `VideoSubtitleEdgePreferenceResolver.resolve(...)`, `VideoSubtitleEdgePreferenceResolver.normalizedStrength(_:)`, and `VideoSubtitleEdgeRecipe.make(style:strength:fontSize:)`.

- [x] **Step 1: Write the failing executable unit test**

Create `script/test_video_subtitle_edge_style.swift` with the complete cases below:

```swift
import CoreGraphics
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func expectClose(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
    expect(abs(actual - expected) < 0.0001, "\(message): got \(actual), expected \(expected)")
}

@main
private enum VideoSubtitleEdgeStyleTests {
    static func main() {
        let fresh = VideoSubtitleEdgePreferenceResolver.resolve(
            edgeStyleRawValue: nil,
            edgeStrength: nil,
            legacyShadowRadius: nil
        )
        expect(fresh == .init(style: .highContrast, strength: 0.5), "fresh installs should use High Contrast at 50%")

        let legacy = VideoSubtitleEdgePreferenceResolver.resolve(
            edgeStyleRawValue: nil,
            edgeStrength: nil,
            legacyShadowRadius: 7.5
        )
        expect(legacy == .init(style: .softShadow, strength: 0.75), "legacy radius should migrate to Soft Shadow")

        let invalid = VideoSubtitleEdgePreferenceResolver.resolve(
            edgeStyleRawValue: "future-value",
            edgeStrength: 3,
            legacyShadowRadius: 2
        )
        expect(invalid == .init(style: .highContrast, strength: 1), "invalid new data should fall back and clamp without reusing legacy data")
        expect(VideoSubtitleEdgePreferenceResolver.normalizedStrength(.nan) == 0.5, "non-finite strength should fall back to 50%")

        let highContrast = VideoSubtitleEdgeRecipe.make(style: .highContrast, strength: 0.5, fontSize: 36)
        expectClose(highContrast.shadowRadius, 3, "default shadow radius")
        expect(highContrast.shadowPassCount == 4, "default shadow should use four passes")
        expectClose(highContrast.outlineWidth, 0.9375, "default High Contrast outline width")

        let soft = VideoSubtitleEdgeRecipe.make(style: .softShadow, strength: 0.5, fontSize: 36)
        expectClose(soft.shadowRadius, 3, "Soft Shadow radius")
        expect(soft.shadowPassCount == 4 && soft.outlineWidth == 0, "Soft Shadow should not add an outline")

        let outline = VideoSubtitleEdgeRecipe.make(style: .clearOutline, strength: 0.5, fontSize: 36)
        expect(outline.shadowPassCount == 0 && outline.shadowRadius == 0, "Clear Outline should not add a shadow")
        expectClose(outline.outlineWidth, 1.25, "Clear Outline width")

        let off = VideoSubtitleEdgeRecipe.make(style: .off, strength: 1, fontSize: 72)
        expect(off == .none, "Off should suppress every edge effect")
        let zero = VideoSubtitleEdgeRecipe.make(style: .highContrast, strength: 0, fontSize: 36)
        expect(zero == .none, "zero strength should suppress every edge effect")

        let maximum = VideoSubtitleEdgeRecipe.make(style: .highContrast, strength: 1, fontSize: 72)
        expectClose(maximum.shadowRadius, 8, "shadow radius should cap at 8pt")
        expectClose(maximum.outlineWidth, 3, "High Contrast outline should derive from the capped 4pt Clear Outline")

        print("Video subtitle edge style tests passed")
    }
}
```

- [x] **Step 2: Run the unit test and verify RED**

Run:

```bash
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift script/test_video_subtitle_edge_style.swift -o /tmp/hoshi-test-video-subtitle-edge-style && /tmp/hoshi-test-video-subtitle-edge-style
```

Expected: compilation fails because `VideoSubtitleEdgeStyle.swift` and its types do not exist.

- [x] **Step 3: Implement the complete pure value layer**

Create `Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift`:

```swift
#if HOSHI_VIDEO
import CoreGraphics
import Foundation
import SwiftUI

enum VideoSubtitleEdgeStyle: String, CaseIterable, Codable {
    case off
    case softShadow
    case clearOutline
    case highContrast

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .off: "Off"
        case .softShadow: "Soft Shadow"
        case .clearOutline: "Clear Outline"
        case .highContrast: "High Contrast"
        }
    }
}

struct VideoSubtitleEdgePreference: Equatable {
    let style: VideoSubtitleEdgeStyle
    let strength: Double
}

enum VideoSubtitleEdgePreferenceResolver {
    static func normalizedStrength(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    static func resolve(
        edgeStyleRawValue: String?,
        edgeStrength: Double?,
        legacyShadowRadius: Double?
    ) -> VideoSubtitleEdgePreference {
        if let edgeStyleRawValue {
            return VideoSubtitleEdgePreference(
                style: VideoSubtitleEdgeStyle(rawValue: edgeStyleRawValue) ?? .highContrast,
                strength: normalizedStrength(edgeStrength)
            )
        }
        if let legacyShadowRadius {
            return VideoSubtitleEdgePreference(
                style: .softShadow,
                strength: normalizedStrength(legacyShadowRadius / 10)
            )
        }
        return VideoSubtitleEdgePreference(style: .highContrast, strength: 0.5)
    }
}

struct VideoSubtitleEdgeRecipe: Equatable {
    let shadowRadius: CGFloat
    let shadowPassCount: Int
    let outlineWidth: CGFloat

    static let none = VideoSubtitleEdgeRecipe(shadowRadius: 0, shadowPassCount: 0, outlineWidth: 0)

    var layoutAllowance: CGFloat {
        ceil(max(shadowRadius * 2, outlineWidth * 2))
    }

    static func make(
        style: VideoSubtitleEdgeStyle,
        strength: Double,
        fontSize: CGFloat
    ) -> VideoSubtitleEdgeRecipe {
        let normalized = CGFloat(VideoSubtitleEdgePreferenceResolver.normalizedStrength(strength))
        guard style != .off, normalized > 0 else { return .none }
        let scale = min(max(fontSize / 36, 0.5), 2)
        let shadowRadius = min(8, 6 * normalized * scale)
        let clearOutlineWidth = min(4, 2.5 * normalized * scale)

        switch style {
        case .off:
            return .none
        case .softShadow:
            return VideoSubtitleEdgeRecipe(shadowRadius: shadowRadius, shadowPassCount: 4, outlineWidth: 0)
        case .clearOutline:
            return VideoSubtitleEdgeRecipe(shadowRadius: 0, shadowPassCount: 0, outlineWidth: clearOutlineWidth)
        case .highContrast:
            return VideoSubtitleEdgeRecipe(
                shadowRadius: shadowRadius,
                shadowPassCount: 4,
                outlineWidth: clearOutlineWidth * 0.75
            )
        }
    }
}
#endif
```

- [x] **Step 4: Run the unit test GREEN**

Run the Step 2 command again.

Expected: `Video subtitle edge style tests passed` and exit 0.

- [x] **Step 5: Review Task 1 diff**

Run:

```bash
git diff --check
git diff -- Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift script/test_video_subtitle_edge_style.swift
```

Expected: no whitespace errors; only the value layer and its focused test are present. Do not commit unless explicitly authorized.

---

### Task 2: Persist the new controls and migrate the legacy shadow setting

**Files:**
- Modify: `Core/UserConfig.swift`
- Modify: `script/test_video_settings_contract.swift`

**Interfaces:**
- Consumes: `VideoSubtitleEdgePreferenceResolver` from Task 1 and legacy key `videoSubtitleShadowRadius`.
- Produces: observable `videoSubtitleEdgeStyle`, observable/clamped `videoSubtitleEdgeStrength`, a compatibility `videoSubtitleShadowRadius` projection, migrated initialization, and new Restore Defaults behavior.

- [x] **Step 1: Add failing persistence and migration contracts**

In `script/test_video_settings_contract.swift`, read the new value file and add these exact checks near the existing subtitle appearance checks:

```swift
let subtitleEdgeStyle = read("Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift")

require(
    subtitleEdgeStyle,
    contains: "enum VideoSubtitleEdgeStyle: String, CaseIterable, Codable",
    "video subtitle edge style should be a stable Codable preference"
)
require(
    userConfig,
    contains: "var videoSubtitleEdgeStyle: VideoSubtitleEdgeStyle",
    "video subtitle edge style should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "var videoSubtitleEdgeStrength: Double",
    "video subtitle edge strength should be centralized in UserConfig"
)
require(
    userConfig,
    contains: "VideoSubtitleEdgePreferenceResolver.resolve(",
    "UserConfig should resolve new defaults and legacy shadow migration through the tested resolver"
)
require(
    userConfig,
    contains: "legacyShadowRadius: defaults.object(forKey: \"videoSubtitleShadowRadius\") as? Double",
    "UserConfig should migrate an explicitly stored legacy shadow radius"
)
require(
    userConfig,
    contains: "videoSubtitleEdgeStyle = .highContrast",
    "Restore Defaults should restore the High Contrast style"
)
require(
    userConfig,
    contains: "videoSubtitleEdgeStrength = 0.5",
    "Restore Defaults should restore 50% edge strength"
)
```

Remove the old requirement that treats `videoSubtitleShadowRadius` as the active centralized appearance preference. Keep a requirement for the legacy key only as migration/compatibility data.

- [x] **Step 2: Run settings contract and verify RED**

Run: `swift script/test_video_settings_contract.swift`

Expected: failure naming the missing `videoSubtitleEdgeStyle` or `videoSubtitleEdgeStrength` property.

- [x] **Step 3: Replace the stored shadow property with new persisted preferences**

Inside `UserConfig`'s `#if HOSHI_VIDEO` preference block, replace the stored legacy property with:

```swift
var videoSubtitleEdgeStyle: VideoSubtitleEdgeStyle {
    didSet {
        Self.defaults.set(videoSubtitleEdgeStyle.rawValue, forKey: "videoSubtitleEdgeStyle")
    }
}

var videoSubtitleEdgeStrength: Double {
    didSet {
        let normalized = VideoSubtitleEdgePreferenceResolver.normalizedStrength(videoSubtitleEdgeStrength)
        guard videoSubtitleEdgeStrength == normalized else {
            videoSubtitleEdgeStrength = normalized
            return
        }
        Self.defaults.set(normalized, forKey: "videoSubtitleEdgeStrength")
        Self.defaults.set(normalized * 10, forKey: "videoSubtitleShadowRadius")
    }
}

var videoSubtitleShadowRadius: Double {
    get { videoSubtitleEdgeStrength * 10 }
    set {
        videoSubtitleEdgeStyle = .softShadow
        videoSubtitleEdgeStrength = newValue / 10
    }
}
```

The computed legacy property preserves compatibility for any remaining internal caller while the new strength setter continues maintaining the old UserDefaults projection.

- [x] **Step 4: Resolve defaults and legacy migration in `init()`**

Replace the old `self.videoSubtitleShadowRadius = ...` initialization with:

```swift
let subtitleEdgePreference = VideoSubtitleEdgePreferenceResolver.resolve(
    edgeStyleRawValue: defaults.string(forKey: "videoSubtitleEdgeStyle"),
    edgeStrength: defaults.object(forKey: "videoSubtitleEdgeStrength") as? Double,
    legacyShadowRadius: defaults.object(forKey: "videoSubtitleShadowRadius") as? Double
)
self.videoSubtitleEdgeStyle = subtitleEdgePreference.style
self.videoSubtitleEdgeStrength = subtitleEdgePreference.strength
```

Because property observers do not run during initialization, this reads migration data without rewriting either defaults key merely by launching or switching variants.

- [x] **Step 5: Update Restore Defaults**

In `resetVideoSubtitleAppearance()`, replace `videoSubtitleShadowRadius = 3` with:

```swift
videoSubtitleEdgeStyle = .highContrast
videoSubtitleEdgeStrength = 0.5
```

- [x] **Step 6: Run persistence tests GREEN**

Run:

```bash
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift script/test_video_subtitle_edge_style.swift -o /tmp/hoshi-test-video-subtitle-edge-style && /tmp/hoshi-test-video-subtitle-edge-style
swift script/test_video_settings_contract.swift
```

Expected: both commands exit 0.

- [x] **Step 7: Review Task 2 diff**

Run:

```bash
git diff --check
git diff -- Core/UserConfig.swift script/test_video_settings_contract.swift
```

Expected: the old key is retained only for resolver input and compatibility projection; new properties are enclosed by `#if HOSHI_VIDEO`. Do not commit unless explicitly authorized.

---

### Task 3: Render stable shadow and outline at the AppKit glyph boundary

**Files:**
- Modify: `Features/Video/Subtitles/InteractiveSubtitleTextView.swift`
- Modify: `Features/Video/Subtitles/SubtitleOverlayView.swift`
- Modify: `Features/Video/Subtitles/SubtitleOverlayRowHeightMeasurer.swift`
- Modify: `Features/Video/VideoPlayerScreen.swift`
- Modify: `script/test_video_liquid_glass_contract.swift`
- Modify: `script/test_video_settings_contract.swift`
- Modify: `script/test_video_subtitles.swift`

**Interfaces:**
- Consumes: `VideoSubtitleEdgeRecipe.make(style:strength:fontSize:)` and new `UserConfig` properties.
- Produces: `edgeRecipe` input on `InteractiveSubtitleTextView`, a `SubtitleEdgeLayoutManager` glyph renderer, recipe-derived row-height allowance, and no row-level SwiftUI shadow.

- [x] **Step 1: Add failing rendering contracts**

Update the subtitle assertions in `script/test_video_liquid_glass_contract.swift` and `script/test_video_settings_contract.swift` to require:

```swift
require(
    subtitles.contains("let edgeStyle: VideoSubtitleEdgeStyle")
        && subtitles.contains("let edgeStrength: Double")
        && subtitles.contains("VideoSubtitleEdgeRecipe.make(")
        && !subtitles.contains(".shadow(color: shadowColor"),
    "subtitle edges should use a glyph recipe instead of a row-level SwiftUI shadow"
)
require(
    interactiveSubtitles.contains("let edgeRecipe: VideoSubtitleEdgeRecipe")
        && interactiveSubtitles.contains("final class SubtitleEdgeLayoutManager: NSLayoutManager")
        && interactiveSubtitles.contains("override func showCGGlyphs(")
        && interactiveSubtitles.contains("graphicsContext.setShadow(")
        && interactiveSubtitles.contains("graphicsContext.setBlendMode(.destinationOver)")
        && interactiveSubtitles.contains("super.showCGGlyphs(")
        && interactiveSubtitles.contains(".strokeWidth")
        && interactiveSubtitles.contains(".strokeColor"),
    "interactive subtitles should draw repeated shadow and outline at the glyph boundary"
)
require(
    player.contains("edgeStyle: userConfig.videoSubtitleEdgeStyle")
        && player.contains("edgeStrength: userConfig.videoSubtitleEdgeStrength")
        && !player.contains("shadowRadius: userConfig.videoSubtitleShadowRadius"),
    "the video screen should pass the new edge preferences into the overlay"
)
```

Replace old `shadowRadius` overlay-parameter requirements rather than keeping both paths.

- [x] **Step 2: Update the height regression test and verify RED**

In `script/test_video_subtitles.swift`, construct the recipe and pass its allowance:

```swift
let wrappedEdgeRecipe = VideoSubtitleEdgeRecipe.make(
    style: .highContrast,
    strength: 0.5,
    fontSize: 43
)
let measuredLargeSubtitleHeight = SubtitleOverlayRowHeightMeasurer.height(
    for: wrappedSubtitleText,
    availableWidth: 360,
    fontFamily: "",
    fontSize: 43,
    fontWeight: 700,
    edgeAllowance: wrappedEdgeRecipe.layoutAllowance
)
```

Run:

```bash
swift script/test_video_liquid_glass_contract.swift
swift script/test_video_settings_contract.swift
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Models/Subtitle.swift Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift Features/Video/Subtitles/SubtitleParser.swift Features/Video/Subtitles/SubtitleCueStore.swift Features/Video/Subtitles/SubtitleOverlayRowHeightMeasurer.swift script/test_video_subtitles.swift -o /tmp/hoshi-test-video-subtitles && /tmp/hoshi-test-video-subtitles
```

Expected: contracts fail on missing edge inputs and the subtitle test fails to compile because `edgeAllowance` is not yet accepted.

- [x] **Step 3: Add a custom glyph-drawing layout manager**

Add this private layout manager above `ClickableSubtitleTextView`:

```swift
private final class SubtitleEdgeLayoutManager: NSLayoutManager {
    var edgeRecipe: VideoSubtitleEdgeRecipe = .none {
        didSet { invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage?.length ?? 0)) }
    }

    override func showCGGlyphs(
        _ glyphs: UnsafePointer<CGGlyph>,
        positions: UnsafePointer<CGPoint>,
        count glyphCount: Int,
        font: NSFont,
        textMatrix: CGAffineTransform,
        attributes: [NSAttributedString.Key: Any] = [:],
        in graphicsContext: CGContext
    ) {
        var finalAttributes = attributes
        if edgeRecipe.outlineWidth > 0, font.pointSize > 0 {
            let percentage = -(edgeRecipe.outlineWidth / font.pointSize * 100)
            finalAttributes[.strokeColor] = NSColor.black
            finalAttributes[.strokeWidth] = NSNumber(value: Double(percentage))
        }
        super.showCGGlyphs(
            glyphs,
            positions: positions,
            count: glyphCount,
            font: font,
            textMatrix: textMatrix,
            attributes: finalAttributes,
            in: graphicsContext
        )

        if edgeRecipe.shadowPassCount > 0, edgeRecipe.shadowRadius > 0 {
            for _ in 0..<edgeRecipe.shadowPassCount {
                graphicsContext.saveGState()
                graphicsContext.setBlendMode(.destinationOver)
                graphicsContext.setShadow(
                    offset: .zero,
                    blur: edgeRecipe.shadowRadius,
                    color: NSColor.black.cgColor
                )
                super.showCGGlyphs(
                    glyphs,
                    positions: positions,
                    count: glyphCount,
                    font: font,
                    textMatrix: textMatrix,
                    attributes: attributes,
                    in: graphicsContext
                )
                graphicsContext.restoreGState()
            }
        }
    }
}
```

The final fill/outline is drawn exactly once. Each shadow call then receives the unmodified run attributes, so its mask comes from the original glyphs, and `.destinationOver` keeps both the repeated source glyph and its shadow behind the already-rendered fill, outline, and lookup highlight. The negative stroke percentage preserves glyph fill per Apple's attributed-string contract, and every Core Graphics shadow pass restores graphics state before the next pass.

- [x] **Step 4: Install the layout manager and pass the recipe in `InteractiveSubtitleTextView`**

Add:

```swift
let edgeRecipe: VideoSubtitleEdgeRecipe
```

In `makeNSView`, replace the convenience `ClickableSubtitleTextView()` construction with the existing TextKit 1 ownership chain:

```swift
let textStorage = NSTextStorage()
let layoutManager = SubtitleEdgeLayoutManager()
let textContainer = NSTextContainer(containerSize: scrollView.bounds.size)
textStorage.addLayoutManager(layoutManager)
layoutManager.addTextContainer(textContainer)
let textView = ClickableSubtitleTextView(frame: scrollView.bounds, textContainer: textContainer)
layoutManager.edgeRecipe = edgeRecipe
```

Apply the same existing container padding, tracking, resizing, font, color, and lookup setup after construction. In `updateNSView`, after updating string/font/color, set:

```swift
(textView.layoutManager as? SubtitleEdgeLayoutManager)?.edgeRecipe = edgeRecipe
```

Do not add stroke attributes to `NSTextStorage`; that would make the repeated shadow use the outlined mask. The custom layout manager changes drawing only, so string replacement, font-size changes, lookup temporary attributes, selection, hit testing, layout, and UTF-16 ranges keep their current behavior.

- [x] **Step 5: Replace the row-level shadow pipeline**

In `SubtitleOverlayView` and `SubtitleCueMaskRow`:

```swift
let edgeStyle: VideoSubtitleEdgeStyle
let edgeStrength: Double

private var edgeRecipe: VideoSubtitleEdgeRecipe {
    VideoSubtitleEdgeRecipe.make(
        style: edgeStyle,
        strength: edgeStrength,
        fontSize: CGFloat(min(max(fontSize, 12), 72))
    )
}
```

Pass `edgeRecipe` to `InteractiveSubtitleTextView`. Delete `.shadow(color:radius:y:)`, `normalizedShadowRadius`, and `shadowColor`. Keep background, mask blur/opacity, hover behavior, padding, and popup geometry in their existing order.

- [x] **Step 6: Reserve edge-derived row height**

Change `SubtitleOverlayRowHeightMeasurer.height` from `shadowRadius: Double` to `edgeAllowance: CGFloat`, then calculate:

```swift
let normalizedEdgeAllowance = max(edgeAllowance, 0)
return max(32, ceil(max(usedHeight, fontLineHeight) + normalizedEdgeAllowance + 2))
```

Call it from `SubtitleCueMaskRow.rowHeight` with `edgeRecipe.layoutAllowance`.

- [x] **Step 7: Pass the new preferences from `VideoPlayerScreen`**

Replace the old overlay argument with:

```swift
edgeStyle: userConfig.videoSubtitleEdgeStyle,
edgeStrength: userConfig.videoSubtitleEdgeStrength,
```

- [x] **Step 8: Run rendering and regression tests GREEN**

Run:

```bash
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift script/test_video_subtitle_edge_style.swift -o /tmp/hoshi-test-video-subtitle-edge-style && /tmp/hoshi-test-video-subtitle-edge-style
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Models/Subtitle.swift Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift Features/Video/Subtitles/SubtitleParser.swift Features/Video/Subtitles/SubtitleCueStore.swift Features/Video/Subtitles/SubtitleOverlayRowHeightMeasurer.swift script/test_video_subtitles.swift -o /tmp/hoshi-test-video-subtitles && /tmp/hoshi-test-video-subtitles
swift script/test_video_liquid_glass_contract.swift
swift script/test_video_settings_contract.swift
xcrun swiftc -parse-as-library script/test_mining_context_ui_contract.swift -o /tmp/test_mining_context_ui_contract && /tmp/test_mining_context_ui_contract
```

Expected: every command exits 0; the mining-context UI contract confirms native selection and lookup highlighting remain present.

- [x] **Step 9: Review Task 3 diff against AppKit boundaries**

Run:

```bash
git diff --check
git diff -- Features/Video/Subtitles/InteractiveSubtitleTextView.swift Features/Video/Subtitles/SubtitleOverlayView.swift Features/Video/Subtitles/SubtitleOverlayRowHeightMeasurer.swift Features/Video/VideoPlayerScreen.swift script/test_video_liquid_glass_contract.swift script/test_video_settings_contract.swift script/test_video_subtitles.swift
```

Expected: no changes to subtitle parsing, cue timing, lookup candidate resolution, mining context, or mpv. Do not commit unless explicitly authorized.

---

### Task 4: Replace the Shadow slider in both UI surfaces and localize it

**Files:**
- Modify: `Features/Settings/VideoSettingsView.swift`
- Modify: `Features/Video/VideoInspectorView.swift`
- Modify: `Localizable.xcstrings`
- Modify: `script/test_video_settings_contract.swift`

**Interfaces:**
- Consumes: `VideoSubtitleEdgeStyle.allCases`, `localizedTitle`, `UserConfig.videoSubtitleEdgeStyle`, and `UserConfig.videoSubtitleEdgeStrength`.
- Produces: one style menu and one `0...100%` strength slider in both settings surfaces, with no edge-color controls.

- [x] **Step 1: Add failing UI and localization contracts**

Replace the old UI binding checks in `script/test_video_settings_contract.swift` with:

```swift
for subtitleEdgeBinding in [
    "$userConfig.videoSubtitleEdgeStyle",
    "$userConfig.videoSubtitleEdgeStrength",
] {
    require(
        settings,
        contains: subtitleEdgeBinding,
        "Video settings should expose compact subtitle edge binding \(subtitleEdgeBinding)"
    )
}
require(
    settings,
    contains: "values: VideoSubtitleEdgeStyle.allCases",
    "Video settings should expose all four edge styles through one menu"
)
require(
    inspector,
    contains: "values: VideoSubtitleEdgeStyle.allCases",
    "Video Inspector should expose the same edge-style menu"
)
require(
    inspector,
    contains: "binding: subtitleEdgeStrength",
    "Video Inspector should expose the shared edge-strength slider"
)
requireCondition(
    !settings.contains("$userConfig.videoSubtitleShadowRadius")
        && !inspector.contains("subtitleShadowRadius"),
    "the legacy Shadow slider should no longer appear in either UI surface"
)
for localizationKey in ["Edge Style", "Edge Strength", "Soft Shadow", "Clear Outline", "High Contrast"] {
    require(
        localization,
        contains: "\"\(localizationKey)\"",
        "subtitle edge UI should localize \(localizationKey)"
    )
}
requireCondition(
    !settings.contains("Shadow Color")
        && !settings.contains("Outline Color")
        && !inspector.contains("Shadow Color")
        && !inspector.contains("Outline Color"),
    "compact subtitle edge controls should not expose advanced colors"
)
```

- [x] **Step 2: Run the settings contract and verify RED**

Run: `swift script/test_video_settings_contract.swift`

Expected: failure naming the missing Edge Style menu or Edge Strength slider.

- [x] **Step 3: Replace the full-settings Shadow row**

In `VideoSettingsView.subtitleAppearanceSection`, replace the legacy Shadow slider with:

```swift
NativeSettingsRow("Edge Style") {
    NativeGlassMenuPicker(
        selection: $userConfig.videoSubtitleEdgeStyle,
        values: VideoSubtitleEdgeStyle.allCases,
        minWidth: 170
    ) { style in
        Text(style.localizedTitle)
    }
    .frame(maxWidth: 260)
}
NativeSettingsSeparator()
NativeSettingsSliderRow(
    title: "Edge Strength",
    value: "\(Int((userConfig.videoSubtitleEdgeStrength * 100).rounded()))%"
) {
    Slider(
        value: $userConfig.videoSubtitleEdgeStrength,
        in: 0...1,
        step: 0.05
    )
    .disabled(userConfig.videoSubtitleEdgeStyle == .off)
}
```

Keep the existing background, vertical position, text color, lookup colors, and Restore Defaults rows.

- [x] **Step 4: Replace the Inspector Shadow row**

Add bindings:

```swift
private var subtitleEdgeStyle: Binding<VideoSubtitleEdgeStyle> {
    Binding(
        get: { userConfig.videoSubtitleEdgeStyle },
        set: { userConfig.videoSubtitleEdgeStyle = $0 }
    )
}

private var subtitleEdgeStrength: Binding<Double> {
    Binding(
        get: { userConfig.videoSubtitleEdgeStrength },
        set: { userConfig.videoSubtitleEdgeStrength = $0 }
    )
}
```

Replace `subtitleShadowRadius` and its slider with:

```swift
HStack(spacing: 12) {
    Text("Edge Style")
        .font(.caption.weight(.medium))
    Spacer(minLength: 12)
    NativeGlassMenuPicker(
        selection: subtitleEdgeStyle,
        values: VideoSubtitleEdgeStyle.allCases,
        minWidth: 150
    ) { style in
        Text(style.localizedTitle)
    }
    .frame(maxWidth: 200)
}

subtitleAppearanceSlider(
    title: "Edge Strength",
    value: "\(Int((userConfig.videoSubtitleEdgeStrength * 100).rounded()))%",
    binding: subtitleEdgeStrength,
    range: 0...1,
    step: 0.05
)
.disabled(userConfig.videoSubtitleEdgeStyle == .off)
```

- [x] **Step 5: Add exact String Catalog entries**

Insert these entries into `Localizable.xcstrings` in the existing JSON style. English uses the source key; Simplified Chinese receives the explicit translation:

```json
"Edge Style": {
  "localizations": {
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "边缘样式" } }
  }
},
"Edge Strength": {
  "localizations": {
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "边缘强度" } }
  }
},
"Soft Shadow": {
  "localizations": {
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "柔和阴影" } }
  }
},
"Clear Outline": {
  "localizations": {
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "清晰描边" } }
  }
},
"High Contrast": {
  "localizations": {
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "高对比度" } }
  }
}
```

Reuse the existing localized `Off` key. Keep the old `Shadow` catalog entry if other release branches or translations still reference it; removing an unused catalog entry is not required for this feature.

- [x] **Step 6: Run UI/localization contracts GREEN**

Run:

```bash
swift script/test_video_settings_contract.swift
swift script/test_video_liquid_glass_contract.swift
jq empty Localizable.xcstrings
```

Expected: all three commands exit 0.

- [x] **Step 7: Review Task 4 diff**

Run:

```bash
git diff --check
git diff -- Features/Settings/VideoSettingsView.swift Features/Video/VideoInspectorView.swift Localizable.xcstrings script/test_video_settings_contract.swift
```

Expected: each settings surface adds only one selector and one slider; no advanced edge controls appear. Do not commit unless explicitly authorized.

---

### Task 5: Update truth sources and complete Light/Video verification

**Files:**
- Modify: `docs/TODO.md`
- Modify: `docs/ARCHITECTURE_REFACTORING.md`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/superpowers/plans/2026-07-11-video-subtitle-edge-style.md` only to check completed steps during execution.

**Interfaces:**
- Consumes: completed persistence, rendering, UI, localization, and fresh verification evidence.
- Produces: accurate project truth sources, a user-visible changelog item, exact Light/Video build evidence, and recorded visual limitations.

- [x] **Step 1: Update current-state and architecture truth sources**

Update the existing Video subtitle appearance bullet in `docs/TODO.md` to state that font, size, edge style, edge strength, and masks are shared between Video Settings and the Inspector, remain Niratan-owned text-only effects, and do not add a subtitle background frame.

Update the Video Learning subtitle boundary in `docs/ARCHITECTURE_REFACTORING.md` to include glyph-level shadow/outline alongside font, size, blur, and opacity while preserving the Niratan-owned overlay and mpv separation.

- [x] **Step 2: Add the user-visible changelog entry**

Under the current release's Chinese and English sections in `docs/CHANGELOG.md`, add:

```markdown
- 改进 Video 字幕在复杂画面上的可读性：字幕外观现在提供简洁的边缘样式与强度控制，可选择更深的柔和阴影、清晰描边或更强的高对比度描边，并为新用户默认启用高对比度样式。
```

```markdown
- Improved Video subtitle readability on busy footage with compact Edge Style and Edge Strength controls for a darker Soft Shadow, Clear Outline, or a stronger High Contrast outline, which is now the default for new users.
```

- [x] **Step 3: Run every focused automated check**

Run:

```bash
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift script/test_video_subtitle_edge_style.swift -o /tmp/hoshi-test-video-subtitle-edge-style && /tmp/hoshi-test-video-subtitle-edge-style
xcrun swiftc -D HOSHI_VIDEO -parse-as-library Models/Subtitle.swift Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift Features/Video/Subtitles/SubtitleParser.swift Features/Video/Subtitles/SubtitleCueStore.swift Features/Video/Subtitles/SubtitleOverlayRowHeightMeasurer.swift script/test_video_subtitles.swift -o /tmp/hoshi-test-video-subtitles && /tmp/hoshi-test-video-subtitles
swift script/test_video_settings_contract.swift
swift script/test_video_liquid_glass_contract.swift
xcrun swiftc -parse-as-library script/test_mining_context_ui_contract.swift -o /tmp/test_mining_context_ui_contract && /tmp/test_mining_context_ui_contract
./script/verify_video_variant_contract.sh
```

Expected: every command exits 0.

- [x] **Step 4: Build and launch the exact Light app**

Run: `./script/build_and_run.sh --instance subtitle-edge-light --verify`

Expected: build succeeds; bundle ID is `moe.shishamo.hoshi`; the running executable matches this instance's DerivedData path; Light contains no Video/libmpv linkage or bundled mpv files.

- [x] **Step 5: Build and launch the exact Video app**

Run: `./script/build_and_run.sh --video --instance subtitle-edge-video --verify`

Expected: build succeeds; bundle ID is `moe.shishamo.hoshi`; the running executable matches the exact Video DerivedData artifact.

- [ ] **Step 6: Perform non-destructive visual validation**

Using only the exact Video artifact and an already available or disposable local fixture, verify:

- Off, Soft Shadow, Clear Outline, and High Contrast update the visible cue immediately.
- High Contrast at 50% remains readable over bright, dark, detailed, and changing footage.
- 12pt, 36pt, and 72pt CJK/Latin mixed text remains filled, centered, and unclipped for one-line and wrapped cues.
- Edge effects have zero offset and no rectangular background when No Background is enabled.
- Native selection, click lookup, Shift-hover lookup, popup highlight, blur/opacity masks, and windowed/full-screen playback still behave correctly.
- Settings and Inspector stay synchronized, Restore Defaults returns High Contrast/50%, and edge strength is disabled while style is Off.

Partial validation note: the exact Video build exposed the localized Edge Style menu and disabled Edge Strength while Off was selected. A freshly compiled, non-persistent mixed-script fixture covered all four styles over a busy multicolor background without dark glyph fill, black compositing blocks, or duplicate glyphs. Existing library videos were deliberately not opened because that would restore and potentially rewrite user playback progress; real-player Inspector synchronization, dynamic footage, lookup, masks, and native full-screen behavior remain unverified in this run.

Do not import, replace, delete, or modify the user's library, bound subtitle sidecars, playback progress, or profile data for validation. If suitable disposable footage or any requested visual scenario is unavailable, list it explicitly in the completion report rather than claiming coverage.

- [x] **Step 7: Review the final diff and leave it uncommitted**

Run:

```bash
git diff --check
git status --short --branch
git diff -- Core/UserConfig.swift Features/Video/Subtitles/VideoSubtitleEdgeStyle.swift Features/Video/Subtitles/InteractiveSubtitleTextView.swift Features/Video/Subtitles/SubtitleOverlayView.swift Features/Video/Subtitles/SubtitleOverlayRowHeightMeasurer.swift Features/Video/VideoPlayerScreen.swift Features/Settings/VideoSettingsView.swift Features/Video/VideoInspectorView.swift Localizable.xcstrings script/test_video_subtitle_edge_style.swift script/test_video_subtitles.swift script/test_video_settings_contract.swift script/test_video_liquid_glass_contract.swift docs/TODO.md docs/ARCHITECTURE_REFACTORING.md docs/CHANGELOG.md docs/superpowers/specs/2026-07-11-video-subtitle-edge-style-design.md docs/superpowers/plans/2026-07-11-video-subtitle-edge-style.md
```

Expected: no whitespace errors; only the intended implementation, tests, localization, specification, plan, and truth-source documentation are modified.

## Implementation References

- Apple `CGContext.setShadow(offset:blur:color:)` enables a colored shadow in the current graphics state: <https://developer.apple.com/documentation/coregraphics/cgcontext/setshadow%28offset%3Ablur%3Acolor%3A%29>.
- Apple `NSLayoutManager.showCGGlyphs` renders a glyph run with its positions, font, attributes, and graphics context, which keeps this effect inside TextKit drawing rather than layout: <https://developer.apple.com/documentation/appkit/nslayoutmanager>.
- Apple `NSAttributedString.Key.strokeWidth` is a percentage of font point size; negative values stroke and fill: <https://developer.apple.com/documentation/foundation/nsattributedstring/key/strokewidth>.
