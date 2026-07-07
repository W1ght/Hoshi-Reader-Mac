import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum ShortcutRegistryTests {
    static func main() {
        let registry = ShortcutRegistry.application
        let ids = registry.actions.map(\.id)

        expect(Set(ids).count == ids.count, "action identifiers must be unique")
        expect(
            registry.action(id: ReaderShortcutActions.previousPage.id)?.category == .reader,
            "Reader actions should be registered in the Reader category"
        )
        expect(
            registry.action(id: PopupShortcutActions.dismiss.id)?.scopes == [.popup],
            "Popup dismissal should be limited to Popup scope"
        )

#if HOSHI_VIDEO
        expect(
            registry.action(id: VideoShortcutActions.playPause.id)?.category == .video,
            "Video actions should be registered in Video builds"
        )
        expect(
            registry.action(id: VideoShortcutActions.toggleSubtitleGapFastForward.id)?.scopes == [.video],
            "Video subtitle gap fast-forward should be registered in Video scope"
        )
#else
        expect(
            registry.action(id: "video.playPause") == nil,
            "Light builds should not register Video actions"
        )
#endif

        print("Shortcut registry tests passed")
    }
}
