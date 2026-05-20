import SwiftUI
import UIKit

/// SwiftUI wrapper around `UITextView` — the iOS analogue of the macOS
/// `NSTextView` editor. Same job: rich-text editing (bold/italic/underline/
/// headings/lists) inside a SwiftUI scene.
struct RichTextEditor: UIViewRepresentable {
    @Binding var text: NSAttributedString
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var editor: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = true
        textView.autocorrectionType = .default
        textView.smartQuotesType = .yes
        textView.smartDashesType = .yes
        textView.smartInsertDeleteType = .yes
        textView.spellCheckingType = .yes
        textView.dataDetectorTypes = [.link]
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        textView.font = UIFont.systemFont(ofSize: 16)

        if text.length > 0 {
            textView.attributedText = text
        } else {
            textView.typingAttributes = WriteyDocument.defaultBodyAttributes()
        }

        applyTheme(to: textView)

        DispatchQueue.main.async {
            editor.textView = textView
            editor.refreshState()
        }

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if !context.coordinator.isApplyingLocalEdit && !textView.attributedText.isEqual(to: text) {
            let selection = textView.selectedRange
            textView.attributedText = text
            textView.selectedRange = selection
        }
        applyTheme(to: textView)
    }

    private func applyTheme(to textView: UITextView) {
        textView.textColor = theme.editorTextUIColor
        textView.tintColor = theme.editorTextUIColor
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        var isApplyingLocalEdit = false

        init(_ parent: RichTextEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            isApplyingLocalEdit = true
            parent.text = textView.attributedText
            DispatchQueue.main.async { [weak self] in
                self?.isApplyingLocalEdit = false
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.editor.refreshState()
            }
        }
    }
}
