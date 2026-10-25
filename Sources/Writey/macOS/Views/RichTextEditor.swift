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
    let typography: Typography
    /// Focus mode's unit, or nil when it's off.
    let focus: FocusUnit?
    /// ⌘-click or right-click on a web link: open it in the reference pane.
    var openAsReference: (URL) -> Void = { _ in }

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
        coordinator.openAsReference = openAsReference
        coordinator.attach(textView)
        coordinator.applyTheme(context.environment.colorScheme)
        coordinator.applyTypography(typography)
        coordinator.load(document)
        coordinator.setFocus(focus)
        editor.attach(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.openAsReference = openAsReference
        if coordinator.loadedDocument !== document {
            coordinator.load(document)
        }
        coordinator.applyTheme(context.environment.colorScheme)
        coordinator.applyTypography(typography)
        coordinator.setFocus(focus)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let editor: EditorController
        private let storageObserver = EditorStorageObserver()
        private weak var textView: NSTextView?
        private(set) weak var loadedDocument: WriteyDocument?
        private var appliedScheme: ColorScheme?
        private var appliedTypography: Typography?
        private var focusUnit: FocusUnit?
        private var isDimmed = false
        nonisolated(unsafe) private var resizeObserver: NSObjectProtocol?
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
            // A resized window changes where the middle is; focus mode
            // re-centers the line.
            if let clip = textView.enclosingScrollView?.contentView {
                clip.postsFrameChangedNotifications = true
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: clip, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        if self?.focusUnit != nil { self?.centerCaret() }
                    }
                }
            }
        }

        deinit {
            if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
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
                textView.typingAttributes = appliedTypography?.displayAttributes(attributes) ?? attributes
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
            applyFocus()
        }

        /// Shows Writey's styles in the reader's typography. Display only —
        /// the document keeps its standard styles — and, made straight on the
        /// storage, it registers no undo, so the document isn't marked edited.
        func applyTypography(_ typography: Typography) {
            guard typography != appliedTypography, let textView, let storage = textView.textStorage else { return }
            appliedTypography = typography
            storageObserver.typography = typography
            editor.typography = typography
            if storage.length > 0 {
                storage.beginEditing()
                typography.applyDisplay(to: storage, in: NSRange(location: 0, length: storage.length))
                storage.endEditing()
            }
            textView.typingAttributes = typography.displayAttributes(textView.typingAttributes)
        }

        func setFocus(_ unit: FocusUnit?) {
            guard unit != focusUnit else { return }
            focusUnit = unit
            applyFocus()
        }

        // MARK: Focus mode

        /// Dims all but the sentence or paragraph being written, and keeps
        /// its line in the middle of the window, like a typewriter.
        private func applyFocus() {
            guard let textView, let storage = textView.textStorage else { return }
            if let appliedScheme, focusUnit != nil || isDimmed {
                let lit = focusUnit.map { Focus.range(in: storage.string as NSString, selection: textView.selectedRange(), unit: $0) }
                let dim = EditorPalette.text(appliedScheme).withAlphaComponent(0.28)
                if let layoutManager = textView.textLayoutManager {
                    Focus.dim(layoutManager, except: lit, color: dim)
                } else if let layoutManager = textView.layoutManager {
                    // TextKit 1 (only reached if the view ever falls back to it).
                    let everything = NSRange(location: 0, length: storage.length)
                    layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: everything)
                    if let lit {
                        layoutManager.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: everything)
                        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: lit)
                    }
                }
                isDimmed = focusUnit != nil
            }
            centerCaret()
        }

        private static let inset: CGFloat = 32

        private func centerCaret() {
            guard let textView, let scrollView = textView.enclosingScrollView, let window = textView.window else { return }
            let clip = scrollView.contentView
            let visible = clip.bounds.height
            // Half a window of room above and below lets the first and last
            // lines reach the middle too.
            let inset = NSSize(width: Self.inset, height: focusUnit == nil ? Self.inset : max(Self.inset, visible / 2))
            if textView.textContainerInset != inset {
                textView.textContainerInset = inset
                // The text view doesn't grow for the new inset by itself,
                // and the scroll range would stop short of the middle.
                textView.sizeToFit()
            }
            guard focusUnit != nil, visible > 0 else { return }
            let caretOnScreen = textView.firstRect(forCharacterRange: NSRange(location: textView.selectedRange().location, length: 0), actualRange: nil)
            guard !caretOnScreen.isNull else { return }
            let caret = textView.convert(window.convertFromScreen(caretOnScreen), from: nil)
            let highest = max(0, textView.bounds.height - visible)
            let y = min(max(caret.midY - visible / 2, 0), highest)
            guard abs(clip.bounds.origin.y - y) > 0.5 else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                clip.animator().setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: y))
            }
            scrollView.reflectScrolledClipView(clip)
        }

        private func storageDidChange(_ storage: NSTextStorage) {
            loadedDocument?.attributedText = NSAttributedString(attributedString: storage)
            scheduleStateRefresh()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            scheduleStateRefresh()
        }

        var openAsReference: (URL) -> Void = { _ in }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            ReferenceLinks.click(link, open: openAsReference)
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            ReferenceLinks.menu(menu, for: view, at: charIndex, open: openAsReference)
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
                self.applyFocus()
            }
        }
    }
}
