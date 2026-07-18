import Foundation

@MainActor
enum ProfileActivationCoordinator {
    @discardableResult
    static func activateGlobal(
        userConfig: UserConfig,
        repository: ProfileRepository = .shared
    ) -> HoshiProfile {
        let profile = repository.activeProfile
        ProfileSettingsStore.shared.activate(profileID: profile.id, userConfig: userConfig)
        DictionaryManager.shared.activateProfile(profile.id)
        AnkiManager.shared.activateProfile(profile.id)
        return profile
    }
}
