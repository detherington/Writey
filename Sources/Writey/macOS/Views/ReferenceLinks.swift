import AppKit

/// Web links in the writing or a reference document open in the reference
/// pane with ⌘-click, or from the right-click menu. A plain click still
/// opens the browser.
enum ReferenceLinks {
    /// For `textView(_:clickedOnLink:at:)`: true when the link went to the pane.
    @MainActor
    static func click(_ link: Any, open: (URL) -> Void) -> Bool {
        guard NSApp.currentEvent?.modifierFlags.contains(.command) == true,
              let url = ReferenceController.webLink(link) else { return false }
        open(url)
        return true
    }

    /// For `textView(_:menu:for:at:)`: Open Link as Reference at the top
    /// when the click is on a web link.
    @MainActor
    static func menu(_ menu: NSMenu, for textView: NSTextView, at index: Int, open: @escaping (URL) -> Void) -> NSMenu {
        guard let storage = textView.textStorage, index < storage.length,
              let url = ReferenceController.webLink(storage.attribute(.link, at: index, effectiveRange: nil))
        else { return menu }
        menu.insertItem(ActionMenuItem(title: "Open Link as Reference") { open(url) }, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }
}

/// A menu item that runs a closure.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func run() { handler() }
}
