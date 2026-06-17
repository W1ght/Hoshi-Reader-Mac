import AppKit
import Observation

protocol ShortcutEventCaptureResponder: AnyObject {}

typealias ShortcutHandler = @MainActor () -> Bool

@Observable
@MainActor
final class ShortcutManager {
    private struct Registration {
        let scope: ShortcutScope
        let handlers: [String: ShortcutHandler]
        let order: Int
    }

    private let registry: ShortcutRegistry
    private weak var userConfig: UserConfig?
    private var registrations: [UUID: Registration] = [:]
    private var nextRegistrationOrder = 0
    private var monitor: Any?

    init(registry: ShortcutRegistry) {
        self.registry = registry
    }

    func configure(userConfig: UserConfig) {
        self.userConfig = userConfig
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        registrations.removeAll()
    }

    @discardableResult
    func register(
        scope: ShortcutScope,
        handlers: [String: ShortcutHandler]
    ) -> UUID {
        let id = UUID()
        registrations[id] = Registration(
            scope: scope,
            handlers: handlers,
            order: nextRegistrationOrder
        )
        nextRegistrationOrder += 1
        return id
    }

    func unregister(_ id: UUID?) {
        guard let id else { return }
        registrations.removeValue(forKey: id)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard shouldHandle(event),
              let binding = KeyboardShortcutBinding(nsEvent: event),
              let userConfig else {
            return event
        }

        let orderedRegistrations = registrations.values.sorted {
            let firstPriority = Self.priority(for: $0.scope)
            let secondPriority = Self.priority(for: $1.scope)
            if firstPriority == secondPriority {
                return $0.order > $1.order
            }
            return firstPriority > secondPriority
        }
        let activeScopes = orderedRegistrations.map(\.scope)
        let handledActionIDs = Set(
            orderedRegistrations.flatMap { $0.handlers.keys }
        )
        let bindings = Dictionary(
            uniqueKeysWithValues: registry.actions.map {
                ($0.id, userConfig.shortcutBinding(for: $0))
            }
        )
        let candidates = ShortcutDispatchResolver.candidates(
            binding: binding,
            actions: registry.actions,
            bindings: bindings,
            activeScopes: activeScopes,
            handledActionIDs: handledActionIDs
        )

        for actionID in candidates {
            for registration in orderedRegistrations {
                if registration.handlers[actionID]?() == true {
                    return nil
                }
            }
        }
        return event
    }

    private func shouldHandle(_ event: NSEvent) -> Bool {
        guard !event.isARepeat else { return false }
        let responder = event.window?.firstResponder
        if responder is ShortcutEventCaptureResponder {
            return false
        }
        if let textView = responder as? NSTextView {
            return !textView.isEditable
        }
        if responder is NSTextField {
            return false
        }
        return true
    }

    private static func priority(for scope: ShortcutScope) -> Int {
        switch scope {
        case .popup: 500
        case .sasayaki: 400
        case .reader, .dictionary, .video: 300
        case .global: 100
        }
    }
}
