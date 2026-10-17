import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum FocusUnit: String, CaseIterable, Identifiable {
    case sentence, paragraph
    var id: String { rawValue }
    var label: String { self == .sentence ? "Sentence" : "Paragraph" }
}

/// Focus mode's dimming, shared by both editors: everything but the
/// sentence or paragraph being written is drawn faint.
enum Focus {
    /// The sentence or paragraph around the cursor. A selection keeps its
    /// whole paragraphs lit.
    static func range(in text: NSString, selection: NSRange, unit: FocusUnit) -> NSRange {
        let paragraph = text.paragraphRange(for: selection)
        guard unit == .sentence, selection.length == 0 else { return paragraph }
        // The last sentence starting at or before the cursor: the one being
        // typed, or just finished.
        var sentence = paragraph
        text.enumerateSubstrings(in: paragraph, options: [.bySentences, .substringNotRequired]) { _, _, enclosing, stop in
            if enclosing.location <= selection.location {
                sentence = enclosing
            } else {
                stop.pointee = true
            }
        }
        return sentence
    }

    /// Draws all but `focus` in `color`, or everything normally when
    /// `focus` is nil. Rendering attributes only affect drawing, so the
    /// text — what's saved, undone and synced — is never touched.
    @MainActor
    static func dim(_ layoutManager: NSTextLayoutManager, except focus: NSRange?, color: PlatformColor) {
        let document = layoutManager.documentRange
        layoutManager.removeRenderingAttribute(.foregroundColor, for: document)
        guard let focus else { return }
        layoutManager.addRenderingAttribute(.foregroundColor, value: color, for: document)
        if let lit = textRange(focus, in: layoutManager) {
            layoutManager.removeRenderingAttribute(.foregroundColor, for: lit)
        }
    }

    @MainActor
    private static func textRange(_ range: NSRange, in layoutManager: NSTextLayoutManager) -> NSTextRange? {
        guard let content = layoutManager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }
}
