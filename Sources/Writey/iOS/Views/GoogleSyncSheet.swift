import SwiftUI
import UIKit

struct GoogleSyncSheet: View {
    @ObservedObject var document: WriteyDocument
    var fileURL: URL?

    @EnvironmentObject var auth: GoogleAuth
    @EnvironmentObject var sync: SyncManager
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var attachURLString: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.title)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading) {
                            Text("Google Docs Sync").font(.headline)
                            Text(fileURL?.lastPathComponent ?? "Untitled (unsaved)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if !auth.isSignedIn {
                    Section {
                        Button {
                            auth.beginSignIn()
                        } label: {
                            Label("Sign In with Google", systemImage: "person.crop.circle.badge.plus")
                        }
                        if !SyncConfig.isConfigured {
                            Text("Configure your OAuth client ID in SyncConfig.swift first.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                } else if fileURL == nil {
                    Section {
                        Label("Save this document first", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Writey keys the Google Doc link by the local file's path. Save somewhere (the Files app, iCloud Drive), then come back to link it.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let link = sync.currentLink(fileURL: fileURL) {
                    linkedSection(link: link)
                } else {
                    unlinkedSections
                }

                if let status = sync.statusLine {
                    Section {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var unlinkedSections: some View {
        Group {
            Section("Create a new Google Doc") {
                Text("Upload this document's current contents to a new Google Doc and link them for sync.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    Task {
                        await sync.createAndLink(
                            document: document,
                            fileURL: fileURL,
                            auth: auth,
                            suggestedName: fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
                        )
                    }
                } label: {
                    Label("Create & Link", systemImage: "plus.circle")
                }
                .disabled(sync.isBusy)
            }

            Section("Attach an existing Google Doc") {
                Text("Paste a Google Doc URL or file ID. We'll pull its contents.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("docs.google.com/document/d/…", text: $attachURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    let id = extractFileID(from: attachURLString)
                    guard !id.isEmpty else { return }
                    Task {
                        await sync.attachExisting(
                            document: document,
                            fileURL: fileURL,
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
        }
    }

    private func linkedSection(link: SyncLink) -> some View {
        Group {
            Section("Linked Google Doc") {
                Text("File ID: \(link.googleFileID)")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                if let when = link.lastSyncedAt {
                    Text("Last synced: \(when.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Section {
                Button {
                    Task { await sync.sync(document: document, fileURL: fileURL, auth: auth) }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(sync.isBusy)

                Button(role: .destructive) {
                    sync.unlink(fileURL: fileURL)
                } label: {
                    Label("Unlink", systemImage: "link.badge.plus")
                }

                Button {
                    if let url = URL(string: "https://docs.google.com/document/d/\(link.googleFileID)/edit") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open in Google Docs", systemImage: "safari")
                }
            }
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
