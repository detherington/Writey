import Foundation

/// Google OAuth + Drive API configuration.
///
/// Real values are *not* in this file. They live in
/// `Sources/Writey/Config/Secrets.xcconfig` (gitignored), flow through
/// `Base.xcconfig` → Xcode build settings → Info.plist substitution, and
/// are read at runtime from `Bundle.main.infoDictionary`.
///
/// SETUP:
/// 1. https://console.cloud.google.com/apis/credentials — create an
///    OAuth 2.0 Client ID, type "iOS", bundle ID `com.writey.Writey`.
///    Enable the Google Drive API.
/// 2. `cp Sources/Writey/Config/Secrets.template.xcconfig
///        Sources/Writey/Config/Secrets.xcconfig`
/// 3. Edit `Secrets.xcconfig` and paste your real client ID + the
///    reverse-domain redirect scheme it suggests.
/// 4. `xcodegen generate` and rebuild.
///
/// PKCE is used end-to-end, so no client secret is required or stored.
enum SyncConfig {
    static var googleOAuthClientID: String {
        infoString("OAuthClientID") ?? ""
    }

    static var googleOAuthRedirectScheme: String {
        infoString("OAuthRedirectScheme") ?? ""
    }

    /// We use the narrow `drive.file` scope so Writey only sees Docs it
    /// created or that the user explicitly opens with it — never the
    /// user's entire Drive. `userinfo.email` lets us show who's signed in.
    static let scopes: [String] = [
        "https://www.googleapis.com/auth/drive.file",
        "https://www.googleapis.com/auth/userinfo.email"
    ]

    static var redirectURI: String {
        "\(googleOAuthRedirectScheme):/oauth2redirect"
    }

    static var isConfigured: Bool {
        !googleOAuthClientID.isEmpty &&
            googleOAuthClientID != "REPLACE_WITH_YOUR_CLIENT_ID.apps.googleusercontent.com" &&
            !googleOAuthRedirectScheme.isEmpty &&
            googleOAuthRedirectScheme.hasPrefix("com.googleusercontent.apps.")
    }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }
}
