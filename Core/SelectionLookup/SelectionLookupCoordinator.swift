import AppKit
import Observation

enum SelectionLookupAvailability: Equatable {
    case disabled
    case permissionRequired
    case registered
    case shortcutConflict
    case unsupportedShortcut
    case registrationFailed
}

@Observable
@MainActor
final class SelectionLookupCoordinator {
    private(set) var availability: SelectionLookupAvailability = .disabled

    private let selectionReader: AccessibilitySelectionReading
    private let hotKeyRegistrar: SystemHotKeyRegistrar
    private weak var userConfig: UserConfig?

    init(
        selectionReader: AccessibilitySelectionReading = AccessibilitySelectionReader(),
        hotKeyRegistrar: SystemHotKeyRegistrar = SystemHotKeyRegistrar()
    ) {
        self.selectionReader = selectionReader
        self.hotKeyRegistrar = hotKeyRegistrar
    }

    func configure(userConfig: UserConfig) {
        self.userConfig = userConfig
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        guard let userConfig else { return }
        userConfig.crossAppSelectionLookupEnabled = enabled
        if enabled && !selectionReader.isTrusted {
            selectionReader.requestAccess()
        }
        refresh()
    }

    func requestAccess() {
        selectionReader.requestAccess()
        refresh()
    }

    func refresh() {
        guard let userConfig,
              userConfig.crossAppSelectionLookupEnabled else {
            hotKeyRegistrar.unregister()
            availability = .disabled
            QuickLookupPanelController.shared.close()
            return
        }
        guard selectionReader.isTrusted else {
            hotKeyRegistrar.unregister()
            availability = .permissionRequired
            return
        }

        let status = hotKeyRegistrar.register(
            binding: userConfig.shortcutBinding(for: GlobalShortcutActions.lookupSelectedText)
        ) { [weak self] in
            self?.lookupSelectedText()
        }
        availability = switch status {
        case .registered: .registered
        case .conflict: .shortcutConflict
        case .unsupportedBinding: .unsupportedShortcut
        case .inactive: .disabled
        case .failed: .registrationFailed
        }
    }

    private func lookupSelectedText() {
        guard let userConfig else { return }
        let fallbackAnchor = NSEvent.mouseLocation
        switch selectionReader.readSelectedText() {
        case .success(let snapshot):
            let profile = ProfileActivationCoordinator.activate(.global, userConfig: userConfig)
            QuickLookupPanelController.shared.present(
                text: snapshot.text,
                profileID: profile.id,
                anchorRect: snapshot.screenBounds ?? CGRect(origin: fallbackAnchor, size: .zero),
                userConfig: userConfig
            )
        case .failure(let error):
            if error == .permissionRequired {
                hotKeyRegistrar.unregister()
                availability = .permissionRequired
            }
            QuickLookupPanelController.shared.present(error: error, anchor: fallbackAnchor)
        }
    }
}
