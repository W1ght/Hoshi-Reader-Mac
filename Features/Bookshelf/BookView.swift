//
//  BookView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

nonisolated enum BookshelfLayout {
    static let v050CoverWidth: CGFloat = 160
    static let compactCoverWidth: CGFloat = 80
    static let columnSpacing: CGFloat = 20
    static let compactColumnSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 20
    static let titleHeight: CGFloat = 40
    static let progressTrackHeight: CGFloat = 3
    static let progressTextSize: CGFloat = 9
    static let progressRowSpacing: CGFloat = 5
}

struct BookView: View {
    let book: BookMetadata
    let progress: Double
    var isSelected: Bool = false
    
    var body: some View {
        ShelfBookCard(
            title: book.displayTitle,
            progress: progress,
            isSelected: isSelected
        ) {
            CoverImage(url: book.coverURL, maxPixelSize: 768) { image in
                image
                    .resizable()
                    .aspectRatio(0.709, contentMode: .fit)
            } placeholder: {
                Color.gray.opacity(0.3)
                    .aspectRatio(0.709, contentMode: .fit)
            }
        }
    }
}

struct ShelfBookCard<CoverContent: View>: View {
    let title: String
    let progress: Double
    var isSelected = false
    @ViewBuilder let coverContent: () -> CoverContent

    var body: some View {
        VStack(spacing: 6) {
            ShelfCoverFrame(
                progress: progress,
                isSelected: isSelected,
                coverContent: coverContent
            )

            Text(title)
                .font(.system(size: 16))
                .lineLimit(2)
                .frame(height: BookshelfLayout.titleHeight, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: BookshelfLayout.v050CoverWidth)
    }
}

struct BookCover: View {
    let book: BookMetadata
    var progress: Double? = nil
    var isSelected: Bool = false
    var width: CGFloat = BookshelfLayout.v050CoverWidth
    
    var body: some View {
        ShelfCoverFrame(
            progress: progress,
            isSelected: isSelected,
            width: width
        ) {
            CoverImage(url: book.coverURL, maxPixelSize: 768) { image in
                image
                    .resizable()
                    .aspectRatio(0.709, contentMode: .fit)
            } placeholder: {
                Color.gray.opacity(0.3)
                    .aspectRatio(0.709, contentMode: .fit)
            }
        }
    }
}

struct ShelfCoverFrame<CoverContent: View>: View {
    var progress: Double?
    var isSelected = false
    var width: CGFloat = BookshelfLayout.v050CoverWidth
    @ViewBuilder let coverContent: () -> CoverContent

    private let innerCornerRadius: CGFloat = 6
    private let outerCornerRadius: CGFloat = 7

    var body: some View {
        VStack(spacing: progress == nil ? 0 : 3) {
            coverContent()
                .clipShape(RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        checkmark(color: .blue)
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isSelected, let progress, progress >= 0.999 {
                        checkmark(color: .gray)
                            .padding(6)
                    }
                }

            if let progress {
                ShelfProgressStrip(progress: progress)
            }
        }
        .padding(3)
        .frame(width: width)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                .stroke(.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 2)
    }

    private func checkmark(color: Color) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 22))
            .foregroundStyle(.white, color)
    }
}

struct ShelfProgressStrip: View {
    let progress: Double

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        HStack(spacing: BookshelfLayout.progressRowSpacing) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.secondary.opacity(0.18))
                    Capsule()
                        .fill(.secondary.opacity(0.42))
                        .frame(width: proxy.size.width * clampedProgress)
                }
            }
            .frame(height: BookshelfLayout.progressTrackHeight)

            Text(String(format: "%.1f%%", clampedProgress * 100))
                .font(.system(size: BookshelfLayout.progressTextSize, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, 2)
        .frame(height: 10, alignment: .center)
    }
}

struct ShelfSectionHeader: View {
    let title: String
    let count: Int
    let isCollapsible: Bool
    @Binding var isCollapsed: Bool

    var body: some View {
        Group {
            if isCollapsible {
                Button {
                    withAnimation(.default.speed(1.5)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    header
                        .overlay(alignment: .trailing) {
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        }
                }
                .buttonStyle(.plain)
            } else {
                header
            }
        }
        .padding(.horizontal)
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
                .lineLimit(1)
            Text("\(count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

struct ShelfDragVisualState {
    let scale: CGFloat
    let yOffset: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat
    let highlightOpacity: Double
    let zIndex: Double

    static let source = ShelfDragVisualState(
        scale: 1.035,
        yOffset: -3,
        shadowOpacity: 0.20,
        shadowRadius: 12,
        shadowYOffset: 5,
        highlightOpacity: 0,
        zIndex: 2
    )

    static let target = ShelfDragVisualState(
        scale: 1.015,
        yOffset: 0,
        shadowOpacity: 0,
        shadowRadius: 0,
        shadowYOffset: 0,
        highlightOpacity: 0.42,
        zIndex: 1
    )

    static let inactive = ShelfDragVisualState(
        scale: 1,
        yOffset: 0,
        shadowOpacity: 0,
        shadowRadius: 0,
        shadowYOffset: 0,
        highlightOpacity: 0,
        zIndex: 0
    )
}

extension View {
    func shelfDragAppearance(_ state: ShelfDragVisualState) -> some View {
        scaleEffect(state.scale)
            .offset(y: state.yOffset)
            .shadow(
                color: .black.opacity(state.shadowOpacity),
                radius: state.shadowRadius,
                x: 0,
                y: state.shadowYOffset
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        Color.accentColor.opacity(state.highlightOpacity),
                        lineWidth: 2
                    )
                    .padding(-5)
                    .allowsHitTesting(false)
            }
            .zIndex(state.zIndex)
    }
}
