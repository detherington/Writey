import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// One editor window's reference pane: what it shows, on which side, how
/// wide, and whether it's open. Remembered per document in `ReferenceStore`.
///
/// Reference documents are read straight from disk — never opened as a
/// document — so they can't be edited or saved by accident, and a watcher
/// keeps them current when they change on another device.
@MainActor
final class ReferenceController: ObservableObject {
    enum DocumentState: Equatable {
        case loading
        case loaded(NSAttributedString)
        /// A file reference, downloaded and ready to preview. The version
        /// changes when the file does, so the preview reloads.
        case file(URL, version: Int)
        case unavailable(String)
    }

    @Published private(set) var source: ReferenceSource?
    @Published var isVisible: Bool { didSet { remember() } }
    @Published private(set) var side: ReferenceSide
    /// The pane's share of the window's width; saved when a drag ends.
    @Published var fraction: Double
    @Published private(set) var documentState: DocumentState = .loading
    /// Shows the address field even before a page is open.
    @Published var isEnteringAddress = false
    /// Why the web page couldn't open (offline, say), shown in place of a
    /// blank page.
    @Published private(set) var pageError: String?
    /// The web page, once one has been opened; kept while the pane stays,
    /// so going back and forth between sources doesn't lose its history.
    private(set) var page: WebPage?

    private(set) var fileURL: URL?
    private var watcher: ReferenceFileWatcher?
    private var loading: Task<Void, Never>?
    private var fileVersion = 0

    static let minimumFraction = 0.2
    static let maximumFraction = 0.7

    init(fileURL: URL?, defaultSide: ReferenceSide) {
        self.fileURL = fileURL
        let memory = fileURL.flatMap { ReferenceStore.shared.memory(for: $0) }
        side = memory?.side ?? defaultSide
        fraction = memory?.fraction ?? ReferenceMemory.defaultFraction
        isVisible = memory?.isVisible ?? false
        if let source = memory?.source { show(source) }
    }

    // MARK: - What's shown

    func open(_ source: ReferenceSource) {
        if case .document(let url) = source, let fileURL, Self.samePath(url, fileURL) {
            documentState = .unavailable("This is the document you're writing.")
        }
        show(source)
        isEnteringAddress = false
        isVisible = true
        ReferenceStore.shared.noteRecent(source)
        remember()
    }

    /// An address or a search, as typed into the address field.
    func openAddress(_ input: String) {
        guard let url = Self.webURL(from: input) else { return }
        open(.web(url))
    }

    /// Tries the page again after it failed to open.
    func retryPage() {
        guard case .web(let url) = source, let page else { return }
        load(url, in: page)
    }

    /// What the address field shows: the page's address, or the one it's
    /// trying to open.
    var webAddress: String {
        if let url = page?.url { return url.absoluteString }
        if case .web(let url) = source { return url.absoluteString }
        return ""
    }

    func close() {
        source = nil
        watcher?.stop()
        watcher = nil
        loading?.cancel()
        pageError = nil
        page = nil
        isEnteringAddress = false
        isVisible = false
        remember()
    }

    func toggleVisible() { isVisible.toggle() }

    func swapSides() {
        side = side.opposite
        remember()
    }

    func commitFraction() {
        fraction = min(max(fraction, Self.minimumFraction), Self.maximumFraction)
        remember()
    }

    /// The page navigated: remember where it is now.
    func pageDidNavigate() {
        guard let url = page?.url else { return }
        pageError = nil
        guard case .web(let current) = source, url != current else { return }
        source = .web(url)
        remember()
    }

    /// The document being written was renamed or saved somewhere new (Mac).
    func documentMoved(to newURL: URL?) {
        if let old = fileURL, let newURL, !Self.samePath(old, newURL) {
            ReferenceStore.shared.move(from: old, to: newURL)
        }
        fileURL = newURL
        remember()
    }

    /// Before opening the reference for editing: the document being written
    /// becomes its reference, so the two simply swap places.
    func prepareSwap(to referenceURL: URL) {
        guard let fileURL else { return }
        ReferenceStore.shared.setMemory(
            ReferenceMemory(source: .document(fileURL), side: side, fraction: fraction, isVisible: true),
            for: referenceURL
        )
    }

    private func show(_ source: ReferenceSource) {
        self.source = source
        watcher?.stop()
        watcher = nil
        switch source {
        case .document(let url):
            if let fileURL, Self.samePath(url, fileURL) { return }
            loadDocument(url)
            watch(url)
        case .file(let url):
            loadFile(url)
            watch(url)
        case .web(let url):
            let page = page ?? Self.makePage()
            self.page = page
            if page.url != url { load(url, in: page) }
        }
    }

    private func load(_ url: URL, in page: WebPage) {
        pageError = nil
        loading?.cancel()
        let events = page.load(URLRequest(url: url))
        loading = Task { [weak self] in
            do {
                for try await _ in events {}
            } catch {
                guard !Task.isCancelled, let message = Self.message(for: error) else { return }
                self?.pageError = message
            }
        }
    }

