import UIKit
import Combine

/// iOS counterpart to the Mac `EditorController`. Operates on a
/// `UITextView` to apply bold/italic/underline/headings/lists to the
/// current selection. Font traits go through `UIFontDescriptor.SymbolicTraits`
/// instead of macOS's `NSFontManager`.
final class EditorController: ObservableObject {
    weak var textView: UITextView?

    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderline: Bool = false

    // MARK: - Inline formatting

    func toggleBold()      { applyTrait(.traitBold) }
    func toggleItalic()    { applyTrait(.traitItalic) }

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
        let (size, weight): (CGFloat, UIFont.Weight) = {
            switch level {
            case 1: return (28, .bold)
            case 2: return (22, .semibold)
            case 3: return (18, .semibold)
            default: return (16, .regular)
            }
        }()
        modifyParagraphs { storage, paraRange in
            let font = UIFont.systemFont(ofSize: size, weight: weight)
            storage.addAttribute(.font, value: font, range: paraRange)
        }
    }

    func toggleBulletList()    { applyList(format: NSTextList.MarkerFormat(rawValue: "{disc}\t")) }
    func toggleNumberedList()  { applyList(format: NSTextList.MarkerFormat(rawValue: "{decimal}.\t")) }

    private func applyList(format: NSTextList.MarkerFormat) {
        guard let textView else { return }
        let storage = textView.textStorage
        let selection = textView.selectedRange
        let paraRange = (storage.string as NSString).paragraphRange(for: selection)

        textView.undoManager?.beginUndoGrouping()
        storage.beginEditing()

        let para: NSMutableParagraphStyle = {
            if storage.length > 0,
               let existing = storage.attribute(.paragraphStyle, at: paraRange.location, effectiveRange: nil) as? NSParagraphStyle {
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
    }

    // MARK: - Selection sync

    func refreshState() {
        guard let textView else {
            isBold = false; isItalic = false; isUnderline = false
            return
        }
        let storage = textView.textStorage
        let range = textView.selectedRange
        let probe = range.length > 0 ? range.location : max(0, range.location - 1)
        guard probe < storage.length else {
            isBold = false; isItalic = false; isUnderline = false
            return
        }
        let attrs = storage.attributes(at: probe, effectiveRange: nil)
        if let font = attrs[.font] as? UIFont {
            let traits = font.fontDescriptor.symbolicTraits
            isBold = traits.contains(.traitBold)
            isItalic = traits.contains(.traitItalic)
        } else {
            isBold = false; isItalic = false
        }
        let underline = attrs[.underlineStyle] as? Int ?? 0
        isUnderline = underline != 0
    }

    // MARK: - Helpers

    private func applyTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        modifySelection { storage, range in
            storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let baseFont = (value as? UIFont) ?? UIFont.systemFont(ofSize: 16)
                var traits = baseFont.fontDescriptor.symbolicTraits
                if traits.contains(trait) {
                    traits.remove(trait)
                } else {
                    traits.insert(trait)
                }
                if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                    let newFont = UIFont(descriptor: descriptor, size: baseFont.pointSize)
                    storage.addAttribute(.font, value: newFont, range: subRange)
                }
            }
        }
    }

    private func modifySelection(_ change: (NSTextStorage, NSRange) -> Void) {
        guard let textView else { return }
        let storage = textView.textStorage
        var range = textView.selectedRange
        if range.length == 0 {
            let nsString = storage.string as NSString
            if nsString.length == 0 { return }
            range = nsString.paragraphRange(for: range)
        }
        textView.undoManager?.beginUndoGrouping()
        storage.beginEditing()
        change(storage, range)
        storage.endEditing()
        textView.undoManager?.endUndoGrouping()
        refreshState()
    }

    private func modifyParagraphs(_ change: (NSTextStorage, NSRange) -> Void) {
        guard let textView else { return }
        let storage = textView.textStorage
        let nsString = storage.string as NSString
        let selection = textView.selectedRange
        let paraRange = nsString.paragraphRange(for: selection)
        textView.undoManager?.beginUndoGrouping()
        storage.beginEditing()
        change(storage, paraRange)
        storage.endEditing()
        textView.undoManager?.endUndoGrouping()
        refreshState()
    }
}
