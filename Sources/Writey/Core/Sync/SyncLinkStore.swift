import Foundation

/// Persists the per-document mapping between a local Writey file and a
/// Google Doc file ID.
///
/// Stored at `~/Library/Application Support/Writey/links.json`, keyed by
/// the local file's `StableFilePath`, so links into the app's own
/// container survive iOS moving it. We initially tried to round-trip a
/// per-document UUID through RTF metadata, but Cocoa's RTF writer silently
/// drops custom document-attribute keys (it only honors a fixed allowlist
/// — .title, .author, .keywords, …), so every reopen minted a fresh UUID
/// and the link looked lost. Keying by path is robust to closing and
/// reopening; moving / renaming the file breaks the link, in which case
/// the user re-links from the sync sheet.
struct SyncLink: Codable {
    /// `StableFilePath` of the local document this link belongs to:
    /// "~/…" inside the app's container, absolute elsewhere. Primary key.
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

    private static let stablePathsKey = "SyncLinksKeyedByStablePath"
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
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: SyncLink].self, from: data) {
            links = decoded
        }
        // Pre-v0.2 entries (keyed by per-session UUID, with a `documentID`
        // field) silently fail to decode here and are effectively dropped.
        // Users re-link those documents once.
        if !UserDefaults.standard.bool(forKey: Self.stablePathsKey) {
            rekeyByStablePath()
            UserDefaults.standard.set(true, forKey: Self.stablePathsKey)
        }
    }

    /// One time: links saved by earlier builds are keyed by absolute path,
    /// which breaks when iOS moves the app's data container. Re-key them
    /// by `StableFilePath`, finding links into an earlier container in the
    /// current one. If two land on the same file, the last synced wins.
    private func rekeyByStablePath() {
        guard !links.isEmpty else { return }
        var rekeyed: [String: SyncLink] = [:]
        for (path, var link) in links {
            var key = StableFilePath.string(for: StableFilePath.url(for: path))
            if key.hasPrefix("/"), let moved = Self.keyInCurrentContainer(forOldPath: path) {
                key = moved
            }
            link.localPath = key
            if let other = rekeyed[key], (other.lastSyncedAt ?? .distantPast) > (link.lastSyncedAt ?? .distantPast) {
                continue
            }
            rekeyed[key] = link
        }
        links = rekeyed
        save()
    }

    /// A path into an earlier iOS data container of this app
    /// (…/Containers/Data/Application/<UUID>/…), moved into the current
    /// one. Only if the file is there: documents opened in place from
    /// another app's folder have paths of the same shape.
    private static func keyInCurrentContainer(forOldPath path: String) -> String? {
        let marker = "/Containers/Data/Application/"
        let home = NSHomeDirectory()
        guard home.contains(marker), let range = path.range(of: marker) else { return nil }
        let rest = path[range.upperBound...]
        guard let slash = rest.firstIndex(of: "/"), UUID(uuidString: String(rest[..<slash])) != nil else { return nil }
        let moved = URL(fileURLWithPath: home + rest[slash...])
        guard FileManager.default.fileExists(atPath: moved.path) else { return nil }
        return StableFilePath.string(for: moved)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(links) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func key(for fileURL: URL) -> String {
        StableFilePath.string(for: fileURL)
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

    /// Keeps a document's link when Writey itself renames or moves the file.
    func move(from oldURL: URL, to newURL: URL) {
        guard var link = links.removeValue(forKey: Self.key(for: oldURL)) else { return }
        link.localPath = Self.key(for: newURL)
        links[link.localPath] = link
        save()
    }
}
