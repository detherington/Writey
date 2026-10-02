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

/// Platform UI for the "both sides changed" sync prompt (NSAlert on Mac,
/// UIAlertController on iOS), so `SyncManager` can stay in Core.
@MainActor
public protocol SyncConflictResolver: AnyObject {
    func resolveSyncConflict() async -> SyncConflictChoice
}

public enum SyncConflictChoice {
    case keepLocal
    case keepRemote
    case cancel
}

/// Lets sync replace a document's text through the editor rather than by
/// assigning to the model. Going through the text view registers the change
/// with the document's undo manager, which is what makes SwiftUI treat the
/// document as edited and autosave it — and makes a pull undoable.
@MainActor
protocol DocumentTextEditing: AnyObject {
    func replaceAllText(with text: NSAttributedString, actionName: String)
}
