import Foundation
import AuthenticationServices
import CryptoKit
import Combine

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Google OAuth 2.0 + PKCE for installed apps, with refresh-token
/// persistence in the Keychain. Uses ASWebAuthenticationSession so the
/// user's existing Safari login is reused.
@MainActor
final class GoogleAuth: NSObject, ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var userEmail: String?
    /// User-facing problem with sign-in, shown in Settings and the sync sheet.
    @Published private(set) var lastError: String?

    /// Full Drive access, so "attach an existing Google Doc" works for docs
    /// Writey didn't create (the narrower `drive.file` scope 404s on those).
    static let driveScope = "https://www.googleapis.com/auth/drive"
    private static let scopes = [driveScope, "https://www.googleapis.com/auth/userinfo.email"]

    private enum Account {
        static let refreshToken = "refresh_token"
        static let email = "user_email"
        static let accessToken = "access_token_cache"
        static let accessExpiry = "access_token_expiry"
        static let grantedScopes = "granted_scopes"
    }

    private var session: ASWebAuthenticationSession?
    private var codeVerifier = ""
    private var refreshTask: Task<String, Error>?

    override init() {
        super.init()
        guard Keychain.get(Account.refreshToken) != nil else { return }
        if Self.grantsDrive(Keychain.get(Account.grantedScopes)) {
            isSignedIn = true
            userEmail = Keychain.get(Account.email)
        } else {
            // Signed in under the old drive.file scope (or scopes unknown).
            clearTokens()
            lastError = "Writey now needs full Google Drive access. Sign in again to grant it."
        }
    }

    // MARK: - Sign in

    func beginSignIn() {
        guard SyncConfig.isConfigured else {
            lastError = "Add your OAuth client ID in SyncConfig.swift first."
            return
        }
        lastError = nil
        codeVerifier = Self.makeCodeVerifier()

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: SyncConfig.googleOAuthClientID),
            URLQueryItem(name: "redirect_uri", value: SyncConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let url = components.url else { return }

        session = ASWebAuthenticationSession(
            url: url,
            callback: .customScheme(SyncConfig.googleOAuthRedirectScheme)
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                self?.handleCallback(url: callbackURL, error: error)
            }
        }
        session?.presentationContextProvider = self
        session?.prefersEphemeralWebBrowserSession = false
        session?.start()
    }

    private func handleCallback(url: URL?, error: Error?) {
        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            lastError = "Sign-in failed: \(error.localizedDescription)"
            return
        }
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        if let denied = items.first(where: { $0.name == "error" })?.value {
            lastError = denied == "access_denied"
                ? "Sign-in was cancelled on Google's side."
                : "Google declined sign-in (\(denied))."
            return
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            lastError = "Sign-in failed: Google didn't return an authorization code."
            return
        }
        Task { await exchange(code: code) }
    }

    private func exchange(code: String) async {
        do {
            let tokens = try await Self.requestTokens([
                "client_id": SyncConfig.googleOAuthClientID,
                "code": code,
                "code_verifier": codeVerifier,
                "grant_type": "authorization_code",
                "redirect_uri": SyncConfig.redirectURI
            ])
            // Google's consent screen lets people untick individual scopes.
            guard Self.grantsDrive(tokens.scope) else {
                lastError = "Writey needs access to your Google Drive to sync. Sign in again and leave the Drive permission checked."
                return
            }
            guard let refresh = tokens.refresh_token else {
                lastError = "Sign-in failed: Google didn't return a refresh token."
                return
            }
            Keychain.set(refresh, for: Account.refreshToken)
            Keychain.set(tokens.scope, for: Account.grantedScopes)
            storeAccessToken(tokens)
            await fetchUserEmail(accessToken: tokens.access_token)
            isSignedIn = true
            lastError = nil
        } catch {
            lastError = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    private func fetchUserEmail(accessToken: String) async {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let email = json["email"] as? String {
            userEmail = email
            Keychain.set(email, for: Account.email)
        }
    }

    func signOut() {
        clearTokens()
        lastError = nil
    }

    private func clearTokens() {
        refreshTask?.cancel()
        refreshTask = nil
        for account in [Account.refreshToken, Account.email, Account.accessToken, Account.accessExpiry, Account.grantedScopes] {
            Keychain.set(nil, for: account)
        }
        isSignedIn = false
        userEmail = nil
    }

    // MARK: - Access token

    /// Returns a usable access token, refreshing it if it's expired (or if
    /// `forceRefresh`). Concurrent callers share one refresh request.
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh,
           let cached = Keychain.get(Account.accessToken),
           let expiry = Keychain.get(Account.accessExpiry).flatMap(Double.init),
           Date().timeIntervalSince1970 < expiry - 60 {
            return cached
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let refresh = Keychain.get(Account.refreshToken) else {
            throw AuthError.notSignedIn
        }

        let task = Task { () throws -> String in
            let tokens = try await Self.requestTokens([
                "client_id": SyncConfig.googleOAuthClientID,
                "refresh_token": refresh,
                "grant_type": "refresh_token"
            ])
            self.storeAccessToken(tokens)
            return tokens.access_token
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            return try await task.value
        } catch AuthError.refreshRejected {
            // Revoked, expired (7-day limit while the OAuth app is in Testing
            // mode), or the user removed Writey from their Google account.
            clearTokens()
            lastError = "Your Google sign-in expired. Sign in again to keep syncing."
            throw AuthError.reauthRequired
        }
    }

    private func storeAccessToken(_ tokens: TokenResponse) {
        Keychain.set(tokens.access_token, for: Account.accessToken)
        Keychain.set(String(Date().addingTimeInterval(TimeInterval(tokens.expires_in)).timeIntervalSince1970),
                     for: Account.accessExpiry)
    }

    enum AuthError: LocalizedError {
        case notSignedIn
        case reauthRequired
        case refreshRejected
        case tokenRequestFailed(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Not signed in to Google."
            case .reauthRequired, .refreshRejected: return "Your Google sign-in expired. Sign in again to keep syncing."
            case .tokenRequestFailed(let message): return message
            }
        }
    }

    // MARK: - Token endpoint

    struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
        let scope: String?
    }

    private static func requestTokens(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if json?["error"] as? String == "invalid_grant" {
                throw AuthError.refreshRejected
            }
            let detail = json?["error_description"] as? String ?? "HTTP \(http.statusCode)"
            throw AuthError.tokenRequestFailed("Google sign-in error: \(detail)")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    /// application/x-www-form-urlencoded: only unreserved characters pass
    /// through. (`.urlQueryAllowed` would leave `+`, `&` and `=` unescaped.)
    private static func formEncoded(_ fields: [String: String]) -> Data {
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }
            .joined(separator: "&")
            .utf8)
    }

    private static func grantsDrive(_ grantedScopes: String?) -> Bool {
        grantedScopes?.split(separator: " ").contains { $0 == driveScope } ?? false
    }

    // MARK: - PKCE

    private static func makeCodeVerifier() -> String {
        // 32 bytes from the system CSPRNG → 43 base64url characters.
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Called on the main thread; assumeIsolated avoids the libdispatch
        // self-deadlock that DispatchQueue.main.sync would cause here.
        MainActor.assumeIsolated {
            #if canImport(AppKit)
            return NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
            #elseif canImport(UIKit)
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap(\.windows)
            if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
                return window
            }
            // Sign-in is always started from a visible window, so a scene exists.
            return UIWindow(windowScene: scenes[0])
            #endif
        }
    }
}
