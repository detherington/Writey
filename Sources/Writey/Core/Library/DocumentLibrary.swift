import Foundation
import UniformTypeIdentifiers

/// The documents in Writey's folder: iCloud Drive ▸ Writey, or — when iCloud
/// Drive is off — On My iPhone ▸ Writey (on the Mac, the app's container).
/// Shared by the iOS home screen and the Mac library window.
///
/// In iCloud an `NSMetadataQuery` keeps the list live, including documents
/// that exist in iCloud but aren't downloaded yet, and edits made on other
/// devices. File operations are coordinated, so an open document follows a
/// rename instead of losing its file.
@MainActor
final class DocumentLibrary: ObservableObject {
    struct Item: Identifiable, Hashable {
        let url: URL
        var modified: Date
        var isDownloaded: Bool

        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    /// A document in Recently Deleted: a folder of that name inside the
    /// Writey folder, so it syncs like everything else. Documents are
    /// removed for good 30 days after they were deleted.
    struct DeletedItem: Identifiable, Hashable {
        let url: URL
        /// When it arrived in Recently Deleted on this device; nil while
        /// it's still downloading. Undated documents are never purged.
        var deleted: Date?

        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }

        var daysLeft: Int {
            guard let deleted else { return DocumentLibrary.retentionDays }
            let elapsed = Calendar.current.dateComponents([.day], from: deleted, to: .now).day ?? 0
            return max(0, DocumentLibrary.retentionDays - elapsed)
        }
    }

    enum Location: Equatable {
        case resolving
        case iCloud(URL)
        case local(URL)

        var folder: URL? {
            switch self {
            case .resolving: return nil
            case .iCloud(let url), .local(let url): return url
            }
        }
    }

    @Published private(set) var items: [Item] = []
    /// First line of each document, for the list.
    @Published private(set) var previews: [URL: String] = [:]
    @Published private(set) var location: Location = .resolving
    @Published private(set) var hasLoaded = false
    @Published private(set) var deletedItems: [DeletedItem] = []
    @Published var lastError: String?

    nonisolated static let documentExtensions: Set<String> = ["rtf", "md", "markdown", "txt", "text"]
    nonisolated static let recentlyDeletedFolderName = "Recently Deleted"
    nonisolated static let retentionDays = 30
    private static let migrationKey = "MovedLocalDocumentsToICloud"

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var previewDates: [URL: Date] = [:]
    private var purging: Set<URL> = []

    private var recentlyDeletedFolder: URL? {
        location.folder?.appendingPathComponent(Self.recentlyDeletedFolderName, isDirectory: true)
    }

