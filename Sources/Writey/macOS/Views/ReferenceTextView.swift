import SwiftUI
import AppKit

/// A reference document, read-only: selectable, so text can be copied or
/// dragged into the writing, and shown in the reader's typography and theme.
struct ReferenceTextView: NSViewRepresentable {
    let text: NSAttributedString
    let typography: Typography
    /// ⌘-click or right-click on a web link: open it in the pane.
    var onOpenLink: (URL) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        if let textView = scrollView.documentView as? NSTextView {
            textView.delegate = context.coordinator
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 24, height: 24)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onOpenLink = onOpenLink
        let scheme = context.environment.colorScheme
        let shown = Coordinator.Shown(text: text, typography: typography, scheme: scheme)
        guard context.coordinator.shown != shown else { return }
        context.coordinator.shown = shown
        let color = EditorPalette.text(scheme)
        textView.textStorage?.setAttributedString(typography.displayed(text, color: color))
        textView.selectedTextAttributes = [
            .backgroundColor: EditorPalette.selection(scheme),
            .foregroundColor: color
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        /// What's on screen, so SwiftUI updates don't re-lay out the text.
        struct Shown: Equatable {
            let text: NSAttributedString
            let typography: Typography
            let scheme: ColorScheme

            static func == (a: Shown, b: Shown) -> Bool {
                a.text === b.text && a.typography == b.typography && a.scheme == b.scheme
            }
        }
        var shown: Shown?
        var onOpenLink: (URL) -> Void = { _ in }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            ReferenceLinks.click(link, open: onOpenLink)
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            ReferenceLinks.menu(menu, for: view, at: charIndex, open: onOpenLink)
        }
    }
}
