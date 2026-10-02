import Foundation
import UniformTypeIdentifiers

/// The documents in Writey's folder: iCloud Drive ▸ Writey, or — when iCloud
/// Drive is off — On My iPhone ▸ Writey.
///
/// In iCloud an `NSMetadataQuery` keeps the list live, including documents
/// that exist in iCloud but aren't downloaded yet, and edits made on the
/// Mac. File operations are coordinated, so an open document follows a
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
    @Published var lastError: String?

    nonisolated static let documentExtensions: Set<String> = ["rtf", "md", "markdown", "txt", "text"]
    private static let migrationKey = "MovedLocalDocumentsToICloud"

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var previewDates: [URL: Date] = [:]

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
        guard case .local(let folder) = location else { return }
        Task {
            let found = await Task.detached { Self.documents(in: folder) }.value
            apply(found)
        }
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
        var found: [Item] = []
        for case let result as NSMetadataItem in query.results {
            guard let url = result.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  Self.isDocument(url),
                  url.deletingLastPathComponent().resolvingSymlinksInPath().path == folderPath
            else { continue }
            let status = result.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let isDownloaded = status == NSMetadataUbiquitousItemDownloadingStatusCurrent
            if !isDownloaded {
                // Documents are small; fetch them all so they open instantly.
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            let modified = result.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date ?? .distantPast
            found.append(Item(url: url, modified: modified, isDownloaded: isDownloaded))
        }
        apply(found)
    }

    private func apply(_ found: [Item]) {
        items = found.sorted { $0.modified > $1.modified }
        hasLoaded = true
        loadPreviews()
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
        let file = WriteyFile(fileURL: url)
        guard await file.save(to: url, for: .forCreating) else {
            lastError = "Couldn't create a new document."
            return nil
        }
        _ = await file.close()
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

    func delete(_ url: URL) async {
        let error = await Task.detached { Self.coordinatedDelete(url) }.value
        if let error {
            lastError = "Couldn't delete “\(url.deletingPathExtension().lastPathComponent)”: \(error.localizedDescription)"
            return
        }
        SyncLinkStore.shared.remove(fileURL: url)
        items.removeAll { $0.url == url }
        previews[url] = nil
        previewDates[url] = nil
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