    /// A failure worth showing; nil when the load was only interrupted,
    /// by a click on a link or a newer address.
    private static func message(for error: any Error) -> String? {
        guard let navigation = error as? WebPage.NavigationError else { return error.localizedDescription }
        switch navigation {
        case .failedProvisionalNavigation(let underlying):
            if (underlying as? URLError)?.code == .cancelled { return nil }
            return underlying.localizedDescription
        case .webContentProcessTerminated:
            return "The page stopped working."
        case .invalidURL:
            return "That isn't a web address Writey can open."
        case .pageClosed:
            return nil
        @unknown default:
            return error.localizedDescription
        }
    }

    /// iPadOS asks for desktop sites by default, which lay out wider than
    /// the pane and get cut off. A reference pane is phone-sized, so ask
    /// for the mobile layout there.
    private static func makePage() -> WebPage {
        var configuration = WebPage.Configuration()
        #if os(iOS)
        configuration.defaultNavigationPreferences.preferredContentMode = .mobile
        #endif
        return WebPage(configuration: configuration)
    }

    private func remember() {
        guard let fileURL else { return }
        ReferenceStore.shared.setMemory(
            ReferenceMemory(source: source, side: side, fraction: fraction, isVisible: isVisible),
            for: fileURL
        )
    }

    // MARK: - Reference documents and files

    private func loadDocument(_ url: URL) {
        if case .loaded = documentState {} else { documentState = .loading }
        Task {
            let state = await Task.detached { Self.read(url) }.value
            guard source == .document(url) else { return }
            documentState = state
        }
    }

    private func loadFile(_ url: URL) {
        if case .file = documentState {} else { documentState = .loading }
        Task {
            let isThere = await Task.detached { Self.download(url) }.value
            guard source == .file(url) else { return }
            fileVersion += 1
            documentState = isThere
                ? .file(url, version: fileVersion)
                : .unavailable("This file has been moved or deleted.")
        }
    }

    private func watch(_ url: URL) {
        watcher = ReferenceFileWatcher(url: url) { [weak self] event in
            MainActor.assumeIsolated { self?.fileChanged(event) }
        }
    }

    private func fileChanged(_ event: ReferenceFileWatcher.Event) {
        switch (source, event) {
        case (.document(let url)?, .changed):
            loadDocument(url)
        case (.file(let url)?, .changed):
            loadFile(url)
        case (.document?, .moved(let newURL)):
            source = .document(newURL)
            watcher?.url = newURL
            remember()
        case (.file?, .moved(let newURL)):
            source = .file(newURL)
            watcher?.url = newURL
            loadFile(newURL)
            remember()
        case (.document?, .deleted):
            documentState = .unavailable("This document has been deleted.")
        case (.file?, .deleted):
            documentState = .unavailable("This file has been deleted.")
        default:
            break
        }
    }

    /// Coordinated, so a file in iCloud Drive is downloaded before it's
    /// previewed. False if it isn't there.
    nonisolated private static func download(_ url: URL) -> Bool {
        var isThere = false
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { readURL in
            isThere = FileManager.default.fileExists(atPath: readURL.path)
        }
        return isThere
    }

    /// Coordinated, so an iCloud document is downloaded first and a save in
    /// progress elsewhere finishes before it's read.
    nonisolated private static func read(_ url: URL) -> DocumentState {
        var result = DocumentState.unavailable("This document has been moved or deleted.")
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { readURL in
            guard let data = try? Data(contentsOf: readURL) else { return }
            let type = UTType(filenameExtension: readURL.pathExtension) ?? .rtf
            if let text = try? WriteyDocument.decode(data, as: type) {
                result = .loaded(text)
            } else {
                result = .unavailable("Writey can't show this kind of document.")
            }
        }
        return result
    }

    var isInRecentlyDeleted: Bool {
        guard case .document(let url) = source else { return false }
        return url.deletingLastPathComponent().lastPathComponent == DocumentLibrary.recentlyDeletedFolderName
    }

    // MARK: - Helpers

    static func samePath(_ a: URL, _ b: URL) -> Bool {
        StableFilePath.string(for: a) == StableFilePath.string(for: b)
    }

    /// A link in the text, if it's a web address the pane can open.
    nonisolated static func webLink(_ value: Any?) -> URL? {
        let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }

    /// A web address as typed: with or without "https://", or else words
    /// to search for.
    static func webURL(from input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host() != nil {
            return url
        }
        if !text.contains(" "), text.contains("."), let url = URL(string: "https://" + text), url.host() != nil {
            return url
        }
        var search = URLComponents(string: "https://www.google.com/search")
        search?.queryItems = [URLQueryItem(name: "q", value: text)]
        return search?.url
    }

    /// Sign out of every website the reference pane has visited.
    static func clearWebsiteData() async {
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
    }
}

/// Tells the reference pane when its document changes, moves or goes away.
final class ReferenceFileWatcher: NSObject, NSFilePresenter {
    enum Event {
        case changed
        case moved(URL)
        case deleted
    }

    var url: URL
    private let onEvent: (Event) -> Void

    var presentedItemURL: URL? { url }
    let presentedItemOperationQueue = OperationQueue.main

    init(url: URL, onEvent: @escaping (Event) -> Void) {
        self.url = url
        self.onEvent = onEvent
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() {
        NSFileCoordinator.removeFilePresenter(self)
    }

    func presentedItemDidChange() { onEvent(.changed) }

    func presentedItemDidMove(to newURL: URL) {
        url = newURL
        onEvent(.moved(newURL))
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        onEvent(.deleted)
        completionHandler(nil)
    }
}
