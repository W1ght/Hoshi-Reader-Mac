//
//  ShelfManagementView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

nonisolated enum ShelfManagementLayout {
    static let panelWidth: CGFloat = 420
    static let panelHeight: CGFloat = 460
    static let contentPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
    static let surfacePadding: CGFloat = 12
}

struct ShelfManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserConfig.self) private var userConfig
    var viewModel: BookshelfViewModel
    
    var body: some View {
        nativeBody
    }

    @ViewBuilder
    private var nativeBody: some View {
        @Bindable var userConfig = userConfig
        NativeReaderSheetPanel("Manage Shelves", onClose: {
            dismiss()
        }) {
            ShelfManagementForm(
                showReading: $userConfig.bookshelfShowReading,
                shelves: viewModel.shelves.map {
                    ShelfManagementEntry(id: $0.name, name: $0.name)
                },
                onCreate: viewModel.createShelf,
                onDelete: viewModel.deleteShelf,
                onMove: viewModel.moveShelves
            )
        }
        .frame(
            width: ShelfManagementLayout.panelWidth,
            height: ShelfManagementLayout.panelHeight
        )
    }
}

struct ShelfManagementEntry: Identifiable {
    let id: String
    let name: String
}

struct ShelfManagementForm: View {
    @Binding var showReading: Bool
    let shelves: [ShelfManagementEntry]
    let onCreate: (String) -> Void
    let onDelete: (String) -> Void
    let onMove: (IndexSet, Int) -> Void
    @State private var newShelfName = ""

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: ShelfManagementLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: ShelfManagementLayout.sectionSpacing) {
                    shelfManagementSurface {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Reading Shelf", isOn: $showReading)
                                .toggleStyle(.switch)

                            Text("Shows books you've started but not finished.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shelves")
                            .font(.headline)

                        shelfManagementSurface {
                            shelvesContent
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add Shelf")
                            .font(.headline)

                        shelfManagementSurface {
                            HStack(spacing: 10) {
                                TextField("Shelf name", text: $newShelfName)
                                    .nativeSettingsTextField()
                                    .onSubmit(addShelf)

                                Button(action: addShelf) {
                                    Label("Add", systemImage: "plus")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(
                                    trimmedShelfName.isEmpty
                                        ? Color.secondary
                                        : Color.accentColor
                                )
                                .padding(.horizontal, 8)
                                .padding(.vertical, 7)
                                .disabled(trimmedShelfName.isEmpty)
                            }
                        }
                    }
                }
            }
            .padding(ShelfManagementLayout.contentPadding)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    @ViewBuilder
    private var shelvesContent: some View {
        if shelves.isEmpty {
            ContentUnavailableView(
                "No Shelves",
                systemImage: "folder",
                description: Text("Create a shelf to organize books.")
            )
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(shelves.enumerated()), id: \.element.id) { index, shelf in
                    HStack(spacing: 12) {
                        Label(shelf.name, systemImage: "folder")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        shelfReorderButton(
                            systemImage: "chevron.up",
                            isDisabled: index == 0
                        ) {
                            onMove(
                                IndexSet(integer: index),
                                max(index - 1, 0)
                            )
                        }

                        shelfReorderButton(
                            systemImage: "chevron.down",
                            isDisabled: index == shelves.count - 1
                        ) {
                            onMove(
                                IndexSet(integer: index),
                                min(index + 2, shelves.count)
                            )
                        }

                        Button(role: .destructive) {
                            onDelete(shelf.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete Shelf")
                    }
                    .padding(.vertical, 6)

                    if index < shelves.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var trimmedShelfName: String {
        newShelfName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addShelf() {
        guard !trimmedShelfName.isEmpty else { return }
        onCreate(trimmedShelfName)
        newShelfName = ""
    }

    private func shelfManagementSurface<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(ShelfManagementLayout.surfacePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
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