    private static var localFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resolveLocation() }
        })
        resolveLocation()
    }

    // MARK: - Where documents live

    func resolveLocation() {
        Task {
            // Can block while iCloud sets up the container, so off the main thread.
            let cloudFolder = await Task.detached { () -> URL? in
                guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
                let folder = container.appendingPathComponent("Documents", isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                return folder
            }.value

            if let cloudFolder {
                guard location != .iCloud(cloudFolder) else { return }
                location = .iCloud(cloudFolder)
                await moveLocalDocuments(into: cloudFolder)
                startQuery()
            } else {
                stopQuery()
                location = .local(Self.localFolder)
                refresh()
            }
        }
    }

    /// One time: documents made before Writey used iCloud Drive (in On My
    /// iPhone ▸ Writey) move into the iCloud folder so they stay in the list.
    private func moveLocalDocuments(into cloudFolder: URL) async {
        guard !UserDefaults.standard.bool(forKey: Self.migrationKey) else { return }
        let localFiles = Self.documents(in: Self.localFolder).map(\.url)
        var allMoved = true
        for source in localFiles {
            let destination = uniqueURL(in: cloudFolder, name: source.deletingPathExtension().lastPathComponent, extension: source.pathExtension)
            let moved = await Task.detached {
                (try? FileManager.default.setUbiquitous(true, itemAt: source, destinationURL: destination)) != nil
            }.value
            if moved {
                SyncLinkStore.shared.move(from: source, to: destination)
            } else {
                allMoved = false
            }
        }
        if allMoved { UserDefaults.standard.set(true, forKey: Self.migrationKey) }
    }

    // MARK: - Listing

    func refresh() {
        guard case .local(let folder) = location, let bin = recentlyDeletedFolder else { return }
        Task {
            let (found, deleted) = await Task.detached { (Self.documents(in: folder), Self.deletedDocuments(in: bin)) }.value
            apply(found)
            applyDeleted(deleted)
        }
    }

    nonisolated private static func deletedDocuments(in folder: URL) -> [DeletedItem] {
        let keys: [URLResourceKey] = [.attributeModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, isDocument(url) else { return nil }
            return DeletedItem(url: url, deleted: deletionDate(of: url))
        }
    }

    // MARK: Deletion dates

    /// Stamped on a document as it moves to Recently Deleted. "#S" asks
    /// iCloud Drive to sync the attribute, so every device counts the 30
    /// days from the same moment.
    nonisolated private static let deletedAttribute = "com.writey.deleted#S"

    nonisolated private static func markDeleted(_ url: URL) {
        let stamp = String(Date().timeIntervalSince1970)
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = stamp.withCString { setxattr(path, deletedAttribute, $0, strlen($0), 0, 0) }
        }
    }

    nonisolated private static func clearDeletedMark(_ url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = removexattr(path, deletedAttribute, 0)
        }
    }

    /// The stamp, or else the file's status-change time, which moving it
    /// also sets. Either is never earlier than the real deletion, so
    /// nothing is purged early.
    nonisolated private static func deletionDate(of url: URL) -> Date? {
        let stamp: Double? = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            var buffer = [CChar](repeating: 0, count: 64)
            guard getxattr(path, deletedAttribute, &buffer, buffer.count - 1, 0, 0) > 0 else { return nil }
            return Double(String(cString: buffer))
        }
        if let stamp { return Date(timeIntervalSince1970: stamp) }
        return (try? url.resourceValues(forKeys: [.attributeModificationDateKey]))?.attributeModificationDate
    }

    nonisolated private static func documents(in folder: URL) -> [Item] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true, isDocument(url) else { return nil }
            return Item(url: url, modified: values?.contentModificationDate ?? .distantPast, isDownloaded: true)
        }
    }

    nonisolated static func isDocument(_ url: URL) -> Bool {
        documentExtensions.contains(url.pathExtension.lowercased())
    }

    private func startQuery() {
        stopQuery()
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.readQueryResults() }
            })
        }
        self.query = query
        query.start()
    }

    private func stopQuery() {
        query?.stop()
        query = nil
    }

    private func readQueryResults() {
        guard let query, let folder = location.folder else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        let folderPath = folder.resolvingSymlinksInPath().path
        let binPath = folder.appendingPathComponent(Self.recentlyDeletedFolderName).resolvingSymlinksInPath().path
        var found: [Item] = []
        var deleted: [DeletedItem] = []
        for case let result as NSMetadataItem in query.results {
            guard let url = result.value(forAttribute: NSMetadataItemURLKey) as? URL, Self.isDocument(url) else { continue }
            let parentPath = url.deletingLastPathComponent().resolvingSymlinksInPath().path
            guard parentPath == folderPath || parentPath == binPath else { continue }
            let status = result.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let isDownloaded = status == NSMetadataUbiquitousItemDownloadingStatusCurrent
            if !isDownloaded {
                // Documents are small; fetch them all so they open instantly.
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            if parentPath == binPath {
                deleted.append(DeletedItem(url: url, deleted: isDownloaded ? Self.deletionDate(of: url) : nil))
            } else {
                let modified = result.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantPast
                found.append(Item(url: url, modified: modified, isDownloaded: isDownloaded))
            }
        }
        apply(found)
        applyDeleted(deleted)
    }

    private func apply(_ found: [Item]) {
        items = found.sorted { $0.modified > $1.modified }
        hasLoaded = true
        loadPreviews()
    }

    /// Newest first; anything past 30 days is removed for good.
    private func applyDeleted(_ found: [DeletedItem]) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: .now) ?? .distantPast
        let expired = found.filter { ($0.deleted ?? .now) < cutoff }
        deletedItems = found
            .filter { ($0.deleted ?? .now) >= cutoff }
            .sorted { ($0.deleted ?? .now) > ($1.deleted ?? .now) }
        purge(expired.map(\.url))
    }

    /// Quietly, without error alerts: it runs on its own, and another
    /// device may have purged the same file first.
    private func purge(_ urls: [URL]) {
        let urls = urls.filter { !purging.contains($0) }
        guard !urls.isEmpty else { return }
        purging.formUnion(urls)
        Task {
            for url in urls {
                if await Task.detached(operation: { Self.coordinatedDelete(url) }).value == nil {
                    SyncLinkStore.shared.remove(fileURL: url)
                }
                purging.remove(url)
            }
        }
    }

    private func loadPreviews() {
        let stale = items.filter { $0.isDownloaded && previewDates[$0.url] != $0.modified }
        guard !stale.isEmpty else { return }
        for item in stale { previewDates[item.url] = item.modified }
        Task {
            let loaded = await Task.detached {
                stale.map { ($0.url, Self.firstLine(of: $0.url)) }
            }.value
            for (url, line) in loaded { previews[url] = line }
        }
    }

    /// A document that was just closed: show its first line right away,
    /// rather than after the save lands and the file is read back.
    func updatePreview(for url: URL, text: String) {
        previews[url] = Self.firstLine(in: text)
    }

    nonisolated private static func firstLine(of url: URL) -> String {
        var text = ""
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: nil) { readURL in
            guard let data = try? Data(contentsOf: readURL),
                  let type = UTType(filenameExtension: readURL.pathExtension)
            else { return }
            text = (try? WriteyDocument.decode(data, as: type))?.string ?? ""
        }
        return firstLine(in: text)
    }

    /// First non-blank line, without Markdown heading, quote or list marks.
    nonisolated private static func firstLine(in text: String) -> String {
        let line = text
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#>*- \t")) }
            .first { !$0.isEmpty }
        return line.map { String($0.prefix(140)) } ?? ""
    }

    // MARK: - Creating, renaming, deleting

    func createDocument() async -> URL? {
        guard let folder = location.folder else { return nil }
        let url = uniqueURL(in: folder, name: "Untitled", extension: "rtf")
        #if os(iOS)
        let file = WriteyFile(fileURL: url)
        guard await file.save(to: url, for: .forCreating) else {
            lastError = "Couldn't create a new document."
            return nil
        }
        _ = await file.close()
        #else
        // The Mac opens documents through DocumentGroup, so write an empty
        // one directly; the editor window picks it up from there.
        guard let data = try? WriteyDocument.encode(WriteyDocument().attributedText, as: .rtf),
              await Task.detached(operation: { Self.coordinatedCreate(data, at: url) }).value == nil
        else {
            lastError = "Couldn't create a new document."
            return nil
        }
        #endif
        items.insert(Item(url: url, modified: Date(), isDownloaded: true), at: 0)
        previews[url] = ""
        previewDates[url] = items.first?.modified
        return url
    }

    /// Returns the new URL, or nil if the rename didn't happen.
    @discardableResult
    func rename(_ url: URL, to proposedName: String) async -> URL? {
        let name = proposedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let current = url.deletingPathExtension().lastPathComponent
        guard !name.isEmpty, name != current, !name.hasPrefix(".") else { return nil }

        let destination = url.deletingLastPathComponent()
            .appendingPathComponent(name)
            .appendingPathExtension(url.pathExtension)
        if nameIsTaken(destination) {
            lastError = "There's already a document called “\(name)”."
            return nil
        }

        let error = await Task.detached { Self.coordinatedMove(from: url, to: destination) }.value
        if let error {
            lastError = "Couldn't rename “\(current)”: \(error.localizedDescription)"
            return nil
        }
        SyncLinkStore.shared.move(from: url, to: destination)
        if let index = items.firstIndex(where: { $0.url == url }) {
            items[index] = Item(url: destination, modified: items[index].modified, isDownloaded: items[index].isDownloaded)
        }
        previews[destination] = previews.removeValue(forKey: url)
        previewDates[destination] = previewDates.removeValue(forKey: url)
        refresh()
        return destination
    }

    /// Deleting moves the document to Recently Deleted, where it stays for
    /// 30 days. Its Google Docs link moves with it, so a restore keeps it.
    func moveToRecentlyDeleted(_ url: URL) async {
        guard let bin = recentlyDeletedFolder else { return }
        let (destination, error) = await Task.detached { () -> (URL, Error?) in
            try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let destination = Self.availableURL(in: bin, for: url)
            let error = Self.coordinatedMove(from: url, to: destination)
            if error == nil { Self.markDeleted(destination) }
            return (destination, error)
        }.value
        if let error {
            lastError = "Couldn't delete “\(url.deletingPathExtension().lastPathComponent)”: \(error.localizedDescription)"
            return
        }
        SyncLinkStore.shared.move(from: url, to: destination)
        items.removeAll { $0.url == url }
        previews[url] = nil
        previewDates[url] = nil
        deletedItems.insert(DeletedItem(url: destination, deleted: .now), at: 0)
    }

    /// Puts a deleted document back in the Writey folder, renamed if its
    /// name has been taken since.
    @discardableResult
    func restore(_ item: DeletedItem) async -> URL? {
        guard let folder = location.folder else { return nil }
        let destination = uniqueURL(in: folder, name: item.name, extension: item.url.pathExtension)
        let error = await Task.detached { () -> Error? in
            let error = Self.coordinatedMove(from: item.url, to: destination)
            if error == nil { Self.clearDeletedMark(destination) }
            return error
        }.value
        if let error {
            lastError = "Couldn't restore “\(item.name)”: \(error.localizedDescription)"
            return nil
        }
        SyncLinkStore.shared.move(from: item.url, to: destination)
        deletedItems.removeAll { $0.url == item.url }
        let modified = (try? destination.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
        items.append(Item(url: destination, modified: modified, isDownloaded: true))
        items.sort { $0.modified > $1.modified }
        loadPreviews()
        return destination
    }

    func deletePermanently(_ item: DeletedItem) async {
        let error = await Task.detached { Self.coordinatedDelete(item.url) }.value
        if let error {
            lastError = "Couldn't delete “\(item.name)”: \(error.localizedDescription)"
            return
        }
        SyncLinkStore.shared.remove(fileURL: item.url)
        deletedItems.removeAll { $0.url == item.url }
    }

    func emptyRecentlyDeleted() async {
        for item in deletedItems {
            await deletePermanently(item)
        }
    }

    /// "Notes.rtf", then "Notes 2.rtf"… among files already in `folder`.
    nonisolated private static func availableURL(in folder: URL, for url: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }

    nonisolated private static func coordinatedMove(from source: URL, to destination: URL) -> Error? {
        var failure: Error?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: destination, options: .forReplacing,
            error: &coordinationError
        ) { from, to in
            do {
                coordinator.item(at: from, willMoveTo: to)
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch {
                failure = error
            }
        }
        return coordinationError ?? failure
    }

    nonisolated private static func coordinatedCreate(_ data: Data, at url: URL) -> Error? {
        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                try data.write(to: target, options: .withoutOverwriting)
            } catch {
                failure = error
            }
        }
        return coordinationError ?? failure
    }

    nonisolated private static func coordinatedDelete(_ url: URL) -> Error? {
        var failure: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            do {
                try FileManager.default.removeItem(at: target)
            } catch {
                failure = error
            }
        }
        return coordinationError ?? failure
    }

    // MARK: - Names

    private func nameIsTaken(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return items.contains { $0.url.lastPathComponent.lowercased() == name }
            || FileManager.default.fileExists(atPath: url.path)
    }

    /// "Untitled", then "Untitled 2", "Untitled 3"…
    private func uniqueURL(in folder: URL, name: String, extension ext: String) -> URL {
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var number = 2
        while nameIsTaken(candidate) {
            candidate = folder.appendingPathComponent("\(name) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }
}

extension DocumentLibrary.Location {
    var isICloud: Bool {
        if case .iCloud = self { return true }
        return false
    }
}
