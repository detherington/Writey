import SwiftUI
import AppKit

/// Format menu items that route through the first-responder NSTextView via
/// the standard responder chain. We use AppKit selectors so they work even
/// without an EditorController in scope (e.g. when invoked from the menu
/// bar of an unfocused window).
struct FormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            Button("Bold") {
                NSApp.sendAction(#selector(NSFontManagerActionInvoker.toggleBoldFromMenu(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("Italic") {
                NSApp.sendAction(#selector(NSFontManagerActionInvoker.toggleItalicFromMenu(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Underline") {
                NSApp.sendAction(#selector(NSText.underline(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("u", modifiers: .command)
        }
    }
}

/// AppKit selectors aren't visible from SwiftUI without a host object, so
/// we declare a thin protocol whose methods NSFontManager already implements.
@objc protocol NSFontManagerActionInvoker {
    @objc func toggleBoldFromMenu(_ sender: Any?)
    @objc func toggleItalicFromMenu(_ sender: Any?)
}

extension NSFontManager: NSFontManagerActionInvoker {
    @objc func toggleBoldFromMenu(_ sender: Any?) {
        let tagged = NSMenuItem()
        tagged.tag = 2 // NSBoldFontMask
        addFontTrait(tagged)
    }

    @objc func toggleItalicFromMenu(_ sender: Any?) {
        let tagged = NSMenuItem()
        tagged.tag = 1 // NSItalicFontMask
        addFontTrait(tagged)
    }
}

struct SyncCommands: Commands {
    var body: some Commands {
        CommandMenu("Sync") {
            Button("Sync with Google Docs…") {
                NotificationCenter.default.post(name: .writeyShowSyncSheet, object: nil)
            }
            .keyboardShortcut("y", modifiers: [.command, .shift])
        }
    }
}

/// "Check for Updates…" lives in the standard Apple-menu / appInfo group,
/// just below "About Writey", matching the convention every native macOS
/// app follows.
struct UpdateCommands: Commands {
    @ObservedObject var updater: UpdaterService

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
    }
}

/// View menu — distraction-free mode toggle.
///
/// The menu command broadcasts a notification rather than mutating a
/// single shared state, so each document window can track its own
/// distraction-free state. The window that's currently key responds.
///
/// Shortcut is ⇧⌘D rather than ⌃⌘D because macOS reserves ⌃⌘D
/// system-wide for "Look Up & Data Detectors" (the dictionary popover),
/// which swallows the keystroke before any text-editing app can see it.
struct ViewCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Distraction-Free Mode") {
                NotificationCenter.default.post(name: .writeyToggleDistractionFree, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.shift, .command])
        }
    }
}

extension Notification.Name {
    static let writeyShowSyncSheet         = Notification.Name("writey.showSyncSheet")
    static let writeyToggleDistractionFree = Notification.Name("writey.toggleDistractionFree")
}
