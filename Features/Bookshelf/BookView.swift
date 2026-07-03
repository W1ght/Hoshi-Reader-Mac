//
//  BookView.swift
//  Niratan
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

enum BookshelfLayout {
    static let v050CoverWidth: CGFloat = 160
    static let columnSpacing: CGFloat = 20
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
        VStack(spacing: 6) {
            BookCover(
                book: book,
                progress: progress,
                isSelected: isSelected
            )
            
            Text(book.displayTitle)
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
    
    private let coverAspectRatio: CGFloat = 0.709
    private let innerCornerRadius: CGFloat = 6
    private let outerCornerRadius: CGFloat = 7
    
    var body: some View {
        cover
            .padding(3)
            .frame(width: width)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous)
                    .stroke(.primary.opacity(0.06), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 2)
    }
    
    private var cover: some View {
        VStack(spacing: progress == nil ? 0 : 3) {
            CoverImage(url: book.coverURL, maxPixelSize: 768) { image in
                image
                    .resizable()
                    .aspectRatio(coverAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous))
            } placeholder: {
                RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(coverAspectRatio, contentMode: .fit)
            }
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
                BookProgressStrip(progress: progress)
            }
        }
    }
    
    private func checkmark(color: Color) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 22))
            .foregroundStyle(.white, color)
    }
}

private struct BookProgressStrip: View {
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
