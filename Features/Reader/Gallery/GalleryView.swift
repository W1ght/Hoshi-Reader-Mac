//
//  GalleryView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct ReaderGalleryImage: Identifiable, Equatable {
    let url: URL
    let isRead: Bool

    var id: URL { url }
}

struct GalleryView: View {
    let images: [ReaderGalleryImage]
    let isLoading: Bool
    let backgroundColor: Color
    let onDismiss: () -> Void

    @State private var selectedImageIndex: Int?
    @State private var revealedImageIDs: Set<URL> = []

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 16, alignment: .top)
    ]

    var body: some View {
        NativeReaderSheetPanel("Gallery", onClose: onDismiss) {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                        let isBlurred = !item.isRead && !revealedImageIDs.contains(item.id)
                        Button {
                            selectedImageIndex = index
                        } label: {
                            CoverImage(url: item.url, maxPixelSize: 1600) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .blur(radius: isBlurred ? 18 : 0)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.secondary.opacity(0.1))
                                    .aspectRatio(0.7, contentMode: .fit)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                if isBlurred {
                                    Image(systemName: "eye.slash.fill")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(12)
                                        .background(.black.opacity(0.45), in: Circle())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            isBlurred
                                ? Text("Unread Image")
                                : Text(verbatim: item.url.lastPathComponent)
                        )
                    }
                }
                .padding(20)
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                } else if images.isEmpty {
                    ContentUnavailableView("No Images", systemImage: "photo.on.rectangle")
                }
            }
        }
        .overlay {
            if selectedImageIndex != nil {
                GalleryImagePreview(
                    images: images,
                    selectedImageIndex: $selectedImageIndex,
                    revealedImageIDs: $revealedImageIDs,
                    backgroundColor: backgroundColor
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }
}

private struct GalleryImagePreview: View {
    let images: [ReaderGalleryImage]
    @Binding var selectedImageIndex: Int?
    @Binding var revealedImageIDs: Set<URL>
    let backgroundColor: Color

    private var currentIndex: Int? {
        guard let selectedImageIndex,
              images.indices.contains(selectedImageIndex) else {
            return nil
        }
        return selectedImageIndex
    }

    var body: some View {
        Group {
            if let currentIndex {
                NativeFullscreenImageView(
                    url: images[currentIndex].url,
                    backgroundColor: backgroundColor,
                    isBlurred: !images[currentIndex].isRead
                        && !revealedImageIDs.contains(images[currentIndex].id),
                    onReveal: {
                        revealedImageIDs.insert(images[currentIndex].id)
                    },
                    onDismiss: dismiss
                )
                .overlay {
                    HStack {
                        navigationButton(
                            systemName: "chevron.left",
                            label: "Previous",
                            key: .leftArrow,
                            isEnabled: currentIndex > images.startIndex,
                            action: showPrevious
                        )

                        Spacer()

                        navigationButton(
                            systemName: "chevron.right",
                            label: "Next",
                            key: .rightArrow,
                            isEnabled: currentIndex < images.index(before: images.endIndex),
                            action: showNext
                        )
                    }
                    .padding(.horizontal, 32)
                }
            } else {
                Color.clear
                    .onAppear(perform: dismiss)
            }
        }
        .onExitCommand(perform: dismiss)
    }

    private func navigationButton(
        systemName: String,
        label: LocalizedStringKey,
        key: KeyEquivalent,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        NativeGlassCircleButton(systemName: systemName, diameter: 44, fontSize: 17, action: action)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.35)
            .keyboardShortcut(key, modifiers: [])
            .accessibilityLabel(Text(label))
            .help(Text(label))
    }

    private func showPrevious() {
        guard let currentIndex, currentIndex > images.startIndex else { return }
        showImage(at: images.index(before: currentIndex))
    }

    private func showNext() {
        guard let currentIndex, currentIndex < images.index(before: images.endIndex) else { return }
        showImage(at: images.index(after: currentIndex))
    }

    private func showImage(at index: Int) {
        selectedImageIndex = index
    }

    private func dismiss() {
        selectedImageIndex = nil
    }
}
