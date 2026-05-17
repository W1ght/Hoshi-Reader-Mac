//
//  Extensions.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import CryptoKit
import Foundation
import SwiftUI

enum AppPlatform {
    static var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    static var usesDesktopLayout: Bool {
        isMacCatalyst
    }

    static var topSafeArea: CGFloat {
        usesDesktopLayout ? 0 : UIApplication.topSafeArea
    }

    static var bottomSafeArea: CGFloat {
        usesDesktopLayout ? 0 : UIApplication.bottomSafeArea
    }
}

struct AppRelease: Equatable {
    var version: String
    var tagName: String
    var pageURL: URL
}

enum UpdateCheckAlert: Identifiable, Equatable {
    case available(AppRelease, currentVersion: String)
    case upToDate(currentVersion: String)
    case failed

    var id: String {
        switch self {
        case .available(let release, let currentVersion):
            "available-\(release.tagName)-\(currentVersion)"
        case .upToDate(let currentVersion):
            "up-to-date-\(currentVersion)"
        case .failed:
            "failed"
        }
    }
}

@MainActor
@Observable
final class UpdateChecker {
    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/W1ght/Hoshi-Reader-for-Mac/releases/latest")!
    private static let autoCheckKey = "updateCheckerLastAutomaticCheck"
    private static let autoCheckInterval: TimeInterval = 24 * 60 * 60

    var isChecking = false
    var availableRelease: AppRelease?
    var alert: UpdateCheckAlert?

    var hasAvailableUpdate: Bool {
        availableRelease != nil
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func checkAutomaticallyIfNeeded() async {
        guard AppPlatform.isMacCatalyst else {
            return
        }

        let defaults = UserDefaults.standard
        if let lastCheck = defaults.object(forKey: Self.autoCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < Self.autoCheckInterval {
            return
        }

        try? await Task.sleep(for: .seconds(3))
        defaults.set(Date(), forKey: Self.autoCheckKey)
        await check(manual: false)
    }

    func check(manual: Bool) async {
        guard AppPlatform.isMacCatalyst, !isChecking else {
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await fetchLatestRelease()
            if Self.isVersion(release.version, newerThan: currentVersion) {
                availableRelease = release
                alert = .available(release, currentVersion: currentVersion)
            } else {
                availableRelease = nil
                if manual {
                    alert = .upToDate(currentVersion: currentVersion)
                }
            }
        } catch {
            if manual {
                alert = .failed
            }
        }
    }

    private func fetchLatestRelease() async throws -> AppRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Hoshi-Reader-Mac", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else {
            throw URLError(.cannotParseResponse)
        }

        return AppRelease(
            version: Self.normalizedVersion(release.tagName),
            tagName: release.tagName,
            pageURL: release.htmlURL
        )
    }

    private static func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = versionParts(candidate)
        let currentParts = versionParts(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let lhs = index < candidateParts.count ? candidateParts[index] : 0
            let rhs = index < currentParts.count ? currentParts[index] : 0
            if lhs != rhs {
                return lhs > rhs
            }
        }

        return false
    }

    private static func versionParts(_ version: String) -> [Int] {
        normalizedVersion(version)
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }
}

extension String {
    func filtered() -> String {
        var text = self
        if let bodyRange = text.range(of: "(?s)<body.*?</body>", options: .regularExpression) {
            text = String(text[bodyRange])
        }
        text = text.replacingOccurrences(of: "(?s)<rt[^>]*>.*?</rt>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?s)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(
            of: "[^0-9A-Za-z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚａ-ｚｦ-ﾝ\\p{Radical}\\p{Unified_Ideograph}]",
            with: "",
            options: .regularExpression
        )
        return text
    }
}

extension BookMetadata {
    var coverURL: URL? {
        guard let coverPath = self.cover,
              let appDir = try? BookStorage.getAppDirectory() else {
            return nil
        }
        return appDir.appendingPathComponent(coverPath)
    }
}

extension Data {
    var sha1: String {
        Insecure.SHA1.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

extension URL {
    mutating func excludeFromBackup() throws {
        var resource = URLResourceValues()
        resource.isExcludedFromBackup = true
        try self.setResourceValues(resource)
    }
}

extension UIApplication {
    static var topSafeArea: CGFloat {
        (shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?
            .safeAreaInsets.top ?? 0
    }

    static var bottomSafeArea: CGFloat {
        (shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?
            .safeAreaInsets.bottom ?? 0
    }
}

struct LoadingOverlay: View {
    let message: String

    init(_ message: String = "Loading...") {
        self.message = message
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            Group {
                if #available(iOS 26, *) {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(message)
                            .lineLimit(1)
                    }
                    .padding(24)
                    .glassEffect()
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(message)
                            .lineLimit(1)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
        }
    }
}

// https://stackoverflow.com/questions/26341008/how-to-convert-uicolor-to-hex-and-display-in-nslog
extension UIColor {
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let multiplier: CGFloat = 255.9999999

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        if alpha == 1.0 {
            return String(
                format: "#%02lX%02lX%02lX",
                Int(red * multiplier),
                Int(green * multiplier),
                Int(blue * multiplier)
            )
        }
        else {
            return String(
                format: "#%02lX%02lX%02lX%02lX",
                Int(red * multiplier),
                Int(green * multiplier),
                Int(blue * multiplier),
                Int(alpha * multiplier)
            )
        }
    }
}

extension View {
    @ViewBuilder
    func conditionalGlassEffect() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive())
        } else {
            self
        }
    }
}
