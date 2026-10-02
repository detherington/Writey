import SwiftUI
import UIKit

/// SwiftUI wrapper around `UITextView`.
///
/// The text view owns the live text. Every storage edit is copied into the
/// document by `EditorStorageObserver`. The view only reloads from the
/// document when SwiftUI hands it a *different* document instance (e.g. the
/// file changed on another device), never because of a SwiftUI re-render —
/// re-rendering used to reset the text and wipe out toolbar formatting.
struct RichTextEditor: UIViewRepresentable {
    let document: WriteyDocument
    let editor: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = true
        textView.isFindInteractionEnabled = true
        textView.autocorrectionType = .default
        textView.smartQuotesType = .yes
        textView.smartDashesType = .yes
        textView.smartInsertDeleteType = .yes
        textView.spellCheckingType = .yes
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)

        let coordinator = context.coordinator
        coordinator.documentUndoManager = context.environment.undoManager
        coordinator.attach(textView)
        coordinator.applyTheme(context.environment.colorScheme)
        coordinator.load(document)
        editor.attach(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.documentUndoManager = context.environment.undoManager
        if coordinator.loadedDocument !== document {
            coordinator.load(document)
        }
        coordinator.applyTheme(context.environment.colorScheme)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        /// SwiftUI's undo manager for this document. SwiftUI saves a
        /// ReferenceFileDocument only when something registers here — but
        /// UITextView keeps its own, separate undo manager for typing, so
        /// without `markDocumentEdited()` iOS never saved anything you typed.
        weak var documentUndoManager: UndoManager?

        private let editor: EditorController
        private let storageObserver = EditorStorageObserver()
        private weak var textView: UITextView?
        private(set) weak var loadedDocument: WriteyDocument?
        private var appliedScheme: ColorScheme?
        private var isApplyingNonEdit = false
        private var editMarkPending = false
        private var stateRefreshPending = false

        init(editor: EditorController) {
            self.editor = editor
            super.init()
            storageObserver.onChange = { [weak self] storage in
                MainActor.assumeIsolated { self?.storageDidChange(storage) }
            }
        }

        func attach(_ textView: UITextView) {
            self.textView = textView
            textView.textStorage.delegate = storageObserver
        }

        /// Loads a document's text without marking it edited.
        func load(_ document: WriteyDocument) {
            guard let textView else { return }
            loadedDocument = document
            withoutMarkingEdited {
                textView.textStorage.setAttributedString(document.attributedText)
            }
            if textView.textStorage.length == 0 {
                var attributes = WriteyDocument.defaultBodyAttributes()
                attributes[.foregroundColor] = storageObserver.textColor
                textView.typingAttributes = attributes
            }
            textView.selectedRange = NSRange(location: 0, length: 0)
        }

        /// Recolors only when the resolved light/dark scheme changes. Not an
        /// edit, so it doesn't mark the document changed.
        func applyTheme(_ scheme: ColorScheme) {
            guard scheme != appliedScheme, let textView else { return }
            appliedScheme = scheme
            let color = EditorPalette.text(scheme)
            storageObserver.textColor = color
            let storage = textView.textStorage
            if storage.length > 0 {
                withoutMarkingEdited {
                    storage.beginEditing()
                    storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: storage.length))
                    storage.endEditing()
                }
            }
            textView.typingAttributes[.foregroundColor] = color
            textView.tintColor = color
        }

        private func storageDidChange(_ storage: NSTextStorage) {
            loadedDocument?.attributedText = NSAttributedString(attributedString: storage)
            if !isApplyingNonEdit { markDocumentEdited() }
            scheduleStateRefresh()
        }

        /// Registers a marker with the document's undo manager — the signal
        /// SwiftUI uses to mark the document edited and autosave it. Real
        /// undo stays with UITextView's own manager (⌘Z, the keyboard's undo
        /// button). One marker per run-loop pass is enough.
        private func markDocumentEdited() {
            guard !editMarkPending, let documentUndoManager else { return }
            editMarkPending = true
            documentUndoManager.registerUndo(withTarget: self) { _ in }
            Task { @MainActor [weak self] in self?.editMarkPending = false }
        }

        private func withoutMarkingEdited(_ body: () -> Void) {
            isApplyingNonEdit = true
            body()
            isApplyingNonEdit = false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            scheduleStateRefresh()
        }

        /// Deferred so toolbar state is never published from inside a
        /// SwiftUI view update (loads happen during make/updateUIView).
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
