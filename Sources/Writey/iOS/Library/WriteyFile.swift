import UIKit
import UniformTypeIdentifiers

/// One open document on iOS.
///
/// `UIDocument` does the file work SwiftUI's DocumentGroup used to:
/// coordinated reads and writes (which download iCloud files on demand),
/// autosave, saving when the app goes to the background, and reloading when
/// the file changes on another device. The text itself lives in a
/// `WriteyDocument`, the same model the Mac uses.
final class WriteyFile: UIDocument, ObservableObject {
    let model = WriteyDocument()

    /// Bumped whenever the text is (re)loaded from disk — on open, and when
    /// another device changes the file — so the editor knows to reload.
    @Published private(set) var revision = 0
    @Published private(set) var saveError: String?

    override init(fileURL url: URL) {
        super.init(fileURL: url)
        NotificationCenter.default.addObserver(
            self, selector: #selector(documentStateChanged),
            name: UIDocument.stateChangedNotification, object: self
        )
    }

    var name: String { fileURL.deletingPathExtension().lastPathComponent }

    private var contentType: UTType {
        UTType(filenameExtension: fileURL.pathExtension) ?? .rtf
    }

    // MARK: - Reading and writing

    override func contents(forType typeName: String) throws -> Any {
        try WriteyDocument.encode(model.attributedText, as: contentType)
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data else { throw CocoaError(.fileReadCorruptFile) }
        model.attributedText = try WriteyDocument.decode(data, as: contentType)
        revision += 1
    }

    override func handleError(_ error: Error, userInteractionPermitted: Bool) {
        saveError = "Couldn't save: \(error.localizedDescription)"
        finishedHandlingError(error, recovered: false)
    }

    override func save(
        to url: URL,
        for saveOperation: UIDocument.SaveOperation,
        completionHandler: ((Bool) -> Void)? = nil
    ) {
        super.save(to: url, for: saveOperation) { [weak self] saved in
            if saved { self?.saveError = nil }
            completionHandler?(saved)
        }
    }

    /// Renames done through `DocumentLibrary` reach the open document here.
    override func presentedItemDidMove(to newURL: URL) {
        super.presentedItemDidMove(to: newURL)
        Task { @MainActor [weak self] in self?.objectWillChange.send() }
    }

    // MARK: - iCloud conflicts

    /// Edited on two devices before iCloud caught up: keep whichever version
    /// was saved last, and copy the others to Sync Backups so nothing is lost.
    @objc private func documentStateChanged() {
        guard documentState.contains(.inConflict),
              let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL),
              let current = NSFileVersion.currentVersionOfItem(at: fileURL)
        else { return }

        let all = [current] + conflicts
        let newest = all.max { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) } ?? current
        for version in all where version != newest {
            if let data = try? Data(contentsOf: version.url),
               let text = try? WriteyDocument.decode(data, as: contentType) {
                _ = SyncBackup.save(text, for: fileURL)
            }
        }
        if newest != current {
            _ = try? newest.replaceItem(at: fileURL)
        }
        conflicts.forEach { $0.isResolved = true }
        try? NSFileVersion.removeOtherVersionsOfItem(at: fileURL)
        if newest != current {
            revert(toContentsOf: fileURL)
        }
    }
}
