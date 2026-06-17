import Foundation

enum ShortcutDispatchResolver {
    static func resolve(
        binding: KeyboardShortcutBinding,
        actions: [ShortcutAction],
        bindings: [String: KeyboardShortcutBinding],
        activeScopes: [ShortcutScope],
        handledActionIDs: Set<String>
    ) -> String? {
        candidates(
            binding: binding,
            actions: actions,
            bindings: bindings,
            activeScopes: activeScopes,
            handledActionIDs: handledActionIDs
        ).first
    }

    static func candidates(
        binding: KeyboardShortcutBinding,
        actions: [ShortcutAction],
        bindings: [String: KeyboardShortcutBinding],
        activeScopes: [ShortcutScope],
        handledActionIDs: Set<String>
    ) -> [String] {
        var result: [String] = []
        for scope in activeScopes {
            for action in actions
            where handledActionIDs.contains(action.id)
                && action.scopes.contains(scope)
                && bindings[action.id] == binding
                && !result.contains(action.id) {
                result.append(action.id)
            }
        }
        return result
    }
}
