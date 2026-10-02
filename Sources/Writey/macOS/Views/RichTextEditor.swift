import SwiftUI
import AppKit

/// SwiftUI wrapper around `NSTextView`.
///
/// The text view owns the live text. Every storage edit is copied into the
/// document by `EditorStorageObserver`. The view only reloads from the
/// document when SwiftUI hands it a *different* document instance (e.g.
/// File ▸ Revert To), never because of a SwiftUI re-render.
struct RichTextEditor: NSViewRepresentable {
    let document: WriteyDocument
    let editor: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
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
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 32, height: 32)

        let coordinator = context.coordinator
        coordinator.attach(textView)
        coordinator.applyTheme(context.environment.colorScheme)
        coordinator.load(document)
        editor.attach(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.loadedDocument !== document {
            coordinator.load(document)
        }
        coordinator.applyTheme(context.environment.colorScheme)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let editor: EditorController
        private let storageObserver = EditorStorageObserver()
        private weak var textView: NSTextView?
        private(set) weak var loadedDocument: WriteyDocument?
        private var appliedScheme: ColorScheme?
        private var stateRefreshPending = false

        init(editor: EditorController) {
            self.editor = editor
            super.init()
            storageObserver.onChange = { [weak self] storage in
                MainActor.assumeIsolated { self?.storageDidChange(storage) }
            }
        }

        func attach(_ textView: NSTextView) {
            self.textView = textView
            textView.textStorage?.delegate = storageObserver
        }

        /// Loads a document's text without registering undo, so opening or
        /// reverting a document doesn't mark it edited.
        func load(_ document: WriteyDocument) {
            guard let textView, let storage = textView.textStorage else { return }
            loadedDocument = document
            storage.setAttributedString(document.attributedText)
            if storage.length == 0 {
                var attributes = WriteyDocument.defaultBodyAttributes()
                attributes[.foregroundColor] = storageObserver.textColor
                textView.typingAttributes = attributes
            }
            textView.setSelectedRange(NSRange(location: 0, length: 0))
        }

        /// Recolors only when the resolved light/dark scheme changes.
        func applyTheme(_ scheme: ColorScheme) {
            guard scheme != appliedScheme, let textView, let storage = textView.textStorage else { return }
            appliedScheme = scheme
            let color = EditorPalette.text(scheme)
            storageObserver.textColor = color
            if storage.length > 0 {
                storage.beginEditing()
                storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: storage.length))
                storage.endEditing()
            }
            textView.typingAttributes[.foregroundColor] = color
            textView.insertionPointColor = color
            textView.selectedTextAttributes = [
                .backgroundColor: EditorPalette.selection(scheme),
                .foregroundColor: color
            ]
        }

        private func storageDidChange(_ storage: NSTextStorage) {
            loadedDocument?.attributedText = NSAttributedString(attributedString: storage)
            scheduleStateRefresh()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            scheduleStateRefresh()
        }

        /// Deferred so we never publish toolbar state from inside a SwiftUI
        /// view update (loads happen during make/updateNSView).
        private func scheduleStateRefresh() {
            guard !stateRefreshPending else { return }
            stateRefreshPending = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stateRefreshPending = false
                self.editor.refreshState()
            }
        }
    }
}
