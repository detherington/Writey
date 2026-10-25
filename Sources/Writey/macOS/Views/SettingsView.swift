import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var auth: GoogleAuth

    var body: some View {
        TabView {
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            textTab
                .tabItem { Label("Text", systemImage: "textformat") }
            googleTab
                .tabItem { Label("Google Docs", systemImage: "doc.text") }
        }
        .frame(width: 480, height: 540)
    }

    private var appearanceTab: some View {
        Form {
            Picker("Theme", selection: $theme.theme) {
                ForEach(AppTheme.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.inline)
            Text("Dark mode uses true black (#000000) for OLED and high-contrast comfort.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
    }

    private var textTab: some View {
        Form {
            TypographySettings()
            Text("How Writey shows your writing on this Mac. Documents keep their own formatting.")
                .font(.caption)
                .foregroundColor(.secondary)
            Divider()
            FocusSettings()
            Text(FocusSettings.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
            Divider()
            ReferenceSettings()
            Text(ReferenceSettings.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
    }

    private var googleTab: some View {
        Form {
            if auth.isSignedIn {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    VStack(alignment: .leading) {
                        Text("Connected to Google")
                        if let email = auth.userEmail {
                            Text(email).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button("Sign Out") { auth.signOut() }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in to enable bidirectional Google Docs sync.")
                    Button {
                        auth.beginSignIn()
                    } label: {
                        Label("Sign In with Google", systemImage: "person.crop.circle.badge.plus")
                    }
                    if !SyncConfig.isConfigured {
                        Text("Add your OAuth client ID in SyncConfig.swift to enable sign-in.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            if let error = auth.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Divider()
            Text("Writey stores only a refresh token (in Keychain) and a per-document link to a Google Doc file ID. No content is sent until you sync.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
    }
}
