import SwiftUI
import UIKit

/// SwiftUI wrapper around `UITextView`.
///
/// The text view owns the live text. Every storage edit is copied into the
/// document by `EditorStorageObserver`, and reported through `onEdit` so the
/// file gets saved. The view only reloads from the document when it's a
/// different document or `revision` changes (the file changed on another
/// device), never because of a SwiftUI re-render — re-rendering used to
/// reset the text and wipe out toolbar formatting.
struct RichTextEditor: UIViewRepresentable {
    let document: WriteyDocument
    let revision: Int
    let editor: EditorController
    let typography: Typography
    /// Focus mode's unit, or nil when it's off.
    let focus: FocusUnit?
    let onEdit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(editor: editor) }

    func makeUIView(context: Context) -> UITextView {
        let textView = WriteyTextView()
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
        coordinator.onEdit = onEdit
        coordinator.attach(textView)
        textView.onResize = { [weak coordinator] in coordinator?.viewDidResize() }
        coordinator.applyTheme(context.environment.colorScheme)
        coordinator.applyTypography(typography)
        coordinator.load(document, revision: revision)
        coordinator.setFocus(focus)
        editor.attach(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onEdit = onEdit
        if coordinator.loadedDocument !== document || coordinator.loadedRevision != revision {
            coordinator.load(document, revision: revision)
        }
        coordinator.applyTheme(context.environment.colorScheme)
        coordinator.applyTypography(typography)
        coordinator.setFocus(focus)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        /// Marks the file as changed so it gets saved.
        var onEdit: () -> Void = {}

        private let editor: EditorController
        private let storageObserver = EditorStorageObserver()
        private weak var textView: UITextView?
        private(set) weak var loadedDocument: WriteyDocument?
        private(set) var loadedRevision: Int?
        private var appliedScheme: ColorScheme?
        private var appliedTypography: Typography?
        private var focusUnit: FocusUnit?
        private var isDimmed = false
        private var isApplyingNonEdit = false
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

        /// Loads a document's text without marking it edited. A reload of the
        /// same document (changed on another device) keeps the cursor where
        /// it was, as far as the new text allows.
        func load(_ document: WriteyDocument, revision: Int) {
            guard let textView else { return }
            let isReload = loadedDocument === document
            let selection = textView.selectedRange
            loadedDocument = document
            loadedRevision = revision
            withoutMarkingEdited {
                textView.textStorage.setAttributedString(document.attributedText)
            }
            if textView.textStorage.length == 0 {
                var attributes = WriteyDocument.defaultBodyAttributes()
                attributes[.foregroundColor] = storageObserver.textColor
                textView.typingAttributes = appliedTypography?.displayAttributes(attributes) ?? attributes
            }
            let location = isReload ? min(selection.location, textView.textStorage.length) : 0
            textView.selectedRange = NSRange(location: location, length: 0)
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
            applyFocus()
        }

        /// Shows Writey's styles in the reader's typography. Display only —
        /// the document keeps its standard styles — so not an edit.
        func applyTypography(_ typography: Typography) {
            guard typography != appliedTypography, let textView else { return }
            appliedTypography = typography
            storageObserver.typography = typography
            editor.typography = typography
            let storage = textView.textStorage
            if storage.length > 0 {
                withoutMarkingEdited {
                    storage.beginEditing()
                    typography.applyDisplay(to: storage, in: NSRange(location: 0, length: storage.length))
                    storage.endEditing()
                }
            }
            textView.typingAttributes = typography.displayAttributes(textView.typingAttributes)
        }

        /// Rotation or the keyboard changed the room there is; focus mode
        /// re-centers the line.
        func viewDidResize() {
            if focusUnit != nil { centerCaret() }
        }

        func setFocus(_ unit: FocusUnit?) {
            guard unit != focusUnit else { return }
            focusUnit = unit
            applyFocus()
        }

        // MARK: Focus mode

        /// Dims all but the sentence or paragraph being written, and keeps
        /// its line in the middle of the screen, like a typewriter.
        private func applyFocus() {
            guard let textView else { return }
            if let layoutManager = textView.textLayoutManager, let appliedScheme, focusUnit != nil || isDimmed {
                let lit = focusUnit.map {
                    Focus.range(in: textView.textStorage.string as NSString, selection: textView.selectedRange, unit: $0)
                }
                Focus.dim(layoutManager, except: lit, color: EditorPalette.text(appliedScheme).withAlphaComponent(0.28))
                isDimmed = focusUnit != nil
            }
            centerCaret()
        }

        private static let inset: CGFloat = 32

        private func centerCaret() {
            guard let textView else { return }
            let chrome = textView.adjustedContentInset
            let visible = textView.bounds.height - chrome.top - chrome.bottom
            // Half a screen of room above and below lets the first and last
            // lines reach the middle too.
            let vertical = focusUnit == nil ? Self.inset : max(Self.inset, visible / 2)
            let insets = UIEdgeInsets(top: vertical, left: Self.inset, bottom: vertical, right: Self.inset)
            if textView.textContainerInset != insets { textView.textContainerInset = insets }
            guard focusUnit != nil, visible > 0, let caretPosition = textView.selectedTextRange?.end else { return }
            textView.layoutIfNeeded()
            let caret = textView.caretRect(for: caretPosition)
            guard !caret.isNull, !caret.isInfinite else { return }
            let lowest = -chrome.top
            let highest = max(lowest, textView.contentSize.height - textView.bounds.height + chrome.bottom)
            let y = min(max(caret.midY - chrome.top - visible / 2, lowest), highest)
            if abs(textView.contentOffset.y - y) > 0.5 {
                textView.setContentOffset(CGPoint(x: textView.contentOffset.x, y: y), animated: true)
            }
        }

        private func storageDidChange(_ storage: NSTextStorage) {
            loadedDocument?.attributedText = NSAttributedString(attributedString: storage)
            if !isApplyingNonEdit { onEdit() }
            scheduleStateRefresh()
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
                self.applyFocus()
            }
        }
    }
}

/// Reports size changes — rotation, the keyboard coming and going — so
/// focus mode can keep the line in the middle.
final class WriteyTextView: UITextView {
    var onResize: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        onResize?()
    }
}
