import SwiftUI
import AppKit

/// A reference document, read-only: selectable, so text can be copied or
/// dragged into the writing, and shown in the reader's typography and theme.
struct ReferenceTextView: NSViewRepresentable {
    let text: NSAttributedString
    let typography: Typography

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        if let textView = scrollView.documentView as? NSTextView {
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

    final class Coordinator {
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
    }
}
