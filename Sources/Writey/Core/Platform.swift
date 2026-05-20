import Foundation

#if canImport(AppKit)
import AppKit
public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
#endif

/// Mediates UI behaviors that are inherently platform-specific from the
/// Core sync layer.
///
/// `SyncManager` lives in Core (so the iOS app can reuse it without a
/// rewrite), but it occasionally needs to ask the user a question — "both
/// sides changed, which do you want to keep?". The Core layer doesn't
/// know how to put up an alert (AppKit's `NSAlert` vs UIKit's
/// `UIAlertController`), so it delegates through this protocol. Each
/// platform target provides its own implementation.
public protocol SyncConflictResolver: AnyObject {
    /// Asks the user how to resolve a local-and-remote-both-changed sync.
    /// Must be called from the main actor; implementations show their
    /// platform's standard alert UI.
    @MainActor
    func resolveSyncConflict() -> SyncConflictChoice
}

public enum SyncConflictChoice {
    case keepLocal
    case keepRemote
    case cancel
}
