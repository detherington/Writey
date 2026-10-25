import SwiftUI
import UIKit

/// A reference document, read-only: selectable, so text can be copied or
/// dragged into the writing, and shown in the reader's typography and theme.
struct ReferenceTextView: UIViewRepresentable {
    let text: NSAttributedString
    let typography: Typography

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let scheme = context.environment.colorScheme
        let shown = Coordinator.Shown(text: text, typography: typography, scheme: scheme)
        guard context.coordinator.shown != shown else { return }
        context.coordinator.shown = shown
        let color = EditorPalette.text(scheme)
        textView.attributedText = typography.displayed(text, color: color)
        textView.tintColor = color
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
