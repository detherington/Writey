import AppKit

/// macOS implementation of `SyncConflictResolver` — pops a synchronous
/// NSAlert. The iOS target will ship its own UIAlertController-based
/// implementation alongside its app delegate.
final class MacConflictResolver: SyncConflictResolver {
    @MainActor
    func resolveSyncConflict() -> SyncConflictChoice {
        let alert = NSAlert()
        alert.messageText = "Both versions have changed"
        alert.informativeText = "The local document and the Google Doc have both been edited since your last sync. Which copy should win?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Local (push)")
        alert.addButton(withTitle: "Keep Google (pull)")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .keepLocal
        case .alertSecondButtonReturn: return .keepRemote
        default:                       return .cancel
        }
    }
}
