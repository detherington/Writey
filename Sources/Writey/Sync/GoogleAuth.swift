import Foundation
import AppKit
import AuthenticationServices
import CryptoKit
import Combine

/// Google OAuth 2.0 + PKCE for installed apps, with refresh-token
/// persistence in the Keychain. Uses ASWebAuthenticationSession so the
/// user's existing Safari login is reused and tokens never touch our app
/// process beyond what we need.
@MainActor
final class GoogleAuth: NSObject, ObservableObject {
    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var userEmail: String?
    @Published private(set) var lastError: String?

    private var session: ASWebAuthenticationSession?
    private var codeVerifier: String = ""

    private static let refreshTokenAccount = "refresh_token"
    private static let emailAccount = "user_email"

    override init() {
        super.init()
        if Keychain.get(GoogleAuth.refreshTokenAccount) != nil {
            isSignedIn = true
            userEmail = Keychain.get(GoogleAuth.emailAccount)
        }
    }

    // MARK: - Sign in

    func beginSignIn() {
        guard SyncConfig.isConfigured else {
            lastError = "Add your OAuth client ID in SyncConfig.swift first."
            return
        }

        codeVerifier = Self.randomURLSafe(length: 64)
        let challenge = Self.codeChallenge(for: codeVerifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: SyncConfig.googleOAuthClientID),
            URLQueryItem(name: "redirect_uri", value: SyncConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: SyncConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let url = components.url else { return }

        session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: SyncConfig.googleOAuthRedirectScheme
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
            lastError = error.localizedDescription
            return
        }
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            lastError = "Missing authorization code."
            return
        }

        Task { await exchange(code: code) }
    }

    private func exchange(code: String) async {
        do {
            let tokens = try await Self.exchangeCodeForTokens(
                code: code,
                verifier: codeVerifier
            )
            if let refresh = tokens.refresh_token {
                Keychain.set(refresh, for: GoogleAuth.refreshTokenAccount)
            }
            Keychain.set(tokens.access_token, for: "access_token_cache")
            Keychain.set("\(Date().addingTimeInterval(TimeInterval(tokens.expires_in)).timeIntervalSince1970)",
                         for: "access_token_expiry")
            await fetchUserEmail(accessToken: tokens.access_token)
            isSignedIn = true
            lastError = nil
        } catch {
            lastError = "Sign in failed: \(error.localizedDescription)"
        }
    }

    private func fetchUserEmail(accessToken: String) async {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let email = json["email"] as? String {
            self.userEmail = email
            Keychain.set(email, for: GoogleAuth.emailAccount)
        }
    }

    func signOut() {
        Keychain.set(nil, for: GoogleAuth.refreshTokenAccount)
        Keychain.set(nil, for: GoogleAuth.emailAccount)
        Keychain.set(nil, for: "access_token_cache")
        Keychain.set(nil, for: "access_token_expiry")
        isSignedIn = false
        userEmail = nil
    }

    // MARK: - Access token (refreshes lazily)

    func validAccessToken() async throws -> String {
        if let cached = Keychain.get("access_token_cache"),
           let expiryStr = Keychain.get("access_token_expiry"),
           let expirySec = Double(expiryStr),
           Date().timeIntervalSince1970 < expirySec - 30 {
            return cached
        }
        guard let refresh = Keychain.get(GoogleAuth.refreshTokenAccount) else {
            throw AuthError.notSignedIn
        }
        let tokens = try await Self.refreshAccessToken(refreshToken: refresh)
        Keychain.set(tokens.access_token, for: "access_token_cache")
        Keychain.set("\(Date().addingTimeInterval(TimeInterval(tokens.expires_in)).timeIntervalSince1970)",
                     for: "access_token_expiry")
        return tokens.access_token
    }

    enum AuthError: LocalizedError {
        case notSignedIn
        case tokenExchangeFailed(String)
        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Not signed in to Google."
            case .tokenExchangeFailed(let body): return "Token exchange failed: \(body)"
            }
        }
    }

    // MARK: - Token network calls

    struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
        let token_type: String
        let scope: String?
    }

    private static func exchangeCodeForTokens(code: String, verifier: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": SyncConfig.googleOAuthClientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": SyncConfig.redirectURI
        ]
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw AuthError.tokenExchangeFailed(String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func refreshAccessToken(refreshToken: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": SyncConfig.googleOAuthClientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw AuthError.tokenExchangeFailed(String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - PKCE helpers

    private static func randomURLSafe(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension GoogleAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        DispatchQueue.main.sync {
            NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        }
    }
}
