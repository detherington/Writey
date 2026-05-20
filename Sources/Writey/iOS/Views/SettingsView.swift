import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var auth: GoogleAuth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $theme.theme) {
                        ForEach(AppTheme.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Text("Dark mode uses true black for OLED comfort.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Google Docs") {
                    if auth.isSignedIn {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("Connected")
                                if let email = auth.userEmail {
                                    Text(email).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button("Sign Out") { auth.signOut() }
                        }
                    } else {
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
                    Text("Writey stores only a refresh token (in Keychain) and a per-document link to a Google Doc file ID. No content is sent until you sync.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
