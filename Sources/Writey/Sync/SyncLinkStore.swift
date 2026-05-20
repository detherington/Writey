import Foundation

/// Persists the per-document mapping between a local Writey file and a
/// Google Doc file ID.
///
/// Stored at `~/Library/Application Support/Writey/links.json`, keyed by
/// the local file's absolute path. We initially tried to round-trip a
/// per-document UUID through RTF metadata, but Cocoa's RTF writer silently
/// drops custom document-attribute keys (it only honors a fixed allowlist
/// — .title, .author, .keywords, …), so every reopen minted a fresh UUID
/// and the link looked lost. Keying by path is robust to closing and
/// reopening; moving / renaming the file breaks the link, in which case
/// the user re-links from the sync sheet.
struct SyncLink: Codable {
    /// Absolute, standardized path of the local document this link
    /// belongs to. Primary key.
    var localPath: String
    var googleFileID: String
    /// SHA-256 of the *exported HTML* of the remote Google Doc at the
    /// moment of our last sync.
    ///
    /// We previously tried two cheaper signals to detect remote changes —
    /// `headRevisionId` (not populated by Drive API for Docs/Sheets/Slides)
    /// and `modifiedTime` (which, in practice, didn't reliably tick on
    /// browser edits within the test window). Hashing the exported HTML
    /// is the only mechanism that *actually* reflects whether the
    /// content has changed, at the cost of one extra API call per sync.
    var lastSyncedRemoteContentHash: String?
    var lastSyncedAt: Date?
    var localFingerprint: String?  // hash of the local RTF at last sync
}

final class SyncLinkStore {
    static let shared = SyncLinkStore()

    private let url: URL
    private var links: [String: SyncLink] = [:]

    init() {
        let fm = FileManager.default
        let appSupport = try! fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Writey", isDirectory: true)
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.url = appSupport.appendingPathComponent("links.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode([String: SyncLink].self, from: data) {
            links = decoded
        }
        // Pre-v0.2 entries (keyed by per-session UUID, with a `documentID`
        // field) silently fail to decode here and are effectively dropped.
        // Users re-link those documents once.
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(links) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func key(for fileURL: URL) -> String {
        fileURL.standardizedFileURL.path
    }

    func link(for fileURL: URL) -> SyncLink? {
        links[Self.key(for: fileURL)]
    }

    func upsert(_ link: SyncLink) {
        links[link.localPath] = link
        save()
    }

    func remove(fileURL: URL) {
        links.removeValue(forKey: Self.key(for: fileURL))
        save()
    }
}
