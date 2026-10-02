import AppKit

/// Asks "which copy wins?" as a sheet on the frontmost window.
final class MacConflictResolver: SyncConflictResolver {
    @MainActor
    func resolveSyncConflict() async -> SyncConflictChoice {
        let alert = NSAlert()
        alert.messageText = "Both versions have changed"
        alert.informativeText = "This document and its Google Doc have both been edited since your last sync. Which copy should win? Writey saves your copy before replacing it, and Google Docs keeps its own version history."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Mine (push)")
        alert.addButton(withTitle: "Keep Google's (pull)")
        alert.addButton(withTitle: "Cancel")

        guard let window = NSApp.keyWindow else {
            return Self.choice(for: alert.runModal())
        }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: Self.choice(for: response))
            }
        }
    }

    private static func choice(for response: NSApplication.ModalResponse) -> SyncConflictChoice {
        switch response {
        case .alertFirstButtonReturn:  return .keepLocal
        case .alertSecondButtonReturn: return .keepRemote
        default:                       return .cancel
        }
    }
}
