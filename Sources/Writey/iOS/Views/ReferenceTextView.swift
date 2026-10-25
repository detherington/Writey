import SwiftUI
import UIKit

/// A reference document, read-only: selectable, so text can be copied or
/// dragged into the writing, and shown in the reader's typography and theme.
struct ReferenceTextView: UIViewRepresentable {
    let text: NSAttributedString
    let typography: Typography
    /// Open as Reference, in a web link's long-press menu.
    var onOpenLink: (URL) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onOpenLink = onOpenLink
        let scheme = context.environment.colorScheme
        let shown = Coordinator.Shown(text: text, typography: typography, scheme: scheme)
        guard context.coordinator.shown != shown else { return }
        context.coordinator.shown = shown
        let color = EditorPalette.text(scheme)
        textView.attributedText = typography.displayed(text, color: color)
        textView.tintColor = color
    }

    final class Coordinator: NSObject, UITextViewDelegate {
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

        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            ReferenceLinkMenu.configuration(for: textItem, defaultMenu: defaultMenu) { [weak self] in self?.onOpenLink($0) }
        }
    }
}

/// Open as Reference at the top of a web link's long-press menu, in the
/// writing and in reference documents.
enum ReferenceLinkMenu {
    static func configuration(
        for textItem: UITextItem, defaultMenu: UIMenu, open: @escaping (URL) -> Void
    ) -> UITextItem.MenuConfiguration {
        guard case .link(let link) = textItem.content, let url = ReferenceController.webLink(link) else {
            return UITextItem.MenuConfiguration(menu: defaultMenu)
        }
        let first = UIMenu(options: .displayInline, children: [action(open: { open(url) })])
        return UITextItem.MenuConfiguration(menu: defaultMenu.replacingChildren([first] + defaultMenu.children))
    }

    static func action(open: @escaping () -> Void) -> UIAction {
        UIAction(title: "Open as Reference", image: UIImage(systemName: "text.book.closed")) { _ in open() }
    }
}
