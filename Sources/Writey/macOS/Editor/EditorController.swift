import AppKit
import Combine

/// Formatting commands for the window's `NSTextView`, shared by the toolbar
/// and the Format menu.
///
/// Every change to existing text goes through
/// `shouldChangeText(inRanges:)` / `didChangeText()`, which is how
/// NSTextView registers undo — and registering with the document's undo
/// manager is what tells SwiftUI the document needs saving. With nothing
/// selected, formatting applies to what you type next.
@MainActor
final class EditorController: ObservableObject, DocumentTextEditing {
    private(set) weak var textView: NSTextView?

    @Published private(set) var isBold = false
    @Published private(set) var isItalic = false
    @Published private(set) var isUnderline = false
    @Published private(set) var isBulletList = false
    @Published private(set) var isNumberedList = false

    // NSTextList marker tokens render as just the glyph; the trailing "."
    // and tab make items read "1.  First item".
    static let bulletFormat = NSTextList.MarkerFormat(rawValue: "{disc}\t")
    static let numberedFormat = NSTextList.MarkerFormat(rawValue: "{decimal}.\t")

    func attach(_ textView: NSTextView) {
        self.textView = textView
        refreshState()
    }

    // MARK: - Inline formatting

    func toggleBold()   { toggleFontTrait(.boldFontMask, actionName: "Bold") }
    func toggleItalic() { toggleFontTrait(.italicFontMask, actionName: "Italic") }

    func toggleUnderline() {
        // NSText's built-in toggle already handles typing attributes and undo.
        textView?.underline(nil)
        refreshState()
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask, actionName: String) {
        guard let textView, let storage = textView.textStorage else { return }
        let fontManager = NSFontManager.shared
        let ranges = selectedRanges(in: textView)

        guard !ranges.isEmpty else {
            let font = (textView.typingAttributes[.font] as? NSFont) ?? WriteyDocument.font(forHeadingLevel: 0)
            textView.typingAttributes[.font] = fontManager.traits(of: font).contains(trait)
                ? fontManager.convert(font, toNotHaveTrait: trait)
                : fontManager.convert(font, toHaveTrait: trait)
            refreshState()
            return
        }

        // Pages-style toggle: the first selected character decides whether
        // the whole selection gains or loses the trait.
        let first = (storage.attribute(.font, at: ranges[0].location, effectiveRange: nil) as? NSFont)
            ?? WriteyDocument.font(forHeadingLevel: 0)
        let adding = !fontManager.traits(of: first).contains(trait)

        editAttributes(in: ranges, actionName: actionName) { storage, range in
            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = (value as? NSFont) ?? WriteyDocument.font(forHeadingLevel: 0)
                let converted = adding
                    ? fontManager.convert(font, toHaveTrait: trait)
                    : fontManager.convert(font, toNotHaveTrait: trait)
                storage.addAttribute(.font, value: converted, range: subrange)
            }
        }
    }

    // MARK: - Paragraph formatting

    /// 0 = body, 1 = title, 2 = heading, 3 = subheading
    func applyHeading(level: Int) {
        guard let textView else { return }
        let font = WriteyDocument.font(forHeadingLevel: level)
        let paragraph = currentParagraphRange(in: textView)
        if paragraph.length > 0 {
            editAttributes(in: [paragraph], actionName: "Paragraph Style") { storage, range in
                storage.addAttribute(.font, value: font, range: range)
            }
        }
        textView.typingAttributes[.font] = font
        refreshState()
    }

    func toggleBulletList()   { toggleList(Self.bulletFormat) }
    func toggleNumberedList() { toggleList(Self.numberedFormat) }

    private func toggleList(_ format: NSTextList.MarkerFormat) {
        guard let textView, let storage = textView.textStorage else { return }
        let paragraph = currentParagraphRange(in: textView)
        // An empty last line has no characters to read a style from, so use
        // the typing attributes (reading at `storage.length` would throw).
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
            editAttributes(in: [paragraph], actionName: "List") { storage, range in
                storage.addAttribute(.paragraphStyle, value: style, range: range)
            }
        }
        textView.typingAttributes[.paragraphStyle] = style
        refreshState()
    }

    // MARK: - Whole-document replacement (sync pulls)

    func replaceAllText(with text: NSAttributedString, actionName: String) {
        guard let textView, let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        let caret = textView.selectedRange().location
        textView.breakUndoCoalescing()
        guard textView.shouldChangeText(in: full, replacementString: text.string) else { return }
        storage.replaceCharacters(in: full, with: text)
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        textView.setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
        refreshState()
    }

    // MARK: - Toolbar / menu state

    func refreshState() {
        guard let textView, let storage = textView.textStorage else {
            update(bold: false, italic: false, underline: false, lists: [])
            return
        }
        let selection = textView.selectedRange()
        let attributes: [NSAttributedString.Key: Any] = selection.length == 0 || selection.location >= storage.length
            ? textView.typingAttributes
            : storage.attributes(at: selection.location, effectiveRange: nil)

        let traits = (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
        update(
            bold: traits.contains(.boldFontMask),
            italic: traits.contains(.italicFontMask),
            underline: (attributes[.underlineStyle] as? Int ?? 0) != 0,
            lists: (attributes[.paragraphStyle] as? NSParagraphStyle)?.textLists ?? []
        )
    }

    private func update(bold: Bool, italic: Bool, underline: Bool, lists: [NSTextList]) {
        // Assign only on change so observers aren't invalidated needlessly.
        if isBold != bold { isBold = bold }
        if isItalic != italic { isItalic = italic }
        if isUnderline != underline { isUnderline = underline }
        let bullet = lists.contains { $0.markerFormat == Self.bulletFormat }
        let numbered = lists.contains { $0.markerFormat == Self.numberedFormat }
        if isBulletList != bullet { isBulletList = bullet }
        if isNumberedList != numbered { isNumberedList = numbered }
    }

    // MARK: - Helpers

    private func editAttributes(
        in ranges: [NSRange],
        actionName: String,
        _ change: (NSTextStorage, NSRange) -> Void
    ) {
        guard let textView, let storage = textView.textStorage,
              textView.shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: nil)
        else { return }
        storage.beginEditing()
        ranges.forEach { change(storage, $0) }
        storage.endEditing()
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        refreshState()
    }

    private func selectedRanges(in textView: NSTextView) -> [NSRange] {
        textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
    }

    private func currentParagraphRange(in textView: NSTextView) -> NSRange {
        (textView.string as NSString).paragraphRange(for: textView.selectedRange())
    }
}
