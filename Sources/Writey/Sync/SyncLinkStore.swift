import Foundation

/// Persists the per-document mapping between a local Writey file and a
/// Google Doc file ID.
///
/// Stored at `~/Library/Application Support/Writey/links.json`, keyed by
/// the document's own stable `documentID` (which we round-trip into RTF
/// metadata). This means the link survives renames and moves.
struct SyncLink: Codable {
    var documentID: String
    var googleFileID: String
    /// The remote doc's `modifiedTime` (RFC 3339 string, e.g.
    /// "2026-05-20T15:32:17.123Z") at the moment of our last sync.
    /// We *used to* use `headRevisionId` here, but Drive API v3 does not
    /// populate that field for Google Docs/Sheets/Slides — only for
    /// arbitrary binary files. `modifiedTime` works for both.
    var lastSyncedModifiedTime: String?
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
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(links) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func link(for documentID: String) -> SyncLink? {
        links[documentID]
    }

    func upsert(_ link: SyncLink) {
        links[link.documentID] = link
        save()
    }

    func remove(documentID: String) {
        links.removeValue(forKey: documentID)
        save()
    }
}
