import Foundation

/// Notification names used to route commands from the platform's menu /
/// keyboard-shortcut layer down to the active document scene. Lives in
/// Core so both targets reference the same constants.
public extension Notification.Name {
    static let writeyShowSyncSheet         = Notification.Name("writey.showSyncSheet")
    static let writeyToggleDistractionFree = Notification.Name("writey.toggleDistractionFree")
}
