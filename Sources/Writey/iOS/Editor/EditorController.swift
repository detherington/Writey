import UIKit
import Combine

/// Formatting commands for the document's `UITextView`, shared by the
/// toolbar and the iPad menu bar.
///
/// Bold / italic / underline use UITextView's own toggles, which handle undo
/// and apply to what you type next when nothing is selected. Headings, lists
/// and sync pulls edit the text storage directly and register their own undo.
/// Every edit reaches the document through the storage observer, so nothing
/// depends on a SwiftUI re-render to be saved.
@MainActor
final class EditorController: ObservableObject, DocumentTextEditing {
    private(set) weak var textView: UITextView?

    @Published private(set) var isBold = false
    @Published private(set) var isItalic = false
    @Published private(set) var isUnderline = false
    @Published private(set) var isBulletList = false
    @Published private(set) var isNumberedList = false

    static let bulletFormat = NSTextList.MarkerFormat(rawValue: "{disc}\t")
    static let numberedFormat = NSTextList.MarkerFormat(rawValue: "{decimal}.\t")

    func attach(_ textView: UITextView) {
        self.textView = textView
        refreshState()
    }

    func focus() { textView?.becomeFirstResponder() }

    // MARK: - Inline formatting

    func toggleBold()      { textView?.toggleBoldface(nil); refreshState() }
    func toggleItalic()    { textView?.toggleItalics(nil); refreshState() }
    func toggleUnderline() { textView?.toggleUnderline(nil); refreshState() }

    // MARK: - Paragraph formatting

    /// 0 = body, 1 = title, 2 = heading, 3 = subheading
    func applyHeading(level: Int) {
        guard let textView else { return }
        let font = WriteyDocument.font(forHeadingLevel: level)
        let paragraph = currentParagraphRange(in: textView)
        if paragraph.length > 0 {
            editAttributes(in: paragraph, actionName: "Paragraph Style") { storage, range in
                storage.addAttribute(.font, value: font, range: range)
            }
        }
        textView.typingAttributes[.font] = font
        refreshState()
    }

    func toggleBulletList()   { toggleList(Self.bulletFormat) }
    func toggleNumberedList() { toggleList(Self.numberedFormat) }

    private func toggleList(_ format: NSTextList.MarkerFormat) {
        guard let textView else { return }
        let storage = textView.textStorage
        let paragraph = currentParagraphRange(in: textView)
        let existing = paragraph.length > 0
            ? storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            : textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? WriteyDocument.defaultParagraphStyle()

        if style.textLists.contains(where: { $0.markerFormat == format }) {
            style.textLists = []
            style.headIndent = 0
        } else {
            style.textLists = [NSTextList(markerFormat: format, options: 0)]
            style.headIndent = 24
        }
        style.firstLineHeadIndent = 0

        if paragraph.length > 0 {
            editAttributes(in: paragraph, actionName: "List") { storage, range in
                storage.addAttribute(.paragraphStyle, value: style, range: range)
            }
        }
        textView.typingAttributes[.paragraphStyle] = style
        refreshState()
    }

    // MARK: - Whole-document replacement (sync pulls)

    func replaceAllText(with text: NSAttributedString, actionName: String) {
        guard let textView else { return }
        textView.unmarkText()
        let caret = textView.selectedRange.location
        let before = NSAttributedString(attributedString: textView.textStorage)
        replaceStorage(with: text)
        textView.selectedRange = NSRange(location: min(caret, textView.textStorage.length), length: 0)
        registerReplacementUndo(restoring: before, redo: text, actionName: actionName)
        refreshState()
    }

    private func replaceStorage(with text: NSAttributedString) {
        guard let storage = textView?.textStorage else { return }
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
    }

    private func registerReplacementUndo(restoring old: NSAttributedString, redo new: NSAttributedString, actionName: String) {
        guard let undoManager = textView?.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.replaceStorage(with: old)
                target.registerReplacementUndo(restoring: new, redo: old, actionName: actionName)
                target.refreshState()
            }
        }
        undoManager.setActionName(actionName)
    }

    // MARK: - Toolbar / menu state

    func refreshState() {
        guard let textView else {
            update(bold: false, italic: false, underline: false, lists: [])
            return
        }
        let storage = textView.textStorage
        let selection = textView.selectedRange
        let attributes: [NSAttributedString.Key: Any] = selection.length == 0 || selection.location >= storage.length
            ? textView.typingAttributes
            : storage.attributes(at: selection.location, effectiveRange: nil)

        let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
        update(
            bold: traits.contains(.traitBold),
            italic: traits.contains(.traitItalic),
            underline: (attributes[.underlineStyle] as? Int ?? 0) != 0,
            lists: (attributes[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        )
    }

    private func update(bold: Bool, italic: Bool, underline: Bool, lists: [NSTextList]) {
        if isBold != bold { isBold = bold }
        if isItalic != italic { isItalic = italic }
        if isUnderline != underline { isUnderline = underline }
        let bullet = lists.contains { $0.markerFormat == Self.bulletFormat }
        let numbered = lists.contains { $0.markerFormat == Self.numberedFormat }
        if isBulletList != bullet { isBulletList = bullet }
        if isNumberedList != numbered { isNumberedList = numbered }
    }

    // MARK: - Helpers

    /// Applies an attribute-only change and registers an undo that restores
    /// the previous attributes (and a redo that reapplies them).
    private func editAttributes(in range: NSRange, actionName: String, _ change: (NSTextStorage, NSRange) -> Void) {
        guard let storage = textView?.textStorage else { return }
        let before = storage.attributedSubstring(from: range)
        storage.beginEditing()
        change(storage, range)
        storage.endEditing()
        registerAttributeUndo(range: range, restoring: before, redo: storage.attributedSubstring(from: range), actionName: actionName)
        refreshState()
    }

    private func registerAttributeUndo(range: NSRange, restoring old: NSAttributedString, redo new: NSAttributedString, actionName: String) {
        guard let undoManager = textView?.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                guard let storage = target.textView?.textStorage, NSMaxRange(range) <= storage.length else { return }
                storage.replaceCharacters(in: range, with: old)
                target.registerAttributeUndo(range: range, restoring: new, redo: old, actionName: actionName)
                target.refreshState()
            }
        }
        undoManager.setActionName(actionName)
    }

    private func currentParagraphRange(in textView: UITextView) -> NSRange {
        (textView.text as NSString).paragraphRange(for: textView.selectedRange)
    }
}
