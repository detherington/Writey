import AppKit

/// The reference pane of the document window most recently in front, so
/// the library can open a document as its reference.
@MainActor
final class FrontmostReference {
    static let shared = FrontmostReference()

    private weak var controller: ReferenceController?
    private weak var window: NSWindow?

    /// A document window came to the front.
    func update(_ controller: ReferenceController, in window: NSWindow) {
        self.controller = controller
        self.window = window
    }

    /// The name of the document a reference would open beside, unless it's
    /// `url` itself.
    func documentName(excluding url: URL) -> String? {
        guard let fileURL = controller?.fileURL, window?.isVisible == true,
              !ReferenceController.samePath(fileURL, url) else { return nil }
        return fileURL.deletingPathExtension().lastPathComponent
    }

    func open(_ url: URL) {
        controller?.open(.document(url))
        window?.makeKeyAndOrderFront(nil)
    }
}
