import AppKit
import Combine

/// A small bridge between SwiftUI menu / toolbar commands and the active
/// `NSTextView`. The text view registers itself when it becomes the first
/// responder; toolbar / menu actions look up the controller from the
/// environment and invoke formatting commands directly on the text view.
///
/// This avoids the awkward "no rich-text editing in pure SwiftUI" problem
/// while still letting the editor live inside a SwiftUI scene.
final class EditorController: ObservableObject {
    weak var textView: NSTextView?

    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderline: Bool = false

    // MARK: - Inline formatting

    func toggleBold()      { applyTrait(.boldFontMask) }
    func toggleItalic()    { applyTrait(.italicFontMask) }

    func toggleUnderline() {
        modifySelection { storage, range in
            let current = storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
            let new: Int = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            storage.addAttribute(.underlineStyle, value: new, range: range)
        }
    }

    // MARK: - Paragraph style

    /// 0 = body, 1 = title, 2 = heading, 3 = subheading
    func applyHeading(level: Int) {
        let (size, weight): (CGFloat, NSFont.Weight) = {
            switch level {
            case 1: return (28, .bold)
            case 2: return (22, .semibold)
            case 3: return (18, .semibold)
            default: return (16, .regular)
            }
        }()
        modifyParagraphs { storage, paraRange in
            let font = NSFont.systemFont(ofSize: size, weight: weight)
            storage.addAttribute(.font, value: font, range: paraRange)
        }
    }

    // NSTextList marker tokens (`{decimal}`, `{disc}`, …) render as just the
    // glyph. Wrap them in a format string to add the trailing period and a
    // tab so list items line up cleanly:
    //   1.    First item
    //   2.    Second item
    func toggleBulletList()    { applyList(format: NSTextList.MarkerFormat(rawValue: "{disc}\t")) }
    func toggleNumberedList()  { applyList(format: NSTextList.MarkerFormat(rawValue: "{decimal}.\t")) }

    private func applyList(format: NSTextList.MarkerFormat) {
        guard let textView, let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        let paraRange = (storage.string as NSString).paragraphRange(for: selection)

        textView.undoManager?.beginUndoGrouping()
        storage.beginEditing()

        let para: NSMutableParagraphStyle = {
            if let existing = storage.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle {
                return existing.mutableCopy() as! NSMutableParagraphStyle
            }
            return NSMutableParagraphStyle()
        }()

        if para.textLists.contains(where: { $0.markerFormat == format }) {
            para.textLists = []
            para.headIndent = 0
            para.firstLineHeadIndent = 0
        } else {
            let list = NSTextList(markerFormat: format, options: 0)
            para.textLists = [list]
            para.headIndent = 24
            para.firstLineHeadIndent = 0
        }

        storage.addAttribute(.paragraphStyle, value: para, range: paraRange)
        storage.endEditing()
        textView.undoManager?.endUndoGrouping()
        textView.didChangeText()
    }

    // MARK: - Selection sync

    func refreshState() {
        guard let textView, let storage = textView.textStorage else {
            isBold = false; isItalic = false; isUnderline = false
            return
        }
        let range = textView.selectedRange()
        let probe = range.length > 0 ? range.location : max(0, range.location - 1)
        guard probe < storage.length else {
            isBold = false; isItalic = false; isUnderline = false
            return
        }
        let attrs = storage.attributes(at: probe, effectiveRange: nil)
        if let font = attrs[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            isBold = traits.contains(.boldFontMask)
            isItalic = traits.contains(.italicFontMask)
        } else {
            isBold = false; isItalic = false
        }
        let underline = attrs[.underlineStyle] as? Int ?? 0
        isUnderline = underline != 0
    }

    // MARK: - Helpers

    private func applyTrait(_ trait: NSFontTraitMask) {
        modifySelection { storage, range in
            storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let baseFont = (value as? NSFont) ?? NSFont.systemFont(ofSize: 16)
                let currentTraits = NSFontManager.shared.traits(of: baseFont)
                let nextFont: NSFont
                if currentTraits.contains(trait) {
                    nextFont = NSFontManager.shared.convert(baseFont, toNotHaveTrait: trait)
                } else {
                    nextFont = NSFontManager.shared.convert(baseFont, toHaveTrait: trait)
                }
                storage.addAttribute(.font, value: nextFont, range: subRange)
            }
        }
    }

    private func modifySelection(_ change: (NSTextStorage, NSRange) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        var range = textView.selectedRange()
        if range.length == 0 {
            // Apply to current word, or fall through if at empty document.
            let nsString = storage.string as NSString
            if nsString.length == 0 { return }
            range = nsString.paragraphRange(for: range)
        }
        textView.undoManager?.beginUndoGrouping()
        storage.beginEditing()
        change(storage, range)
        storage.endEditing()
        textView.undoManager?.endUndoGrouping()
        textView.didChangeText()
        refreshState()
    }

    private func modifyParagraphs(_ change: (NSTextStorage, NSRange) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        let nsString = storage.string as NSString
        let selection = textView.selectedRange()
        let paraRange = nsString.paragraphRange(for: selection)
        textView.undoManager?.beginUndoGrouping()
        storage.beginEditing()
        change(storage, paraRange)
        storage.endEditing()
        textView.undoManager?.endUndoGrouping()
        textView.didChangeText()
        refreshState()
    }
}
