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

        let fullViewportRect = ReaderViewportGeometry.selectionRect(
            fromViewportRect: viewportRect,
            adjustedContentInset: .zero,
            scrollBoundsOrigin: .zero,
            subtractVerticalScrollOffset: false
        )
        assertEqual(fullViewportRect.minX, viewportRect.minX, "full-viewport popup x should not add a synthetic side inset")
        assertEqual(fullViewportRect.minY, viewportRect.minY, "full-viewport popup y should not add a synthetic top inset")

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let nativeReader = try String(
            contentsOf: root.appendingPathComponent("NativeMac/NativeReaderView.swift"),
            encoding: .utf8
        )
        let popupView = try String(
            contentsOf: root.appendingPathComponent("Features/Popup/PopupView.swift"),
            encoding: .utf8
        )
        assertContains(
            popupView,
            "import CxxStdlib",
            "Popup clean builds must explicitly import the std::string-to-Swift bridge they use"
        )
        assertContains(
            nativeReader,
            "coverURL: model.coverURL",
            "Reader popup mining should pass the active book cover into MiningContext"
        )
        assertNotContains(
            nativeReader,
            "coverURL: nil",
            "Reader popup mining should not discard the active book cover"
        )
        guard let readerIdentityStart = nativeReader.range(of: "let readerIdentity = ["),
              let readerIdentityEnd = nativeReader.range(
                of: "].joined(separator: \"-\")",
                range: readerIdentityStart.upperBound..<nativeReader.endIndex
              ) else {
            fputs("FAIL: native Reader should define a readerIdentity array\n", stderr)
            exit(1)
        }
        let readerIdentityBlock = String(nativeReader[readerIdentityStart.lowerBound..<readerIdentityEnd.upperBound])
        let paginatedReaderScript = try String(
            contentsOf: root.appendingPathComponent("Features/Reader/ReaderWebView/reader.js"),
            encoding: .utf8
        )
        let selectionScript = try String(
            contentsOf: root.appendingPathComponent("Features/Reader/ReaderWebView/selection.js"),
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
            contentsOf: root.appendingPathComponent("Core/ReaderKeyboardShortcutAppKitBridge.swift"),
            encoding: .utf8
        )
        let shortcutManager = try String(
            contentsOf: root.appendingPathComponent("Core/Shortcuts/ShortcutManager.swift"),
            encoding: .utf8
        )
        assertContains(selectionScript, "language: 'ja'", "Reader selection must declare a language policy")
        assertContains(selectionScript, "isEnglishScanBoundaryAt", "Reader selection must support English phrase boundaries")
        assertContains(selectionScript, "findEnglishWordStart", "English lookup must start at the beginning of the tapped word")
        assertContains(selectionScript, "EnglishWordInternalDelimiters", "English lookup must retain apostrophes and hyphens inside words")
        assertContains(nativeReader, "window.hoshiSelection.language =", "native Reader must inject the resolved Profile language")
        assertContains(
            nativeReader,
            "config.userContentController.add(context.coordinator, name: \"focusRequested\")",
            "native Reader must restore the v0.5 focus bridge used by Shift-hover lookup"
        )
        assertContains(
            nativeReader,
            "removeScriptMessageHandler(forName: \"focusRequested\")",
            "native Reader must tear down its Shift-hover focus bridge"
        )
        assertContains(
            nativeReader,
            "case \"focusRequested\":",
            "native Reader must handle pointer focus requests from selection.js"
        )
        assertContains(
            nativeReader,
            "message.webView?.window?.makeFirstResponder(message.webView)",
            "native Reader Shift-hover focus requests must target the active WKWebView"
        )
        assertContains(
            nativeReader,
            "window.hoshiSelection.registerShiftHoverLookup(lookupScanLength, \\(parent.userConfig.desktopLookupHoverDelayMs));",
            "native Reader must register Shift-hover with the configured Mac hover delay"
        )
        assertContains(
            nativeReader,
            "const lookupScanLength = \\(parent.userConfig.scanLength);",
            "native Reader click and Shift-hover lookup must share the configured scan length"
        )
        assertContains(
            nativeReader,
            "BookStorage.loadMetadata(root: root) ?? book",
            "Reader last-access updates must preserve language and Profile fields written by sidecar migration"
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

        assertContains(
            nativeReader,
            "const browserSelection = window.getSelection();\n                    if (browserSelection && !browserSelection.isCollapsed) { return; }",
            "native Reader drag selection must bypass click lookup so WebKit keeps the selected range"
        )
        assertContains(
            nativeReader,
            "config.userContentController.add(context.coordinator, name: \"selectionState\")",
            "native Reader must receive browser selection state for its AppKit context menu"
        )
        assertContains(
            nativeReader,
            "webView.configuration.userContentController.removeScriptMessageHandler(forName: \"selectionState\")",
            "native Reader must remove its selection-state script handler"
        )
        assertContains(
            nativeReader,
            "override func willOpenMenu(_ menu: NSMenu, with event: NSEvent)",
            "native Reader must extend the standard WebKit context menu as it opens"
        )
        assertContains(
            nativeReader,
            "super.willOpenMenu(menu, with: event)",
            "native Reader must preserve WebKit standard context-menu items"
        )
        assertNotContains(
            nativeReader,
            "override func menu(for event: NSEvent) -> NSMenu?",
            "native Reader must not customize the unused outer WKWebView menu provider"
        )
        assertContains(
            nativeReader,
            "window.hoshiHighlights.createHighlight",
            "native Reader highlight actions must reuse the shared JavaScript range creator"
        )
        assertContains(
            nativeReader,
            "case \"selectionState\":",
            "native Reader must update native menu eligibility from browser selection state"
        )
        assertContains(
            nativeReader,
            "onHighlightCreated: model.addHighlight",
            "native Reader must forward WebView highlight creation into the book model"
        )
        assertContains(
            nativeReader,
            "func addHighlight(_ color: HighlightColor, _ creation: HighlightData)",
            "native Reader model must expose book-scoped highlight persistence"
        )
        assertContains(
            nativeReader,
            "try? BookStorage.save(highlights, inside: rootURL, as: FileNames.highlights)",
            "native Reader must persist created highlights in the current book"
        )
        for key in ["Yellow", "Green", "Blue", "Pink", "Purple"] {
            assertLocalized(
                localizationStrings,
                key,
                languages: ["en", "zh-Hans"],
                "native Reader highlight colors should have English and Simplified Chinese localization"
            )
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
            "native target should include the HoshiIcon.icon resource"
        )
        assertOccurrenceCountAtLeast(
            xcodeProject,
            "ASSETCATALOG_COMPILER_APPICON_NAME = HoshiIcon;",
            2,
            "native target should use the HoshiIcon app icon in Debug and Release"
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
            "native Reader should use the shared selection rect conversion"
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
            "native nested popup selections should use horizontal popup layout"
        )
        assertContains(
            nativeReader,
            "isFullWidth: false",
            "native nested popup selections should avoid full-width Reader popup layout"
        )
        assertContains(
            nativeReader,
            "private var sepiaInverted: Bool",
            "native Reader should support sepia dark inversion"
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
            nativeReader,
            "userConfig.theme == .sepia && userConfig.sepiaInvertInDark",
            "native Reader sepia inversion should only apply to the sepia theme"
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
            "let readerSize = CGSize(\n                width: max(geometry.size.width.rounded(), 1)",
            "native Reader should size WebKit from the complete available viewport"
        )
        assertContains(
            nativeReader,
            "viewSize: readerSize",
            "native Reader pagination should use the same complete viewport size as WebKit"
        )
        for identityInput in [
            "userConfig.readerHideFurigana",
            "userConfig.horizontalPadding",
            "userConfig.verticalPadding",
            "userConfig.avoidPageBreak",
            "userConfig.justifyText",
            "userConfig.blurImages",
            "userConfig.layoutAdvanced",
            "userConfig.lineHeight",
            "userConfig.characterSpacing",
            "userConfig.paragraphSpacing",
        ] {
            assertContains(
                readerIdentityBlock,
                identityInput,
                "native Reader reload identity should include layout-affecting setting: \(identityInput)"
            )
        }
        assertContains(
            nativeReader,
            ".frame(width: geometry.size.width, height: geometry.size.height)",
            "native Reader WebView should fill the complete available viewport"
        )
        assertContains(
            nativeReader,
            ".background(readerBackgroundColor.ignoresSafeArea())\n        .ignoresSafeArea(edges: .top)\n        .overlay(alignment: .top)",
            "native Reader content should use the top safe area so vertical pages are not pushed below the title overlay zone"
        )
        assertNotContains(
            nativeReader,
            ".ignoresSafeArea(edges: [.top, .bottom])",
            "native Reader should not extend into top and bottom safe areas as one coupled text viewport"
        )
        assertNotContains(
            nativeReader,
            ".ignoresSafeArea(edges: [.leading, .trailing])",
            "native Reader text viewport should stay inside the GeometryReader safe viewport instead of entering rounded window edges"
        )
        for forbidden in [
            "NativeReaderChromeMetrics",
            "NativeReaderWebContainerView",
            "NativeReaderPassthroughMaskView",
            "readerWebViewSideInset",
            "viewportOrigin",
            "visualSideInset",
            "visualBottomInset",
            "textComfortPadding",
            "sideTextInset",
            "bottomTextInset",
        ] {
            assertNotContains(
                nativeReader,
                forbidden,
                "native Reader should not reserve fixed visual insets or mask full-viewport text: \(forbidden)"
            )
        }
        assertContains(
            nativeReader,
            "adjustedContentInset: .zero",
            "native Reader popup coordinates should share the full WebView viewport origin"
        )
        assertContains(
            nativeReader,
            #"padding: \(verticalPadding / 2)vh \(horizontalPadding / 2)vw !important;"#,
            "native Reader body padding should only reflect the user's layout settings"
        )
        assertContains(
            nativeReader,
            "html, body {\n                margin: 0 !important;\n                padding: 0 !important;\n                color: var(--hoshi-text-color) !important;\n                writing-mode: \\(writingMode) !important;\n                \\(rootOverflowCss)",
            "native Reader root CSS should match the Catalyst viewport contract without applying columns to html"
        )
        assertContains(
            nativeReader,
            "let paginatedHtmlHeightCss = parent.userConfig.continuousMode ? \"\"",
            "native Reader should apply fixed html viewport height only in paginated mode"
        )
        assertContains(
            nativeReader,
            "let bodyPageHeightCss = parent.userConfig.continuousMode ? \"\" : \"height: var(--page-height, 100vh) !important;\"",
            "native Reader should apply fixed body page height only in paginated mode"
        )
        assertContains(
            nativeReader,
            "\\(bodyColumnCss)",
            "native Reader should apply paginated column geometry only to body"
        )
        assertContains(
            nativeReader,
            "let bottomOverlap = parent.userConfig.verticalWriting ? parent.userConfig.fontSize : 0",
            "native Reader vertical pagination should keep only the Catalyst font-derived bottom overlap"
        )
        assertContains(
            nativeReader,
            "? \"calc(\\(verticalPadding)vh + \\(bottomOverlap)px)\"",
            "native Reader vertical column gap should derive from user padding and the font overlap"
        )
        assertContains(
            nativeReader,
            ": \"\\(horizontalPadding)vw\"",
            "native Reader horizontal column gap should derive only from user padding"
        )
        assertNotContains(
            paginatedReaderScript,
            "maxAlignedScroll",
            "paginated Reader navigation should not discard a final partial page"
        )
        assertContains(
            paginatedReaderScript,
            "currentScroll >= (context.maxScroll - 1)",
            "paginated Reader should report the chapter limit only at the true scroll boundary"
        )
        assertContains(
            paginatedReaderScript,
            "Math.min(currentScroll + context.pageSize, context.maxScroll)",
            "paginated Reader should navigate into a final partial page before changing chapters"
        )
        assertContains(
            shortcutManager,
            "func handleKeyDown(_ event: NSEvent) -> Bool",
            "ShortcutManager should expose the unified dispatcher to focused AppKit controls"
        )
        assertContains(
            nativeReader,
            "final class NativeReaderWKWebView: WKWebView",
            "native Reader WKWebView should capture keyDown while focused"
        )
        assertContains(
            nativeReader,
            "if shortcutManager?.handleKeyDown(event) == true { return }",
            "native Reader WKWebView should consume handled shortcuts before WebKit native scrolling"
        )
        assertContains(
            shortcutManager,
            "protocol ShortcutEventDispatchResponder: AnyObject {}",
            "focused AppKit responders must be able to own shortcut dispatch"
        )
        assertContains(
            shortcutManager,
            "handle(event, source: .localMonitor)",
            "the local monitor must identify its dispatch source"
        )
        assertContains(
            shortcutManager,
            "source == .localMonitor, responder is ShortcutEventDispatchResponder",
            "the local monitor must defer to a focused responder that owns shortcut dispatch"
        )
        assertContains(
            nativeReader,
            "final class NativeReaderWKWebView: WKWebView, ShortcutEventDispatchResponder",
            "the Reader WKWebView must be the sole dispatcher while focused"
        )
        assertNotContains(
            shortcutManager,
            "handledEventSignature",
            "mutually exclusive dispatch paths must not rely on timestamp deduplication"
        )
        assertContains(
            nativeReader,
            "private var canHandleSasayakiShortcut: Bool {\n        (activeSheet == nil || activeSheet == .sasayaki)",
            "Sasayaki playback shortcuts should keep working while the Sasayaki sheet is open"
        )
        assertNotContains(
            shortcutManager,
            ".eventNumber",
            "keyboard shortcut dispatch must not query NSEvent.eventNumber because AppKit asserts for key events"
        )
        assertContains(
            nativeReader,
            "shortcutManager: shortcutManager",
            "native Reader WebView should use the shared ShortcutManager instead of a private shortcut path"
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
            "private struct NativeReaderPosition",
            "native Reader should model jump destinations"
        )
        assertContains(
            nativeReader,
            "private var backHistory: [NativeReaderPosition] = []",
            "native Reader should retain backward jump history"
        )
        assertContains(
            nativeReader,
            "private var forwardHistory: [NativeReaderPosition] = []",
            "native Reader should retain forward jump history"
        )
        assertOccurrenceCountAtLeast(
            nativeReader,
            "recordPosition()",
            4,
            "chapter, character/highlight, and internal-link jumps should record their origin"
        )
        assertContains(
            nativeReader,
            "func navigateBackwards()",
            "native Reader should restore a backward jump destination"
        )
        assertContains(
            nativeReader,
            "func navigateForwards()",
            "native Reader should restore a forward jump destination"
        )
        assertContains(
            nativeReader,
            "func handleManualNavigation()",
            "manual Reader navigation should invalidate stale forward history"
        )
        assertContains(
            nativeReader,
            "arrow.uturn.backward.circle",
            "native Reader should show the backward progress control"
        )
        assertContains(
            nativeReader,
            "model.navigateBackwards()",
            "native Reader backward progress control should restore its destination"
        )
        assertContains(
            nativeReader,
            "arrow.uturn.right.circle",
            "native Reader should show the forward progress control"
        )
        assertContains(
            nativeReader,
            "model.navigateForwards()",
            "native Reader forward progress control should restore its destination"
        )
        assertContains(
            nativeReader,
            "contentLanguage.displayCount(forRawCharacters: target)",
            "native Reader history controls should use the active Profile's display units"
        )
        assertContains(
            nativeReader,
            "private var statisticsString: String",
            "native Reader should format session statistics for its information chrome"
        )
        assertContains(
            nativeReader,
            "guard userConfig.enableStatistics else { return \"\" }",
            "native Reader should not show session statistics when Statistics is disabled"
        )
        assertContains(
            nativeReader,
            "if userConfig.readerShowReadingSpeed",
            "native Reader should honor the Show Reading Speed setting"
        )
        assertContains(
            nativeReader,
            "contentLanguage.displayCount(forRawCharacters: model.sessionStatistics.lastReadingSpeed)",
            "native Reader speed should use the active Profile's display units"
        )
        assertContains(
            nativeReader,
            "if userConfig.readerShowReadingTime",
            "native Reader should honor the Show Reading Time setting"
        )
        assertContains(
            nativeReader,
            "Duration.seconds(model.sessionStatistics.readingTime)",
            "native Reader should format the current session reading time"
        )
        assertContains(
            nativeReader,
            "let showStatistics = !statisticsString.isEmpty",
            "native Reader bottom information should render enabled session statistics"
        )
        assertContains(
            nativeReader,
            "private var statisticsAutostartMode: StatisticsAutostartMode = .off",
            "native Reader should retain the configured statistics autostart mode for every navigation source"
        )
        assertContains(
            nativeReader,
            "statisticsAutostartMode = userConfig.statisticsAutostartMode",
            "native Reader should configure its shared page-turn statistics policy"
        )
        assertContains(
            nativeReader,
            "func startTrackingOnPageTurnIfNeeded() {\n        if statisticsAutostartMode == .pageturn && !isTracking",
            "native Reader page-turn statistics should use the model's configured policy"
        )
        assertContains(
            nativeReader,
            "private func loadChapterForSasayaki(index: Int, progress: Double) {\n        guard let document,\n              document.spine.items.indices.contains(index) else {\n            return\n        }\n        startTrackingOnPageTurnIfNeeded()",
            "Sasayaki cross-chapter navigation should start page-turn statistics"
        )
        assertOccurrenceCountAtLeast(
            nativeReader,
            "self.parent.onPageTurn()\n                        self.parent.onProgressChanged",
            2,
            "Sasayaki same-chapter auto-scroll should start statistics only when WebView reports changed progress"
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
            "scope: .sasayaki",
            "native Reader should register Sasayaki actions with the unified shortcut manager"
        )
        assertContains(
            nativeReader,
            "SasayakiShortcutActions.previousCue.id",
            "native Reader should register the previous Sasayaki cue action"
        )
        assertContains(
            nativeReader,
            "SasayakiShortcutActions.nextCue.id",
            "native Reader should register the next Sasayaki cue action"
        )
        assertNotContains(
            nativeReader,
            "NativeReaderSasayakiShortcutMonitor",
            "native Reader should not restore a feature-private AppKit event monitor"
        )
        assertContains(
            shortcutManager,
            "NSEvent.addLocalMonitorForEvents",
            "the unified shortcut manager should own the AppKit key event monitor"
        )
        assertContains(
            shortcutBridge,
            "case 33: return \"[\"",
            "native shortcut matching should normalize the ANSI left bracket key code"
        )
        assertContains(
            shortcutBridge,
            "case 30: return \"]\"",
            "native shortcut matching should normalize the ANSI right bracket key code"
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
            nativeBuildScript,
            "--video",
            "native launcher should expose the Video build variant"
        )
        assertContains(
            nativeBuildScript,
            "Hoshi Reader Video",
            "native launcher should select the Video scheme"
        )
        assertContains(
            nativeBuildScript,
            "Debug-Video",
            "native launcher should resolve the Video build product"
        )
        print("reader popup/Sasayaki regressions passed")
    }
}
