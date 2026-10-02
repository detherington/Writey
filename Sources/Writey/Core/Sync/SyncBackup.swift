import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Saves the local text before a sync overwrites it, so every pull and every
/// "Keep Google" choice is recoverable.
///
/// Mac: added as a version of the document itself, so it shows up under
/// File ▸ Revert To ▸ Browse All Versions. iOS (and the Mac fallback): a
/// timestamped file in a "Sync Backups" folder — on iOS that folder lives in
/// Writey's Documents directory, which Files shows under On My iPad ▸ Writey.
enum SyncBackup {
    private static let keepPerDocument = 20

    /// Returns a short description of where the backup went, for the status
    /// line, or nil if it couldn't be saved.
    static func save(_ text: NSAttributedString, for fileURL: URL) -> String? {
        let canonical = text.writeyCanonicalForm()
        guard let data = try? canonical.data(
            from: NSRange(location: 0, length: canonical.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else { return nil }

        #if os(macOS)
        if fileURL.pathExtension.lowercased() == "rtf", addFileVersion(data, to: fileURL) {
            return "File ▸ Revert To"
        }
        #endif
        return writeBackupFile(data, for: fileURL) ? "Sync Backups folder" : nil
    }

    #if os(macOS)
    private static func addFileVersion(_ data: Data, to fileURL: URL) -> Bool {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("rtf")
        defer { try? FileManager.default.removeItem(at: tmp) }
        do {
            try data.write(to: tmp)
            _ = try NSFileVersion.addOfItem(at: fileURL, withContentsOf: tmp, options: [])
            return true
        } catch {
            return false
        }
    }
    #endif

    private static var backupDirectory: URL? {
        let fm = FileManager.default
        #if os(iOS)
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        #else
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Writey", isDirectory: true)
        #endif
        guard let dir = base?.appendingPathComponent("Sync Backups", isDirectory: true) else { return nil }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func writeBackupFile(_ data: Data, for fileURL: URL) -> Bool {
        guard let dir = backupDirectory else { return false }
        let prefix = "\(fileURL.deletingPathExtension().lastPathComponent) — before sync "
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = dir.appendingPathComponent(prefix + formatter.string(from: Date())).appendingPathExtension("rtf")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }

        // Timestamps sort lexically, so the newest are last.
        let existing = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let mine = existing
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in mine.dropFirst(keepPerDocument) {
            try? FileManager.default.removeItem(at: old)
        }
        return true
    }
}
