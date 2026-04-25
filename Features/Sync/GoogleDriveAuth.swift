//
//  GoogleDriveAuth.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import AuthenticationServices
import OSLog

enum GoogleDriveAuthError: LocalizedError {
    case invalidClientId
    case invalidAuthURL
    case noCallbackURL
    case missingAuthorizationCode
    case tokenExchangeFailed(statusCode: Int)
    case notAuthenticated
    case tokenRefreshFailed
    case missingRefreshToken
    case tokenStorageFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidClientId:
            return "Invalid Client ID format"
        case .invalidAuthURL:
            return "Failed to construct authentication URL"
        case .noCallbackURL:
            return "No callback URL received"
        case .missingAuthorizationCode:
            return "Authorization code missing from callback"
        case .tokenExchangeFailed(let statusCode):
            return "Token exchange failed: \(statusCode)"
        case .notAuthenticated:
            return "Not authenticated\nPlease sign in"
        case .tokenRefreshFailed:
            return "Failed to refresh token\nPlease sign in again"
        case .missingRefreshToken:
            return "Google did not return a refresh token\nPlease try connecting again"
        case .tokenStorageFailed:
            return "Failed to save Google Drive credentials"
        }
    }
}

@MainActor
@Observable
class GoogleDriveAuth: NSObject {
    static let shared = GoogleDriveAuth()
    private static let logger = Logger(subsystem: "de.manhhao.hoshi", category: "Sync")
    private let authorizationSession = GoogleDriveAuthorizationSession()
    private override init() {}
    
    var isAuthenticated: Bool {
        TokenStorage.get("accessToken") != nil
            && TokenStorage.get("refreshToken") != nil
            && TokenStorage.get("clientId") != nil
    }
    
    func getAccessToken() throws -> String {
        guard let token = TokenStorage.get("accessToken") else {
            throw GoogleDriveAuthError.notAuthenticated
        }
        return token
    }
    
    func authenticate(clientId: String) async throws {
        let clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidGoogleClientId(clientId) else {
            throw GoogleDriveAuthError.invalidClientId
        }
        let scheme = clientId.components(separatedBy: ".").reversed().joined(separator: ".")
        let redirectUri = "\(scheme):/oauth2callback"
        
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.file"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        
        guard let authURL = components.url else {
            throw GoogleDriveAuthError.invalidAuthURL
        }
        
        let code = try await getAuthorizationCode(from: authURL, callbackScheme: scheme)
        try await exchangeCode(code: code, clientId: clientId, redirectUri: redirectUri)
        guard TokenStorage.save(clientId, for: "clientId") else {
            TokenStorage.clear()
            throw GoogleDriveAuthError.tokenStorageFailed
        }
        Self.logger.info("Google Drive authentication completed; stored credentials available: \(self.isAuthenticated, privacy: .public)")
    }
    
    func refreshAccessToken() async throws -> String {
        guard let refreshToken = TokenStorage.get("refreshToken"),
              let clientId = TokenStorage.get("clientId") else {
            throw GoogleDriveAuthError.notAuthenticated
        }
        
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        Self.logTokenEndpointResponse(data: data, response: response, context: "refresh")
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            TokenStorage.clear()
            throw GoogleDriveAuthError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard TokenStorage.save(tokenResponse.accessToken, for: "accessToken") else {
            TokenStorage.clear()
            throw GoogleDriveAuthError.tokenStorageFailed
        }
        
        return tokenResponse.accessToken
    }
    
    private func getAuthorizationCode(from url: URL, callbackScheme: String) async throws -> String {
        let callbackURL = try await authorizationSession.callbackURL(from: url, callbackScheme: callbackScheme)
        
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true) else {
            throw GoogleDriveAuthError.missingAuthorizationCode
        }
        let queryNames = components.queryItems?.map(\.name).joined(separator: ",") ?? ""
        Self.logger.info("Google auth callback received with query keys: \(queryNames, privacy: .public)")

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleDriveAuthError.missingAuthorizationCode
        }
        
        return code
    }
    
    private func exchangeCode(code: String, clientId: String, redirectUri: String) async throws {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let params = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code"
        ]
        
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        Self.logTokenEndpointResponse(data: data, response: response, context: "exchange")
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GoogleDriveAuthError.tokenExchangeFailed(statusCode: statusCode)
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = tokenResponse.refreshToken else {
            TokenStorage.clear()
            throw GoogleDriveAuthError.missingRefreshToken
        }

        guard TokenStorage.save(tokenResponse.accessToken, for: "accessToken"),
              TokenStorage.save(refresh, for: "refreshToken") else {
            TokenStorage.clear()
            throw GoogleDriveAuthError.tokenStorageFailed
        }
    }
    
    private static func isValidGoogleClientId(_ clientId: String) -> Bool {
        clientId.range(of: #"^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$"#, options: .regularExpression) != nil
    }

    private static func logTokenEndpointResponse(data: Data, response: URLResponse, context: String) {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let fields = redactedJSONFieldSummary(from: data)
        logger.info("Google token \(context, privacy: .public) response status \(statusCode, privacy: .public), fields: \(fields, privacy: .public)")
    }

    private static func redactedJSONFieldSummary(from data: Data) -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "non-json"
        }
        let keys = json.keys.sorted().joined(separator: ",")
        let hasAccessToken = json["access_token"] != nil
        let hasRefreshToken = json["refresh_token"] != nil
        let error = json["error"] as? String
        if let error {
            return "keys=[\(keys)], error=\(error)"
        }
        return "keys=[\(keys)], has_access_token=\(hasAccessToken), has_refresh_token=\(hasRefreshToken)"
    }
}

private nonisolated final class GoogleDriveAuthorizationSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    func callbackURL(from url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                self?.activeSession = nil
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: GoogleDriveAuthError.noCallbackURL)
                }
            }

            session.presentationContextProvider = self
            activeSession = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                Self.currentPresentationAnchor()
            }
        }

        var anchor: ASPresentationAnchor?
        DispatchQueue.main.sync {
            anchor = MainActor.assumeIsolated {
                Self.currentPresentationAnchor()
            }
        }
        return anchor ?? ASPresentationAnchor()
    }

    @MainActor
    private static func currentPresentationAnchor() -> ASPresentationAnchor {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let windowScene else {
            return UIWindow()
        }
        return windowScene.keyWindow ?? windowScene.windows.first ?? UIWindow(windowScene: windowScene)
    }
}

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
