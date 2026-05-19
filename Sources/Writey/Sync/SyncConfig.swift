import Foundation

/// Google OAuth + Drive API configuration.
///
/// SETUP:
/// 1. Go to https://console.cloud.google.com/apis/credentials
/// 2. Create an OAuth 2.0 Client ID. Pick application type "iOS" (which
///    accepts a custom URL scheme as the redirect URI).
/// 3. Set the bundle ID to `com.writey.Writey` (matches project.yml).
/// 4. Enable the **Google Drive API** for your project.
/// 5. Paste the client ID below.
///
/// The custom redirect URI Google expects (and that we register in
/// project.yml's CFBundleURLTypes) is the reversed client ID:
///
///   com.googleusercontent.apps.<CLIENT_ID_PREFIX>:/oauth2redirect
///
/// PKCE is used so no client secret is required.
enum SyncConfig {
    /// e.g. "1234567890-abcdefg.apps.googleusercontent.com"
    static let googleOAuthClientID: String = ""

    /// e.g. "com.googleusercontent.apps.1234567890-abcdefg"
    /// Must also appear in `Info.plist` -> CFBundleURLTypes.
    static let googleOAuthRedirectScheme: String = ""

    /// We use the narrow `drive.file` scope so Writey only sees Docs it
    /// created or that the user explicitly opens with it — never the
    /// user's entire Drive. Add `userinfo.email` so we can show who's
    /// signed in.
    static let scopes: [String] = [
        "https://www.googleapis.com/auth/drive.file",
        "https://www.googleapis.com/auth/userinfo.email"
    ]

    static var redirectURI: String {
        "\(googleOAuthRedirectScheme):/oauth2redirect"
    }

    static var isConfigured: Bool {
        !googleOAuthClientID.isEmpty && !googleOAuthRedirectScheme.isEmpty
    }
}
