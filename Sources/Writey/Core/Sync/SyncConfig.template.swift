// This is the COMMITTED template. The real file you'll edit is
// `SyncConfig.swift` (gitignored). On a fresh clone:
//
//     cp Sources/Writey/Sync/SyncConfig.template.swift \
//        Sources/Writey/Sync/SyncConfig.swift
//     # then edit SyncConfig.swift with your real OAuth values
//
// xcodegen is configured (via `excludes: "**/*.template.swift"` in
// project.yml) to skip this file at build time, so the two `enum
// SyncConfig` declarations don't collide.

import Foundation

enum SyncConfig {
    /// From Google Cloud Console → Credentials → OAuth 2.0 Client ID.
    /// e.g. "1234567890-abcdefg.apps.googleusercontent.com"
    static let googleOAuthClientID: String = ""

    /// The reversed client ID Google shows you in the same dialog.
    /// e.g. "com.googleusercontent.apps.1234567890-abcdefg"
    static let googleOAuthRedirectScheme: String = ""

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
