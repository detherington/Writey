import Foundation
import AppKit
import CryptoKit
import Combine

@MainActor
final class SyncManager: ObservableObject {
    @Published var isBusy: Bool = false
    @Published var statusLine: String?
    @Published var lastError: String?

    private let store = SyncLinkStore.shared

    func isLinked(fileURL: URL?) -> Bool {
        guard let fileURL else { return false }
        return store.link(for: fileURL) != nil
    }

    func currentLink(fileURL: URL?) -> SyncLink? {
        guard let fileURL else { return nil }
        return store.link(for: fileURL)
    }

    // MARK: - Create-and-link

    func createAndLink(
        document: WriteyDocument,
        fileURL: URL?,
        auth: GoogleAuth,
        suggestedName: String
    ) async {
        guard let fileURL else {
            statusLine = "Save this document to disk first (⌘S), then link it."
            return
        }
        do {
            isBusy = true
            statusLine = "Creating Google Doc…"
            defer { isBusy = false }

            let token = try await auth.validAccessToken()
            let html = HTMLConverter.html(from: document.attributedText)
            let drive = DriveAPI(accessToken: token)
            let meta = try await drive.createDoc(name: suggestedName, html: html)
            // Fetch back the canonical (Google-normalized) HTML to record the
            // baseline hash. We can't hash what we sent because Google
            // reformats HTML during the conversion to its Doc format, and
            // the next sync would otherwise falsely detect "remote changed".
            let canonicalRemote = try await drive.exportAsHTML(fileID: meta.id)

            let link = SyncLink(
                localPath: SyncLinkStore.key(for: fileURL),
                googleFileID: meta.id,
                lastSyncedRemoteContentHash: Self.contentHash(canonicalRemote),
                lastSyncedAt: Date(),
                localFingerprint: fingerprint(of: document.attributedText)
            )
            store.upsert(link)
            statusLine = "Linked to Google Doc · last synced just now"
        } catch {
            lastError = error.localizedDescription
            statusLine = "Sync failed: \(error.localizedDescription)"
        }
    }

    /// Attach an existing Google Doc by its file ID (e.g. extracted from a
    /// docs.google.com URL).
    func attachExisting(
        document: WriteyDocument,
        fileURL: URL?,
        auth: GoogleAuth,
        fileID: String,
        pullAfterAttach: Bool
    ) async {
        guard let fileURL else {
            statusLine = "Save this document to disk first (⌘S), then link it."
            return
        }
        do {
            isBusy = true
            statusLine = "Linking…"
            defer { isBusy = false }

            let token = try await auth.validAccessToken()
            let drive = DriveAPI(accessToken: token)
            let html = try await drive.exportAsHTML(fileID: fileID)

            if pullAfterAttach, let attr = HTMLConverter.attributedString(from: html) {
                document.attributedText = attr
            }

            let link = SyncLink(
                localPath: SyncLinkStore.key(for: fileURL),
                googleFileID: fileID,
                lastSyncedRemoteContentHash: Self.contentHash(html),
                lastSyncedAt: Date(),
                localFingerprint: fingerprint(of: document.attributedText)
            )
            store.upsert(link)
            statusLine = "Linked to Google Doc"
        } catch {
            lastError = error.localizedDescription
            statusLine = "Link failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Push / pull

    func sync(document: WriteyDocument, fileURL: URL?, auth: GoogleAuth) async {
        guard let fileURL, let link = store.link(for: fileURL) else {
            statusLine = "Not linked yet — create or attach a Google Doc first."
            return
        }
        do {
            isBusy = true
            statusLine = "Checking remote…"
            defer { isBusy = false }

            let token = try await auth.validAccessToken()
            let drive = DriveAPI(accessToken: token)

            // Single source of truth for whether the remote has changed:
            // the SHA-256 of the exported HTML. We always fetch this so we
            // can compare against our last baseline; if we end up pulling,
            // we reuse the same body instead of fetching twice.
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
                applyRemote(html: remoteHTML, hash: remoteHash, document: document, link: link)
                statusLine = "Pulled from Google · \(Self.timeString())"
            case (true, true):
                let choice = ConflictPrompt.ask()
                switch choice {
                case .keepLocal:
                    try await push(drive: drive, document: document, link: link)
                    statusLine = "Pushed local copy (overwrote remote) · \(Self.timeString())"
                case .keepRemote:
                    applyRemote(html: remoteHTML, hash: remoteHash, document: document, link: link)
                    statusLine = "Pulled remote copy (overwrote local) · \(Self.timeString())"
                case .cancel:
                    statusLine = "Sync cancelled — both sides have changes"
                }
            }
        } catch {
            lastError = error.localizedDescription
            statusLine = "Sync failed: \(error.localizedDescription)"
        }
    }

    private func push(drive: DriveAPI, document: WriteyDocument, link: SyncLink) async throws {
        let html = HTMLConverter.html(from: document.attributedText)
        _ = try await drive.updateDocHTML(fileID: link.googleFileID, html: html)
        // Re-fetch the canonical post-normalization HTML to record the
        // baseline hash, so the next sync doesn't see "remote changed" just
        // because Google reformatted the HTML during its Doc conversion.
        let canonicalRemote = try await drive.exportAsHTML(fileID: link.googleFileID)
        var updated = link
        updated.lastSyncedRemoteContentHash = Self.contentHash(canonicalRemote)
        updated.lastSyncedAt = Date()
        updated.localFingerprint = fingerprint(of: document.attributedText)
        store.upsert(updated)
    }

    /// Applies the freshly-fetched remote HTML to the document and records
    /// it as the new sync baseline. Used by both the "remote-only changed"
    /// path and the "user picked Keep Remote" conflict path.
    private func applyRemote(
        html: String,
        hash: String,
        document: WriteyDocument,
        link: SyncLink
    ) {
        guard let attr = HTMLConverter.attributedString(from: html) else { return }
        document.attributedText = attr
        var updated = link
        updated.lastSyncedRemoteContentHash = hash
        updated.lastSyncedAt = Date()
        updated.localFingerprint = fingerprint(of: document.attributedText)
        store.upsert(updated)
    }

    func unlink(fileURL: URL?) {
        guard let fileURL else { return }
        store.remove(fileURL: fileURL)
        statusLine = "Unlinked from Google Doc"
    }

    // MARK: - Helpers

    private func fingerprint(of attr: NSAttributedString) -> String {
        // Fingerprint the canonical form (no theme colors). Otherwise the
        // fingerprint would change every time the user toggles light/dark
        // mode, since switching themes re-bakes a different .foregroundColor
        // attribute across the whole storage — and the sync layer would
        // think the user had typed something.
        let canonical = attr.writeyCanonicalForm()
        let range = NSRange(location: 0, length: canonical.length)
        let data = (try? canonical.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func contentHash(_ html: String) -> String {
        SHA256.hash(data: Data(html.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func timeString() -> String {
        let df = DateFormatter()
        df.timeStyle = .short
        return df.string(from: Date())
    }
}

// MARK: - Conflict prompt

enum ConflictPrompt {
    enum Choice { case keepLocal, keepRemote, cancel }
    static func ask() -> Choice {
        let alert = NSAlert()
        alert.messageText = "Both versions have changed"
        alert.informativeText = "The local document and the Google Doc have both been edited since your last sync. Which copy should win?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Local (push)")
        alert.addButton(withTitle: "Keep Google (pull)")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .keepLocal
        case .alertSecondButtonReturn: return .keepRemote
        default:                       return .cancel
        }
    }
}
