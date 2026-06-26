import AppKit
import SwiftUI

private final class QuickLookupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct QuickLookupStatusView: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct QuickLookupPanelContent: View {
    @Environment(UserConfig.self) private var userConfig
    @Bindable var coordinator: PopupPresentationCoordinator
    let profileID: String
    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ForEach(coordinator.popups) { popup in
                let popupID = popup.id
                PopupView(
                    userConfig: userConfig,
                    isVisible: Binding(
                        get: {
                            coordinator.popups.first(where: { $0.id == popupID })?.showPopup ?? false
                        },
                        set: { coordinator.setVisibility(id: popupID, visible: $0) }
                    ),
                    selectionData: popup.currentSelection,
                    lookupResults: popup.lookupResults,
                    dictionaryStyles: popup.dictionaryStyles,
                    screenSize: geometry.size,
                    isVertical: false,
                    isFullWidth: false,
                    coverURL: nil,
                    documentTitle: nil,
                    profileID: profileID,
                    clearSelection: popup.clearSelection,
                    onTextSelected: { selection in
                        coordinator.closeChildren(of: popupID)
                        return coordinator.present(selection: selection, userConfig: userConfig)
                    },
                    onTapOutside: {
                        coordinator.closeChildren(of: popupID)
                    },
                    onSwipeDismiss: {
                        if coordinator.popups.first?.id == popupID {
                            onClose()
                        } else {
                            coordinator.dismiss(id: popupID)
                        }
                    }
                )
                .id(popupID)
                .zIndex(Double(100 + (coordinator.popups.firstIndex(where: { $0.id == popupID }) ?? 0)))
            }
        }
    }
}

@MainActor
final class QuickLookupPanelController {
    static let shared = QuickLookupPanelController()

    private var panel: QuickLookupPanel?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var statusDismissTask: Task<Void, Never>?
    private var shortcutManager: ShortcutManager?

    private init() {}

    @discardableResult
    func present(
        text: String,
        profileID: String,
        anchor: CGPoint,
        userConfig: UserConfig
    ) -> Bool {
        statusDismissTask?.cancel()
        let coordinator = PopupPresentationCoordinator()
        let rootSelection = SelectionData(
            text: text,
            sentence: text,
            rect: CGRect(x: 8, y: 0, width: 1, height: 1),
            normalizedOffset: nil
        )
        guard coordinator.present(
            selection: rootSelection,
            userConfig: userConfig,
            replacingExisting: true
        ) != nil else {
            presentStatus(String(localized: "No dictionary result found."), anchor: anchor)
            return false
        }

        let size = CGSize(
            width: max(280, CGFloat(userConfig.popupWidth) + 16),
            height: max(240, CGFloat(userConfig.popupHeight) + 16)
        )
        let panel = configuredPanel(size: size, anchor: anchor)
        let shortcutManager = ShortcutManager(registry: .application)
        shortcutManager.configure(userConfig: userConfig)
        shortcutManager.manageEvents(for: panel)
        shortcutManager.install()
        self.shortcutManager = shortcutManager
        panel.contentView = NSHostingView(
            rootView: QuickLookupPanelContent(
                coordinator: coordinator,
                profileID: profileID,
                onClose: { QuickLookupPanelController.shared.close() }
            )
            .environment(userConfig)
            .environment(shortcutManager)
        )
        panel.orderFrontRegardless()
        installDismissMonitors()
        return true
    }

    func present(error: SelectionLookupError, anchor: CGPoint) {
        let message = switch error {
        case .permissionRequired: String(localized: "Accessibility permission is required for cross-app lookup.")
        case .noSelection: String(localized: "No selected text was found.")
        case .unsupported: String(localized: "The current app does not expose its selected text.")
        case .readFailed: String(localized: "Selected text could not be read.")
        }
        presentStatus(message, anchor: anchor)
    }

    func close() {
        statusDismissTask?.cancel()
        statusDismissTask = nil
        shortcutManager?.uninstall()
        shortcutManager = nil
        panel?.orderOut(nil)
        panel = nil
        removeDismissMonitors()
    }

    private func presentStatus(_ message: String, anchor: CGPoint) {
        statusDismissTask?.cancel()
        let panel = configuredPanel(size: CGSize(width: 360, height: 92), anchor: anchor)
        panel.contentView = NSHostingView(rootView: QuickLookupStatusView(message: message))
        panel.orderFrontRegardless()
        installDismissMonitors()
        statusDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    private func configuredPanel(size: CGSize, anchor: CGPoint) -> QuickLookupPanel {
        close()
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(origin: .zero, size: size)
        let frame = QuickLookupPanelGeometry.frame(anchor: anchor, size: size, visibleFrame: visibleFrame)
        let panel = QuickLookupPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if event.type == .keyDown, event.keyCode == 53 {
                    self.close()
                } else if event.type != .keyDown,
                          let panel = self.panel,
                          !panel.frame.contains(NSEvent.mouseLocation) {
                    self.close()
                }
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                close()
                return nil
            }
            if event.type != .keyDown,
               let panel,
               event.window !== panel,
               !panel.frame.contains(NSEvent.mouseLocation) {
                close()
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }
}
