import SwiftUI

struct GoogleSyncSheet: View {
    @ObservedObject var document: WriteyDocument
    var fileURL: URL?

    @EnvironmentObject var auth: GoogleAuth
    @EnvironmentObject var sync: SyncManager
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var attachURLString: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !auth.isSignedIn {
                signInPrompt
            } else if let link = sync.currentLink(documentID: document.documentID) {
                linkedView(link: link)
            } else {
                unlinkedView
            }

            if let status = sync.statusLine {
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading) {
                Text("Google Docs Sync").font(.headline)
                Text(fileURL?.lastPathComponent ?? "Untitled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to Google to enable bidirectional sync.")
            Button {
                auth.beginSignIn()
            } label: {
                Label("Sign In with Google", systemImage: "person.crop.circle.badge.plus")
            }
            if !SyncConfig.isConfigured {
                Text("Configure your OAuth client ID in `SyncConfig.swift` first.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var unlinkedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Create a new Google Doc") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Upload this document's current contents to a new Google Doc and link them for sync.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button {
                        Task {
                            await sync.createAndLink(
                                document: document,
                                auth: auth,
                                suggestedName: fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
                            )
                        }
                    } label: {
                        Label("Create & Link", systemImage: "plus.circle")
                    }
                    .disabled(sync.isBusy)
                }
                .padding(.vertical, 4)
            }

            GroupBox("Attach an existing Google Doc") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Paste a Google Doc URL or file ID. We'll pull its contents.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("docs.google.com/document/d/…", text: $attachURLString)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        let id = extractFileID(from: attachURLString)
                        guard !id.isEmpty else { return }
                        Task {
                            await sync.attachExisting(
                                document: document,
                                auth: auth,
                                fileID: id,
                                pullAfterAttach: true
                            )
                        }
                    } label: {
                        Label("Attach & Pull", systemImage: "link")
                    }
                    .disabled(sync.isBusy || attachURLString.isEmpty)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func linkedView(link: SyncLink) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Linked Google Doc") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("File ID: \(link.googleFileID)")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    if let when = link.lastSyncedAt {
                        Text("Last synced: \(when.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    Task { await sync.sync(document: document, auth: auth) }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(sync.isBusy)

                Button(role: .destructive) {
                    sync.unlink(document: document)
                } label: {
                    Label("Unlink", systemImage: "link.badge.plus")
                }
            }

            Button {
                if let url = URL(string: "https://docs.google.com/document/d/\(link.googleFileID)/edit") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in Google Docs", systemImage: "safari")
            }
            .buttonStyle(.link)
        }
    }

    private func extractFileID(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.host?.contains("docs.google.com") == true {
            let parts = url.pathComponents
            if let i = parts.firstIndex(of: "d"), i + 1 < parts.count {
                return parts[i + 1]
            }
        }
        return trimmed
    }
}
