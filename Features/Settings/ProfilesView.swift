//
//  ProfilesView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct ProfilesView: View {
    @Environment(UserConfig.self) private var userConfig
    @State private var repository = ProfileRepository.shared
    @State private var isCreating = false
    @State private var editingProfile: HoshiProfile?
    @State private var deletingProfile: HoshiProfile?
    @State private var draftName = ""
    @State private var draftLanguage: ContentLanguageProfile = .japanese
    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        NativeSettingsForm {
            NativeSettingsSectionCard("Active Profile") {
                ForEach(Array(repository.index.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { NativeSettingsSeparator() }
                    profileRow(profile)
                }
            } footer: {
                Text("Dictionary, Reader appearance and Anki mining settings follow the active profile.")
            }

            ForEach(ContentLanguageProfile.allCases) { language in
                let profiles = repository.profiles(for: language)
                if !profiles.isEmpty {
                    NativeSettingsSectionCard(defaultTitle(for: language)) {
                        NativeSettingsRow("Default Profile") {
                            Picker("", selection: primaryBinding(for: language)) {
                                ForEach(profiles) { profile in
                                    Text(profile.displayName).tag(profile.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }
                    }
                }
            }

            NativeSettingsSectionCard {
                Label("New Profile", systemImage: "plus.circle")
            } content: {
                NativeSettingsButtonRow {
                    Button("Create Profile") {
                        draftName = ""
                        draftLanguage = repository.activeProfile.language
                        isCreating = true
                    }
                }
            }
        }
        .navigationTitle("Profiles")
        .sheet(isPresented: $isCreating) {
            profileEditor(title: "New Profile", confirmTitle: "Create") {
                do {
                    let created = try repository.createProfile(
                        name: draftName,
                        language: draftLanguage,
                        copyFromProfileID: repository.activeProfile.id
                    )
                    try activate(created)
                    isCreating = false
                } catch {
                    present(error)
                }
            }
        }
        .sheet(item: $editingProfile) { profile in
            profileEditor(title: "Rename Profile", confirmTitle: "Save", locksLanguage: true) {
                do {
                    try repository.renameProfile(profile.id, to: draftName)
                    editingProfile = nil
                } catch {
                    present(error)
                }
            }
        }
        .confirmationDialog(
            "Delete \"\(deletingProfile?.name ?? "")\"?",
            isPresented: Binding(
                get: { deletingProfile != nil },
                set: { if !$0 { deletingProfile = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let deletingProfile else { return }
                do {
                    if ProfileSettingsStore.shared.appliedProfileID == deletingProfile.id {
                        ProfileSettingsStore.shared.activate(
                            profileID: repository.index.defaultProfileId,
                            userConfig: userConfig
                        )
                    }
                    try repository.deleteProfile(deletingProfile.id)
                    DictionaryManager.shared.activateProfile(repository.activeProfile.id)
                    AnkiManager.shared.activateProfile(repository.activeProfile.id)
                    self.deletingProfile = nil
                } catch {
                    present(error)
                }
            }
            Button("Cancel", role: .cancel) { deletingProfile = nil }
        } message: {
            Text("Books using this profile will fall back to automatic selection.")
        }
        .alert("Profile Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func profileRow(_ profile: HoshiProfile) -> some View {
        NativeSettingsButtonRow {
            Button {
                do { try activate(profile) } catch { present(error) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: repository.index.globalActiveProfileId == profile.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(repository.index.globalActiveProfileId == profile.id ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                        Text(languageTitle(profile.language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if profile.isDefault {
                        Text("Built-in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Rename") {
                    draftName = profile.name
                    draftLanguage = profile.language
                    editingProfile = profile
                }
                if !profile.isDefault {
                    Button("Delete", role: .destructive) {
                        deletingProfile = profile
                    }
                }
            }
        }
    }

    private func primaryBinding(for language: ContentLanguageProfile) -> Binding<String> {
        Binding(
            get: {
                repository.index.primaryProfileIdsByLanguage[language.rawValue]
                    ?? repository.profiles(for: language).first?.id
                    ?? repository.index.defaultProfileId
            },
            set: { profileID in
                do { try repository.setPrimaryProfile(profileID, for: language) } catch { present(error) }
            }
        )
    }

    private func profileEditor(
        title: LocalizedStringKey,
        confirmTitle: LocalizedStringKey,
        locksLanguage: Bool = false,
        onConfirm: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2.bold())
            TextField("Profile Name", text: $draftName)
            Picker("Language", selection: $draftLanguage) {
                Text("Japanese").tag(ContentLanguageProfile.japanese)
                Text("English").tag(ContentLanguageProfile.english)
            }
            .disabled(locksLanguage)
            HStack {
                Spacer()
                Button("Cancel") {
                    isCreating = false
                    editingProfile = nil
                }
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func activate(_ profile: HoshiProfile) throws {
        ProfileSettingsStore.shared.activate(profileID: profile.id, userConfig: userConfig)
        try repository.setGlobalActiveProfile(profile.id)
        DictionaryManager.shared.activateProfile(profile.id)
        AnkiManager.shared.activateProfile(profile.id)
    }

    private func defaultTitle(for language: ContentLanguageProfile) -> LocalizedStringKey {
        language == .english ? "Default for English" : "Default for Japanese"
    }

    private func languageTitle(_ language: ContentLanguageProfile) -> LocalizedStringKey {
        language == .english ? "English" : "Japanese"
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
