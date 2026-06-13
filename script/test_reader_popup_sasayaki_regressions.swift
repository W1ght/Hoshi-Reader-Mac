import CoreGraphics
import Foundation

@main
enum ReaderPopupSasayakiRegressionTest {
    static func assertEqual(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        if abs(actual - expected) > 0.0001 {
            fputs("FAIL: \(message): expected \(expected), got \(actual)\n", stderr)
            exit(1)
        }
    }

    static func assertContains(_ haystack: String, _ needle: String, _ message: String) {
        if !haystack.contains(needle) {
            fputs("FAIL: \(message)\nMissing: \(needle)\n", stderr)
            exit(1)
        }
    }

    static func assertNotContains(_ haystack: String, _ needle: String, _ message: String) {
        if haystack.contains(needle) {
            fputs("FAIL: \(message)\nUnexpected: \(needle)\n", stderr)
            exit(1)
        }
    }

    static func assertLocalized(
        _ strings: [String: Any],
        _ key: String,
        languages: [String],
        _ message: String
    ) {
        guard let entry = strings[key] as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any] else {
            fputs("FAIL: \(message)\nMissing localization key: \(key)\n", stderr)
            exit(1)
        }
        for language in languages where localizations[language] == nil {
            fputs("FAIL: \(message)\nMissing \(language) localization for key: \(key)\n", stderr)
            exit(1)
        }
    }

    static func assertOccurrenceCountAtLeast(
        _ haystack: String,
        _ needle: String,
        _ minimumCount: Int,
        _ message: String
    ) {
        let count = haystack.components(separatedBy: needle).count - 1
        if count < minimumCount {
            fputs("FAIL: \(message)\nExpected at least \(minimumCount) occurrences of \(needle), found \(count)\n", stderr)
            exit(1)
        }
    }

    static func main() throws {
        let viewportRect = CGRect(x: 120, y: 180, width: 28, height: 16)
        let pagedRect = ReaderViewportGeometry.selectionRect(
            fromViewportRect: viewportRect,
            adjustedContentInset: CGPoint(x: 7, y: 11),
            scrollBoundsOrigin: CGPoint(x: 0, y: 23),
            subtractVerticalScrollOffset: true
        )
        assertEqual(pagedRect.minX, 127, "paged popup x should include left inset")
        assertEqual(pagedRect.minY, 168, "paged popup y should include top inset and subtract scroll offset")
        assertEqual(pagedRect.width, 28, "paged popup width should be preserved")
        assertEqual(pagedRect.height, 16, "paged popup height should be preserved")

        let continuousHorizontalRect = ReaderViewportGeometry.selectionRect(
            fromViewportRect: viewportRect,
            adjustedContentInset: CGPoint(x: 7, y: 11),
            scrollBoundsOrigin: CGPoint(x: 0, y: 23),
            subtractVerticalScrollOffset: false
        )
        assertEqual(continuousHorizontalRect.minY, 191, "horizontal continuous popup y should not subtract vertical scroll offset")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let nativeReader = try String(
            contentsOf: root.appendingPathComponent("NativeMac/NativeReaderView.swift"),
            encoding: .utf8
        )
        let readerView = try String(
            contentsOf: root.appendingPathComponent("Features/Reader/ReaderView/ReaderView.swift"),
            encoding: .utf8
        )
        let readerWebView = try String(
            contentsOf: root.appendingPathComponent("Features/Reader/ReaderWebView/ReaderWebView.swift"),
            encoding: .utf8
        )
        let scrollReaderWebView = try String(
            contentsOf: root.appendingPathComponent("Features/Reader/ScrollReaderWebView/ScrollReaderWebView.swift"),
            encoding: .utf8
        )
        let readerJavaScript = try String(
            contentsOf: root.appendingPathComponent("Features/Reader/ReaderWebView/reader.js"),
            encoding: .utf8
        )
        let scrollReaderJavaScript = try String(
            contentsOf: root.appendingPathComponent("Features/Reader/ScrollReaderWebView/scrollreader.js"),
            encoding: .utf8
        )
        let catalystApp = try String(
            contentsOf: root.appendingPathComponent("App/HoshiReader.swift"),
            encoding: .utf8
        )
        let nativeApp = try String(
            contentsOf: root.appendingPathComponent("NativeMac/HoshiNativeMacApp.swift"),
            encoding: .utf8
        )
        let sasayakiSheet = try String(
            contentsOf: root.appendingPathComponent("Features/Sasayaki/SasayakiSheet.swift"),
            encoding: .utf8
        )
        let nativeReuseViews = try String(
            contentsOf: root.appendingPathComponent("NativeMac/NativeReuseViews.swift"),
            encoding: .utf8
        )
        let nativeMacSection = try String(
            contentsOf: root.appendingPathComponent("NativeMac/NativeMacSection.swift"),
            encoding: .utf8
        )
        let nativeMacSidebarView = try String(
            contentsOf: root.appendingPathComponent("NativeMac/NativeMacSidebarView.swift"),
            encoding: .utf8
        )
        let nativeMacDetailView = try String(
            contentsOf: root.appendingPathComponent("NativeMac/NativeMacDetailView.swift"),
            encoding: .utf8
        )
        let nativeMacPlaceholderViews = try String(
            contentsOf: root.appendingPathComponent("NativeMac/NativeMacPlaceholderViews.swift"),
            encoding: .utf8
        )
        let shortcutBridge = try String(
            contentsOf: root.appendingPathComponent("Core/ReaderKeyboardShortcutUIKitBridge.swift"),
            encoding: .utf8
        )
        let readerRegressionLab = try String(
            contentsOf: root.appendingPathComponent("Features/Reader/ReaderRegressionLab/ReaderRegressionLabView.swift"),
            encoding: .utf8
        )
        let bookshelfView = try String(
            contentsOf: root.appendingPathComponent("Features/Bookshelf/BookshelfView.swift"),
            encoding: .utf8
        )
        let bookshelfViewModel = try String(
            contentsOf: root.appendingPathComponent("Features/Bookshelf/BookshelfViewModel.swift"),
            encoding: .utf8
        )
        let captureScript = try String(
            contentsOf: root.appendingPathComponent("script/capture_reader_regression.sh"),
            encoding: .utf8
        )
        let catalystBuildScript = try String(
            contentsOf: root.appendingPathComponent("script/build_and_run_catalyst.sh"),
            encoding: .utf8
        )
        let nativeBuildScript = try String(
            contentsOf: root.appendingPathComponent("script/build_and_run_native.sh"),
            encoding: .utf8
        )
        let xcodeProject = try String(
            contentsOf: root.appendingPathComponent("Hoshi Reader.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        let localizationData = try Data(contentsOf: root.appendingPathComponent("Localizable.xcstrings"))
        guard let localizationRoot = try JSONSerialization.jsonObject(with: localizationData) as? [String: Any],
              let localizationStrings = localizationRoot["strings"] as? [String: Any] else {
            fputs("FAIL: Localizable.xcstrings should be valid JSON with a strings object\n", stderr)
            exit(1)
        }

        assertNotContains(
            nativeMacSection,
            "case reader",
            "native home sidebar should not expose a standalone Reader section"
        )
        assertNotContains(
            nativeMacDetailView,
            "case .reader",
            "native home detail should not keep the removed Reader placeholder route"
        )
        assertNotContains(
            nativeMacPlaceholderViews,
            "NativeReaderPlaceholderView",
            "native home should not keep the removed Reader placeholder view"
        )
        assertContains(
            nativeMacSection,
            "var title: LocalizedStringKey",
            "native home navigation titles should use localized keys"
        )
        assertContains(
            nativeMacSection,
            "var detail: LocalizedStringKey",
            "native home navigation details should use localized keys"
        )
        assertNotContains(
            nativeMacSidebarView,
            "HoshiAppIconGlyph",
            "native home sidebar should not show an in-app app icon glyph"
        )
        assertContains(
            xcodeProject,
            "48AA10502FAA000100000001 /* Assets.xcassets in Resources */",
            "native target should include the shared asset catalog for app icon support"
        )
        assertContains(
            xcodeProject,
            "48AA10512FAA000100000001 /* HoshiIcon.icon in Resources */",
            "native target should include the same HoshiIcon.icon resource as Catalyst"
        )
        assertOccurrenceCountAtLeast(
            xcodeProject,
            "ASSETCATALOG_COMPILER_APPICON_NAME = HoshiIcon;",
            4,
            "native target should use the same HoshiIcon app icon name as Catalyst"
        )
        assertContains(
            nativeBuildScript,
            "refresh_app_icon_registration",
            "native build harness should refresh Finder/Dock app icon registration after builds"
        )
        assertContains(
            nativeBuildScript,
            "lsregister\" -f \"$APP_BUNDLE\"",
            "native build harness should re-register the app bundle with LaunchServices"
        )
        for key in ["Bookshelf", "Bookshelf and sync", "Dictionary search", "App settings", "Hoshi Reader"] {
            assertLocalized(
                localizationStrings,
                key,
                languages: ["en", "zh-Hans"],
                "native home navigation should have English and Simplified Chinese localization"
            )
        }

        assertContains(
            nativeReader,
            "ReaderViewportGeometry.selectionRect",
            "native Reader should use the shared Catalyst-aligned selection rect conversion"
        )
        assertContains(
            nativeReader,
            ".hoshi-sasayaki-cue.hoshi-sasayaki-active",
            "native Reader should style active Sasayaki cues"
        )
        assertContains(
            nativeReader,
            "background-color: var(--hoshi-sasayaki-background-color)",
            "native Reader should apply the configured Sasayaki highlight background"
        )
        assertContains(
            nativeReader,
            "isVertical: false",
            "native nested popup selections should use horizontal popup layout like Catalyst"
        )
        assertContains(
            nativeReader,
            "isFullWidth: false",
            "native nested popup selections should avoid full-width Reader popup layout"
        )
        assertContains(
            nativeReader,
            "private var sepiaInverted: Bool",
            "native Reader should mirror Catalyst sepia dark inversion"
        )
        assertContains(
            nativeReader,
            "readerTheme == .dark ?",
            "native Reader should derive Sasayaki colors from the effective reader theme"
        )
        assertContains(
            nativeReader,
            ".preferredColorScheme(readerTheme)",
            "native Reader sheets should use the effective reader theme"
        )
        assertContains(
            nativeReader,
            "context.coordinator.syncTextColor()",
            "native Reader should update WebView text color when theme changes without reloading"
        )
        assertContains(
            nativeReader,
            "static func textColorScript(_ hex: String?) -> String",
            "native Reader should use a single set/remove text color script for theme isolation"
        )
        assertContains(
            nativeReader,
            "document.documentElement.style.removeProperty('--hoshi-text-color')",
            "native Reader should clear sepia/custom text color when switching to a normal theme"
        )
        assertContains(
            readerWebView,
            "static func textColorScript(_ hex: String?) -> String",
            "paged Catalyst Reader should share explicit set/remove text color behavior"
        )
        assertContains(
            scrollReaderWebView,
            "static func textColorScript(_ hex: String?) -> String",
            "scroll Catalyst Reader should share explicit set/remove text color behavior"
        )
        assertContains(
            readerView,
            "userConfig.theme == .sepia && userConfig.sepiaInvertInDark",
            "Catalyst Reader sepia inversion should only apply to the sepia theme"
        )
        assertContains(
            nativeReader,
            "userConfig.theme == .sepia && userConfig.sepiaInvertInDark",
            "native Reader sepia inversion should only apply to the sepia theme"
        )
        assertContains(
            catalystApp,
            "userConfig.theme == .sepia && userConfig.sepiaInvertInDark",
            "Catalyst app appearance should not let sepia inversion affect other themes"
        )
        assertContains(
            nativeApp,
            "userConfig.theme == .sepia && userConfig.sepiaInvertInDark",
            "native app appearance should not let sepia inversion affect other themes"
        )
        assertContains(
            nativeReader,
            "nativeReaderGlassCapsuleControl",
            "native Reader bottom controls should use Liquid Glass capsule surfaces"
        )
        assertContains(
            nativeReader,
            "NativeSettingsDetailView(section: .appearance",
            "native Reader Appearance sheet should reuse the same Settings detail component"
        )
        assertContains(
            nativeReader,
            "NativeGlassCircleButton(systemName: \"chevron.left\", diameter: 34, fontSize: 18)",
            "native Reader close control should stay aligned with the right-side control size"
        )
        assertNotContains(
            nativeReader,
            "NativeReaderGlassGroup",
            "native Reader bottom page-turn button group should be removed"
        )
        assertContains(
            nativeReader,
            "userConfig.readerShowProgressTop && !progressString.isEmpty",
            "native Reader should only show top progress when Appearance requests top progress"
        )
        assertContains(
            nativeReader,
            "!userConfig.readerShowProgressTop && !progressString.isEmpty",
            "native Reader should show bottom progress when Appearance requests bottom progress"
        )
        assertContains(
            nativeReader,
            "userConfig.readerShowCharacters",
            "native Reader progress should respect the character count visibility setting"
        )
        assertContains(
            nativeReader,
            "userConfig.readerShowPercentage",
            "native Reader progress should respect the percentage visibility setting"
        )
        assertContains(
            nativeReader,
            ".ignoresSafeArea(edges: [.top, .bottom])",
            "native Reader content should extend into the top and bottom safe areas"
        )
        assertContains(
            nativeReader,
            "nativeBottomControls\n                .ignoresSafeArea(edges: .bottom)",
            "native Reader bottom chrome should extend into the bottom safe area"
        )
        assertContains(
            nativeReader,
            ".padding(.bottom, 18)",
            "native Reader bottom controls should sit closer to the bottom edge"
        )
        assertContains(
            nativeReader,
            "nativeBottomInfoOverlay",
            "native Reader should have a bottom progress overlay"
        )
        assertContains(
            nativeReader,
            ".overlay(alignment: .top) {",
            "native Reader top info overlay should be centered instead of pinned to the top trailing corner"
        )
        assertNotContains(
            nativeReader,
            ".overlay(alignment: .topTrailing)",
            "native Reader top info overlay should not be pinned to the top trailing corner"
        )
        assertContains(
            readerView,
            "--reader-regression-metrics",
            "ReaderView should accept a Debug-only metrics output path for regression captures"
        )
        assertContains(
            readerView,
            "writeReaderRegressionMetricsIfNeeded",
            "ReaderView should write Reader-internal metrics after restore completes"
        )
        assertContains(
            readerView,
            "\"viewport\"",
            "Reader regression metrics should include Reader viewport dimensions"
        )
        assertContains(
            readerView,
            "\"layout\"",
            "Reader regression metrics should include Reader layout mode"
        )
        assertContains(
            readerView,
            "applyReaderRegressionAutomationIfNeeded",
            "Reader regression metrics should be written after deterministic popup/Sasayaki automation is applied"
        )
        assertContains(
            readerView,
            "ReaderRegressionReaderAutomation",
            "ReaderView should map regression scenarios to deterministic popup and Sasayaki states"
        )
        assertContains(
            readerView,
            "case .lookupPopup",
            "ReaderView should be able to synthesize a lookup popup regression scenario"
        )
        assertContains(
            readerView,
            "case .nestedLookupPopup",
            "ReaderView should be able to synthesize a nested popup regression scenario"
        )
        assertContains(
            readerView,
            "\"swiftPopups\"",
            "Reader regression metrics should include SwiftUI popup state outside the WKWebView DOM"
        )
        assertContains(
            readerJavaScript,
            "getRegressionMetrics()",
            "Paged Reader JS should expose scroll, document, selection, popup, and Sasayaki metrics"
        )
        assertContains(
            readerJavaScript,
            "applyRegressionHighlight(query)",
            "Paged Reader JS should expose a deterministic Sasayaki-style highlight hook for visual regression"
        )
        assertContains(
            scrollReaderJavaScript,
            "getRegressionMetrics()",
            "Scroll Reader JS should expose scroll, document, selection, popup, and Sasayaki metrics"
        )
        assertContains(
            scrollReaderJavaScript,
            "applyRegressionHighlight(query)",
            "Scroll Reader JS should expose a deterministic Sasayaki-style highlight hook for visual regression"
        )
        assertContains(
            readerWebView,
            "ReaderRegressionWebAutomation.highlightQuery",
            "Paged Reader WebView should apply deterministic web highlight automation before collecting JS metrics"
        )
        assertContains(
            readerWebView,
            "ReaderRegressionCaptureConfiguration.isEnabled",
            "Paged Reader WebView should only collect regression metrics when Debug capture is explicitly enabled"
        )
        assertContains(
            scrollReaderWebView,
            "ReaderRegressionWebAutomation.highlightQuery",
            "Scroll Reader WebView should apply deterministic web highlight automation before collecting JS metrics"
        )
        assertContains(
            scrollReaderWebView,
            "ReaderRegressionCaptureConfiguration.isEnabled",
            "Scroll Reader WebView should only collect regression metrics when Debug capture is explicitly enabled"
        )
        assertContains(
            nativeReader,
            "VStack(alignment: .center, spacing: 2)",
            "native Reader top info text should be centered"
        )
        assertContains(
            nativeReader,
            "private var nativeBottomControls: some View {\n        if !focusMode {\n            ZStack {\n                nativeBottomInfoOverlay",
            "native Reader bottom progress should share the same vertical row as bottom controls"
        )
        assertContains(
            nativeReader,
            "nativeReaderGlassCapsuleSurface",
            "native Reader info capsules should use Liquid Glass surfaces"
        )
        assertNotContains(
            nativeReader,
            ".background(.thinMaterial, in: Capsule())",
            "native Reader info capsules should not use plain thinMaterial backgrounds"
        )
        assertNotContains(
            nativeReader,
            "model.progressString",
            "native Reader should not use a model-level progress string that ignores Appearance settings"
        )
        assertContains(
            nativeReader,
            "NativeGlassCircleButton(systemName: \"xmark\"",
            "native Reader Appearance sheet should expose a glass close button"
        )
        assertContains(
            nativeReader,
            "NativeReaderSasayakiShortcutMonitor",
            "native Reader should use AppKit key monitoring for Sasayaki bracket shortcuts"
        )
        assertContains(
            nativeReader,
            "case .applyRegressionHighlight(let query)",
            "native Reader bridge should remain exhaustive when shared regression commands are added"
        )
        assertContains(
            nativeReader,
            "userConfig.sasayakiPreviousCueShortcut.matches(event)",
            "native Reader should match the configured previous Sasayaki cue shortcut from NSEvent"
        )
        assertContains(
            nativeReader,
            "userConfig.sasayakiNextCueShortcut.matches(event)",
            "native Reader should match the configured next Sasayaki cue shortcut from NSEvent"
        )
        assertContains(
            shortcutBridge,
            "case 33: return \"[\"",
            "native shortcut matching should normalize the ANSI left bracket key code"
        )
        assertContains(
            shortcutBridge,
            "case .keyboardOpenBracket: return \"[\"",
            "Catalyst shortcut capture should normalize the open bracket HID usage"
        )
        assertContains(
            shortcutBridge,
            "case 30: return \"]\"",
            "native shortcut matching should normalize the ANSI right bracket key code"
        )
        assertContains(
            shortcutBridge,
            "case .keyboardCloseBracket: return \"]\"",
            "Catalyst shortcut capture should normalize the close bracket HID usage"
        )
        assertContains(
            shortcutBridge,
            "\"【\"",
            "native shortcut matching should accept CJK left bracket characters for the default Sasayaki shortcut"
        )
        assertContains(
            shortcutBridge,
            "\"】\"",
            "native shortcut matching should accept CJK right bracket characters for the default Sasayaki shortcut"
        )
        assertContains(
            sasayakiSheet,
            "NativeSettingsForm",
            "native Sasayaki sheet should use the same card form style as Settings"
        )
        assertContains(
            sasayakiSheet,
            "NativeSettingsSectionCard",
            "native Sasayaki sheet should use Settings card sections"
        )
        assertContains(
            sasayakiSheet,
            "NativeGlassCircleButton(systemName: \"xmark\"",
            "native Sasayaki sheet should use the glass close button"
        )
        assertContains(
            nativeReuseViews,
            ".toggleStyle(.switch)",
            "native settings toggles should render as macOS switches instead of checkboxes"
        )
        assertContains(
            nativeReuseViews,
            "struct NativeGlassCircleButton",
            "native Reader sheets should share a macOS glass circle button"
        )
        assertContains(
            nativeReuseViews,
            "nativeSettingsCardGlass",
            "native settings cards should participate in macOS Liquid Glass on supported systems"
        )
        assertContains(
            readerRegressionLab,
            "ReaderRegressionFixtureLocator.fixtureDirectory",
            "Reader Regression Lab should deterministically locate generated fixtures"
        )
        assertContains(
            readerRegressionLab,
            "onOpenScenario(scenario)",
            "Reader Regression Lab should open deterministic screenshot scenarios"
        )
        assertContains(
            readerRegressionLab,
            "static var shouldAutoOpen: Bool",
            "Reader Regression Lab should expose launch-argument auto-open state for capture automation"
        )
        assertContains(
            readerRegressionLab,
            "--reader-regression-fixtures",
            "Reader Regression Lab should accept a launch-argument fixture directory override"
        )
        assertContains(
            readerRegressionLab,
            "--reader-regression-scenario",
            "Reader Regression Lab should accept a launch-argument scenario selector"
        )
        assertContains(
            readerRegressionLab,
            "ReaderRegressionScenarios.plans",
            "Reader Regression Lab UI and launch automation should share the same scenario list"
        )
        assertContains(
            readerRegressionLab,
            "let chapterIndex: Int",
            "Reader Regression Lab scenarios should carry deterministic chapter jump targets"
        )
        assertContains(
            readerRegressionLab,
            "let chapterProgress: Double",
            "Reader Regression Lab scenarios should carry deterministic chapter progress targets"
        )
        assertContains(
            bookshelfViewModel,
            "importReaderRegressionFixture",
            "BookshelfViewModel should expose a Debug-only fixture import path"
        )
        assertContains(
            bookshelfView,
            "@State private var showReaderRegressionLaunchOverlay = ReaderRegressionLabAvailability.shouldShowLaunchOverlay",
            "BookshelfView should initialize a full-window Reader Regression Lab overlay from the launch argument for screenshot capture"
        )
        assertContains(
            bookshelfView,
            "openReaderRegressionLaunchScenarioIfNeeded",
            "BookshelfView should open a requested Reader regression scenario during launch automation"
        )
        assertContains(
            bookshelfView,
            "showReaderRegressionLaunchOverlay = false",
            "BookshelfView should dismiss the launch overlay before opening a regression scenario"
        )
        assertContains(
            bookshelfView,
            "ReaderRegressionSettingsSnapshot",
            "BookshelfView should snapshot and restore user Reader settings for regression scenarios"
        )
        assertContains(
            bookshelfView,
            "scenario.apply(to: userConfig)",
            "BookshelfView should apply temporary Reader settings before opening a regression scenario"
        )
        assertContains(
            bookshelfView,
            "scenario.writeInitialBookmark(for: book)",
            "BookshelfView should write deterministic Reader position bookmarks before opening regression scenarios"
        )
        assertContains(
            bookshelfView,
            "ReaderRegressionBookmarkSnapshot",
            "BookshelfView should snapshot the existing fixture bookmark before applying a regression position"
        )
        assertContains(
            bookshelfView,
            "restoreReaderRegressionBookmarkIfNeeded",
            "BookshelfView should restore the fixture bookmark after a regression scenario closes"
        )
        assertContains(
            captureScript,
            "generate_reader_fixtures.py",
            "Reader capture harness should generate deterministic fixtures"
        )
        assertContains(
            captureScript,
            "build_and_run_catalyst.sh --reader-regression-lab",
            "Reader capture harness should point to the Debug-only lab launch command"
        )
        assertContains(
            captureScript,
            "--smoke-capture",
            "Reader capture harness should expose an opt-in app-driven smoke screenshot mode"
        )
        assertContains(
            captureScript,
            "--scenario-capture",
            "Reader capture harness should expose an opt-in single scenario screenshot mode"
        )
        assertContains(
            captureScript,
            "capture_all_scenario_screenshots",
            "Reader capture harness should be able to capture the planned scenario matrix"
        )
        assertContains(
            captureScript,
            "--update-baseline",
            "Reader capture harness should be able to update screenshot baselines"
        )
        assertContains(
            captureScript,
            "--compare-baseline",
            "Reader capture harness should be able to compare screenshots against baselines"
        )
        assertContains(
            captureScript,
            "baseline-report.json",
            "Reader capture harness should write a baseline comparison report"
        )
        assertContains(
            captureScript,
            "differingPixels",
            "Reader capture harness should compute pixel differences for baseline comparisons"
        )
        assertContains(
            captureScript,
            "--max-diff-pixels",
            "Reader capture harness should expose an explicit pixel-diff threshold policy"
        )
        assertContains(
            captureScript,
            "--max-diff-ratio",
            "Reader capture harness should expose a ratio-based pixel-diff threshold policy"
        )
        assertContains(
            captureScript,
            "baseline-policy.json",
            "Reader capture harness should write baseline policy metadata when updating baselines"
        )
        assertContains(
            captureScript,
            "\"policy\": [",
            "Reader baseline comparison report should include the active threshold policy"
        )
        assertContains(
            captureScript,
            "--reader-regression-scenario \"$scenario\"",
            "Reader capture harness should pass the requested scenario to the app"
        )
        assertContains(
            captureScript,
            "--reader-regression-metrics \"$reader_metrics\"",
            "Reader capture harness should pass a metrics output path to the app"
        )
        assertContains(
            captureScript,
            "JSONSerialization.jsonObject",
            "Reader capture harness should merge app-written Reader metrics into geometry sidecars"
        )
        assertContains(
            captureScript,
            "scenario_screenshot_name",
            "Reader capture harness should map scenario numbers to deterministic screenshot filenames"
        )
        assertContains(
            captureScript,
            "write_capture_geometry_json",
            "Reader capture harness should write geometry sidecars next to screenshots"
        )
        assertContains(
            captureScript,
            "geometry-manifest.txt",
            "Reader capture harness should list planned geometry sidecars"
        )
        assertContains(
            captureScript,
            "CGImageSourceCopyPropertiesAtIndex",
            "Reader capture harness should record screenshot pixel dimensions in geometry sidecars"
        )
        assertContains(
            captureScript,
            "\"readerMetrics\": readerMetrics",
            "Reader capture harness should write merged Reader metrics into geometry sidecars"
        )
        assertContains(
            captureScript,
            "CGWindowListCopyWindowInfo",
            "Reader capture harness should locate the app window before taking a smoke screenshot"
        )
        assertContains(
            captureScript,
            ".optionAll",
            "Reader capture harness should not rely on Catalyst windows appearing in optionOnScreenOnly"
        )
        assertContains(
            captureScript,
            "screencapture -x -l",
            "Reader capture harness should capture the Reader Regression Lab window, not an arbitrary full-screen shot"
        )
        assertContains(
            captureScript,
            "capture_window_screenshot",
            "Reader capture harness should retry screenshot capture with a fresh window id when macOS invalidates the previous one"
        )
        assertContains(
            captureScript,
            "screencapture -x -R",
            "Reader capture harness should fall back to window bounds capture when macOS refuses window-id capture"
        )
        assertContains(
            captureScript,
            "crop_full_screenshot_to_rect",
            "Reader capture harness should crop a full-screen screenshot if direct window and rect captures are both unavailable"
        )
        assertContains(
            captureScript,
            "00-reader-regression-lab.png",
            "Reader capture harness should write a deterministic smoke screenshot filename"
        )
        assertContains(
            captureScript,
            "--reader-regression-fixtures \"$FIXTURE_DIR\"",
            "Reader capture harness should pass its generated fixture directory to the Lab"
        )
        assertContains(
            catalystBuildScript,
            "--reader-regression-lab",
            "Catalyst build script should be able to launch the Reader Regression Lab"
        )
        assertContains(
            catalystBuildScript,
            "open_app --reader-regression-lab \"$@\"",
            "Catalyst build script should pass Reader Regression Lab automation arguments through to the app"
        )

        print("reader popup/Sasayaki regressions passed")
    }
}
