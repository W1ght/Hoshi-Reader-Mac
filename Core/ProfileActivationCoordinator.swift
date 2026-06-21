import Foundation

@MainActor
enum ProfileActivationCoordinator {
    @discardableResult
    static func activate(
        _ context: ProfileContext,
        userConfig: UserConfig,
        repository: ProfileRepository = .shared
    ) -> HoshiProfile {
        let profile = repository.resolve(context)
        ProfileSettingsStore.shared.activate(profileID: profile.id, userConfig: userConfig)
        DictionaryManager.shared.activateProfile(profile.id)
        AnkiManager.shared.activateProfile(profile.id)
        return profile
    }
}
