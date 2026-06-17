import Foundation

struct ShortcutRegistry {
    let actions: [ShortcutAction]

    init(actions: [ShortcutAction]) {
        precondition(
            Set(actions.map(\.id)).count == actions.count,
            "Shortcut action identifiers must be unique"
        )
        self.actions = actions
    }

    func action(id: String) -> ShortcutAction? {
        actions.first { $0.id == id }
    }

    func actions(in category: ShortcutCategory) -> [ShortcutAction] {
        actions.filter { $0.category == category }
    }
}
