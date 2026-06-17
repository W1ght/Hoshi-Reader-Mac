import Foundation

struct ShortcutConfiguration: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var bindings: [String: KeyboardShortcutBinding]

    init(
        version: Int = ShortcutConfiguration.currentVersion,
        bindings: [String: KeyboardShortcutBinding] = [:]
    ) {
        self.version = version
        self.bindings = bindings
    }

    static func migrating(
        storedData: Data?,
        legacyData: [String: Data],
        legacyActionIDs: [String: String]
    ) -> ShortcutConfiguration {
        let decoder = JSONDecoder()
        var configuration = storedData
            .flatMap { try? decoder.decode(ShortcutConfiguration.self, from: $0) }
            ?? ShortcutConfiguration()

        for (legacyKey, actionID) in legacyActionIDs
        where configuration.bindings[actionID] == nil {
            guard let data = legacyData[legacyKey],
                  let binding = try? decoder.decode(KeyboardShortcutBinding.self, from: data) else {
                continue
            }
            configuration.bindings[actionID] = binding
        }

        configuration.version = currentVersion
        return configuration
    }
}
