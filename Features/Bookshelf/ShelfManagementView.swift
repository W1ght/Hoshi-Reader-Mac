//
//  ShelfManagementView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct ShelfManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserConfig.self) private var userConfig
    var viewModel: BookshelfViewModel
    @State private var newShelfName = ""
    
    var body: some View {
        nativeBody
    }

    @ViewBuilder
    private var nativeBody: some View {
        @Bindable var userConfig = userConfig
        NavigationStack {
            Form {
                Section {
                    Toggle("Reading Shelf", isOn: $userConfig.bookshelfShowReading)
                } footer: {
                    Text("Shows books you've started but not finished.")
                }

                Section("Shelves") {
                    if viewModel.shelves.isEmpty {
                        ContentUnavailableView(
                            "No Shelves",
                            systemImage: "folder",
                            description: Text("Create a shelf to organize books.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ForEach(Array(viewModel.shelves.enumerated()), id: \.element.name) { index, shelf in
                            HStack(spacing: 12) {
                                Label(shelf.name, systemImage: "folder")
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                shelfReorderButton(
                                    systemImage: "chevron.up",
                                    isDisabled: index == 0
                                ) {
                                    viewModel.moveShelves(
                                        from: IndexSet(integer: index),
                                        to: max(index - 1, 0)
                                    )
                                }

                                shelfReorderButton(
                                    systemImage: "chevron.down",
                                    isDisabled: index == viewModel.shelves.count - 1
                                ) {
                                    viewModel.moveShelves(
                                        from: IndexSet(integer: index),
                                        to: min(index + 2, viewModel.shelves.count)
                                    )
                                }

                                Button(role: .destructive) {
                                    viewModel.deleteShelf(name: shelf.name)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete Shelf")
                            }
                        }
                    }
                }

                Section("Add Shelf") {
                    HStack(spacing: 10) {
                        TextField("Shelf name", text: $newShelfName)
                            .onSubmit(addShelf)

                        Button(action: addShelf) {
                            Label("Add", systemImage: "plus")
                        }
                        .disabled(trimmedShelfName.isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Manage Shelves")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 440, idealWidth: 520, maxWidth: 620, minHeight: 420, idealHeight: 500)
    }

    private var trimmedShelfName: String {
        newShelfName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addShelf() {
        guard !trimmedShelfName.isEmpty else { return }
        viewModel.createShelf(name: trimmedShelfName)
        newShelfName = ""
    }

    private func shelfReorderButton(
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
    }
}
