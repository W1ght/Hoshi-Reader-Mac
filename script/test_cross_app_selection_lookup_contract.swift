import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func source(_ path: String) throws -> String {
    try String(contentsOfFile: path, encoding: .utf8)
}

@main
private enum CrossAppSelectionLookupContractTests {
    static func main() throws {
        let panel = try source("NativeMac/QuickLookupPanelController.swift")
        let reader = try source("Core/SelectionLookup/AccessibilitySelectionReader.swift")
        let coordinator = try source("Core/SelectionLookup/SelectionLookupCoordinator.swift")
        let app = try source("NativeMac/HoshiNativeMacApp.swift")
        let settings = try source("Features/Settings/KeyboardShortcutsView.swift")
        let config = try source("Core/UserConfig.swift")

        expect(panel.contains(".nonactivatingPanel"), "quick lookup must use a non-activating panel")
        expect(panel.contains("visibleFrame"), "quick lookup placement must respect the usable display frame")
        expect(panel.contains("PopupView("), "quick lookup must reuse the shared popup result surface")
        expect(panel.contains("profileID: profileID"), "quick lookup mining must carry the resolved profile ID")
        expect(panel.contains("ShortcutManager(registry: .application)"), "quick lookup must create a shortcut manager for the shared popup surface")
        expect(panel.contains(".environment(shortcutManager)"), "quick lookup must inject ShortcutManager before hosting PopupView")
        expect(panel.contains("shortcutManager.manageEvents(for: panel)"), "quick lookup shortcuts must be scoped to the transient panel window")
        expect(panel.contains("shortcutManager?.uninstall()"), "quick lookup must remove popup shortcut registrations when the panel closes")
        expect(panel.contains("orderFrontRegardless"), "quick lookup should show without activating the main app")
        expect(panel.contains(".canJoinAllSpaces"), "quick lookup should remain available in the current Space")
        expect(!panel.contains(".moveToActiveSpace"), "quick lookup must not combine mutually exclusive Space behaviors")

        expect(coordinator.contains("AccessibilitySelectionReader"), "coordinator must read selection through accessibility")
        expect(coordinator.contains("SystemHotKeyRegistrar"), "coordinator must use the unified system hot key registrar")
        expect(coordinator.contains("ProfileActivationCoordinator.activate(.global"), "coordinator must explicitly activate the global profile")
        expect(!coordinator.contains("NSPasteboard"), "cross-app lookup must not read the clipboard")
        expect(!coordinator.contains("CGEvent"), "cross-app lookup must not synthesize copy events")
        expect(reader.contains("kAXSelectedTextAttribute"), "reader must prefer direct accessibility selected-text reads")
        expect(reader.contains("CopyShortcutSelectionFallback"), "reader must fall back to the copy shortcut for apps without AX selected text")
        expect(reader.contains("NSPasteboard"), "copy fallback must read selected text from the pasteboard")
        expect(reader.contains("CGEvent"), "copy fallback must synthesize the standard copy shortcut")
        expect(reader.contains("snapshot.restore"), "copy fallback must restore the previous pasteboard contents")

        expect(app.contains("SelectionLookupCoordinator"), "app lifecycle must own one selection lookup coordinator")
        expect(settings.contains("crossAppSelectionLookupEnabled"), "shortcut settings must expose the opt-in switch")
        expect(config.contains("crossAppSelectionLookupEnabled"), "selection lookup opt-in must persist in UserConfig")

        print("Cross-app selection lookup contract tests passed")
    }
}
