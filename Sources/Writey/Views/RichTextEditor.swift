import SwiftUI
import AppKit
import Combine

/// SwiftUI wrapper around `NSTextView` to give us light rich-text editing
/// (bold, italic, underline, headings, lists) inside a SwiftUI scene.
///
/// We let NSTextView own the source of truth while editing, then push
/// snapshots back to the bound `NSAttributedString` so the document model
/// stays in sync and the system can autosave.
struct RichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var editor: EditorController
    @Environment(\.undoManager) private var swiftUIUndoManager

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.usesInspectorBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        textView.textContainerInset = NSSize(width: 32, height: 32)
        textView.font = NSFont.systemFont(ofSize: 16)

        if text.length > 0 {
            textView.textStorage?.setAttributedString(text)
        } else {
            textView.typingAttributes = WriteyDocument.defaultBodyAttributes()
        }

        applyTheme(to: textView)
        context.coordinator.observeFirstResponder(textView)

        DispatchQueue.main.async {
            editor.textView = textView
            editor.refreshState()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Only push externally-driven updates (e.g. sync pull) — avoid
        // overwriting while the user is typing.
        if !context.coordinator.isApplyingLocalEdit && textView.attributedString() != text {
            let selection = textView.selectedRanges
            textView.textStorage?.setAttributedString(text)
            textView.selectedRanges = selection
        }

        applyTheme(to: textView)
    }

    private func applyTheme(to textView: NSTextView) {
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textColor = theme.editorTextNSColor
        textView.insertionPointColor = theme.caretNSColor
        textView.selectedTextAttributes = [
            .backgroundColor: theme.selectionBackgroundNSColor,
            .foregroundColor: theme.editorTextNSColor
        ]
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        var isApplyingLocalEdit = false
        private var observers: [NSObjectProtocol] = []

        init(_ parent: RichTextEditor) { self.parent = parent }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isApplyingLocalEdit = true
            parent.text = textView.attributedString()
            DispatchQueue.main.async { [weak self] in
                self?.isApplyingLocalEdit = false
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.editor.refreshState()
            }
        }

        func observeFirstResponder(_ textView: NSTextView) {
            let token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak textView, weak self] _ in
                guard let textView, let self else { return }
                if textView.window?.firstResponder === textView {
                    self.parent.editor.textView = textView
                    self.parent.editor.refreshState()
                }
            }
            observers.append(token)
        }
    }
}
