import Foundation

/// A document's reference pane as it was last left: what it showed, on
/// which side, how wide, and whether it was open.
struct ReferenceMemory: Codable, Equatable {
    var source: ReferenceSource?
    var side: ReferenceSide
    /// The reference pane's share of the window's width.
    var fraction: Double
    var isVisible: Bool

    static let defaultFraction = 0.42
}

/// Remembers each document's reference, so reopening a draft brings back
/// the research beside it, plus the last few references for quick reuse.
///
/// Stored at `~/Library/Application Support/Writey/references.json`,
/// keyed by the document's `StableFilePath`, and moved along with
/// the document on rename, Recently Deleted and restore.
@MainActor
final class ReferenceStore {
    static let shared = ReferenceStore()

    private struct Stored: Codable {
        var memories: [String: ReferenceMemory] = [:]
        var recents: [ReferenceSource] = []
    }

    private static let recentsLimit = 10
    private let url: URL
    private var stored = Stored()

    var recents: [ReferenceSource] { stored.recents }

    init() {
        let folder = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ))?.appendingPathComponent("Writey", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("references.json")
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        }
    }

    func memory(for fileURL: URL) -> ReferenceMemory? {
        stored.memories[StableFilePath.string(for: fileURL)]
    }

    func setMemory(_ memory: ReferenceMemory, for fileURL: URL) {
        let key = StableFilePath.string(for: fileURL)
        guard stored.memories[key] != memory else { return }
        stored.memories[key] = memory
        save()
    }

    func noteRecent(_ source: ReferenceSource) {
        stored.recents.removeAll { $0 == source }
        stored.recents.insert(source, at: 0)
        stored.recents = Array(stored.recents.prefix(Self.recentsLimit))
        save()
    }

    /// A document moved: its own memory follows it, and so does every
    /// reference that points at it.
    func move(from oldURL: URL, to newURL: URL) {
        let oldKey = StableFilePath.string(for: oldURL)
        if let memory = stored.memories.removeValue(forKey: oldKey) {
            stored.memories[StableFilePath.string(for: newURL)] = memory
        }
        for (key, memory) in stored.memories where memory.source.map({ points($0, at: oldKey) }) == true {
            stored.memories[key]?.source = .document(newURL)
        }
        stored.recents = stored.recents.map { points($0, at: oldKey) ? .document(newURL) : $0 }
        save()
    }

    /// A document is gone for good. References to it stay, and say so.
    func remove(fileURL: URL) {
        stored.memories.removeValue(forKey: StableFilePath.string(for: fileURL))
        stored.recents.removeAll { points($0, at: StableFilePath.string(for: fileURL)) }
        save()
    }

    private func points(_ source: ReferenceSource, at key: String) -> Bool {
        if case .document(let url) = source { return StableFilePath.string(for: url) == key }
        return false
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(stored) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
