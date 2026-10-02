import Foundation
import CryptoKit
import Combine

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
final class SyncManager: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var statusLine: String?

    private let store = SyncLinkStore.shared

    /// Platform UI for the "both sides changed" prompt.
    var conflictResolver: (any SyncConflictResolver)?

    /// The open editor. Pulls go through it so they're undoable and mark the
    /// document as edited (which is what gets them autosaved).
    weak var textEditor: (any DocumentTextEditing)?

    func isLinked(fileURL: URL?) -> Bool {
        currentLink(fileURL: fileURL) != nil
    }

    func currentLink(fileURL: URL?) -> SyncLink? {
        fileURL.flatMap { store.link(for: $0) }
    }

    // MARK: - Link

    func createAndLink(document: WriteyDocument, fileURL: URL?, auth: GoogleAuth, suggestedName: String) async {
        guard !isBusy else { return }
        guard let fileURL else {
            statusLine = "Save this document first, then link it."
            return
        }
        isBusy = true
        defer { isBusy = false }
        statusLine = "Creating Google Doc…"

        do {
            let drive = driveClient(auth)
            let meta = try await drive.createDoc(name: suggestedName, html: HTMLConverter.html(from: document.attributedText))
            // Hash Google's normalized export, not what we sent: Google
            // rewrites HTML on import, so our own HTML would never match.
            let canonicalRemote = try await drive.exportAsHTML(fileID: meta.id)
            store.upsert(SyncLink(
                localPath: SyncLinkStore.key(for: fileURL),
                googleFileID: meta.id,
                lastSyncedRemoteContentHash: Self.contentHash(canonicalRemote),
                lastSyncedAt: Date(),
                localFingerprint: fingerprint(of: document.attributedText)
            ))
            statusLine = "Linked to a new Google Doc · \(Self.timeString())"
        } catch {
            report(error, prefix: "Couldn't create the Google Doc")
        }
    }

    /// Attach an existing Google Doc by file ID and pull its contents.
    func attachExisting(document: WriteyDocument, fileURL: URL?, auth: GoogleAuth, fileID: String) async {
        guard !isBusy else { return }
        guard let fileURL else {
            statusLine = "Save this document first, then link it."
            return
        }
        isBusy = true
        defer { isBusy = false }
        statusLine = "Linking…"

        do {
            let html = try await driveClient(auth).exportAsHTML(fileID: fileID)
            let backupNote = try replaceLocalText(of: document, fileURL: fileURL, withRemoteHTML: html)
            store.upsert(SyncLink(
                localPath: SyncLinkStore.key(for: fileURL),
                googleFileID: fileID,
                lastSyncedRemoteContentHash: Self.contentHash(html),
                lastSyncedAt: Date(),
                localFingerprint: fingerprint(of: document.attributedText)
            ))
            statusLine = "Linked and pulled from Google · \(Self.timeString())" + backupNote
        } catch {
            report(error, prefix: "Couldn't link that Google Doc")
        }
    }

    func unlink(fileURL: URL?) {
        guard let fileURL else { return }
        store.remove(fileURL: fileURL)
        statusLine = "Unlinked from Google Doc"
    }

    // MARK: - Sync

    func sync(document: WriteyDocument, fileURL: URL?, auth: GoogleAuth) async {
        guard !isBusy else { return }
        guard let fileURL, let link = store.link(for: fileURL) else {
            statusLine = "Not linked yet — create or attach a Google Doc first."
            return
        }
        isBusy = true
        defer { isBusy = false }
        statusLine = "Checking Google Docs…"

        do {
            let drive = driveClient(auth)
            // The hash of the exported HTML is the source of truth for "did
            // the remote change". If we end up pulling, we reuse this body.
            let remoteHTML = try await drive.exportAsHTML(fileID: link.googleFileID)
            let remoteHash = Self.contentHash(remoteHTML)
            let remoteChanged = remoteHash != link.lastSyncedRemoteContentHash
            let localChanged = fingerprint(of: document.attributedText) != link.localFingerprint

            switch (localChanged, remoteChanged) {
            case (false, false):
                statusLine = "Already in sync · \(Self.timeString())"
            case (true, false):
                try await push(drive: drive, document: document, link: link)
                statusLine = "Pushed to Google · \(Self.timeString())"
            case (false, true):
                let note = try pull(html: remoteHTML, hash: remoteHash, document: document, fileURL: fileURL, link: link)
                statusLine = "Pulled from Google · \(Self.timeString())" + note
            case (true, true):
                switch await conflictResolver?.resolveSyncConflict() ?? .cancel {
                case .keepLocal:
                    try await push(drive: drive, document: document, link: link)
                    statusLine = "Pushed your copy over Google's · \(Self.timeString())"
                case .keepRemote:
                    let note = try pull(html: remoteHTML, hash: remoteHash, document: document, fileURL: fileURL, link: link)
                    statusLine = "Replaced your copy with Google's · \(Self.timeString())" + note
                case .cancel:
                    statusLine = "Sync cancelled — both copies have changes"
                }
            }
        } catch {
            report(error, prefix: "Sync failed")
        }
    }

    private func push(drive: DriveAPI, document: WriteyDocument, link: SyncLink) async throws {
        _ = try await drive.updateDocHTML(fileID: link.googleFileID, html: HTMLConverter.html(from: document.attributedText))
        let canonicalRemote = try await drive.exportAsHTML(fileID: link.googleFileID)
        var updated = link
        updated.lastSyncedRemoteContentHash = Self.contentHash(canonicalRemote)
        updated.lastSyncedAt = Date()
        updated.localFingerprint = fingerprint(of: document.attributedText)
        store.upsert(updated)
    }

    private func pull(html: String, hash: String, document: WriteyDocument, fileURL: URL, link: SyncLink) throws -> String {
        let backupNote = try replaceLocalText(of: document, fileURL: fileURL, withRemoteHTML: html)
        var updated = link
        updated.lastSyncedRemoteContentHash = hash
        updated.lastSyncedAt = Date()
        updated.localFingerprint = fingerprint(of: document.attributedText)
        store.upsert(updated)
        return backupNote
    }

    /// Backs up the local text if it differs from what's coming in, then
    /// replaces it through the editor. Returns a status-line suffix saying
    /// where the backup went.
    private func replaceLocalText(of document: WriteyDocument, fileURL: URL, withRemoteHTML html: String) throws -> String {
        guard let incoming = HTMLConverter.attributedString(from: html) else {
            throw SyncError.unreadableRemote
        }
        var note = ""
        if fingerprint(of: document.attributedText) != fingerprint(of: incoming),
           let location = SyncBackup.save(document.attributedText, for: fileURL) {
            note = " · previous text saved (\(location))"
        }
        if let textEditor {
            textEditor.replaceAllText(with: incoming, actionName: "Pull from Google Docs")
        } else {
            document.attributedText = incoming
        }
        return note
    }

    // MARK: - Helpers

    private func driveClient(_ auth: GoogleAuth) -> DriveAPI {
        DriveAPI { forceRefresh in
            try await auth.validAccessToken(forceRefresh: forceRefresh)
        }
    }

    private func report(_ error: Error, prefix: String) {
        if let authError = error as? GoogleAuth.AuthError, case .reauthRequired = authError {
            statusLine = "Google sign-in expired. Sign in again from Settings to keep syncing."
        } else {
            statusLine = "\(prefix): \(error.localizedDescription)"
        }
    }

    enum SyncError: LocalizedError {
        case unreadableRemote
        var errorDescription: String? { "Writey couldn't read the Google Doc's contents." }
    }

    /// Hash of the canonical (theme-color-free) RTF, so switching light/dark
    /// doesn't look like a local edit.
    private func fingerprint(of attr: NSAttributedString) -> String {
        let canonical = attr.writeyCanonicalForm()
        let data = (try? canonical.data(
            from: NSRange(location: 0, length: canonical.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func contentHash(_ html: String) -> String {
        SHA256.hash(data: Data(html.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func timeString() -> String {
        Date().formatted(date: .omitted, time: .shortened)
    }
}
