import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension NSAttributedString {
    /// Returns a copy of the receiver with display-only attributes undone:
    /// theme colors (foreground and background) stripped, and text shown in
    /// the reader's typography put back in Writey's standard styles. The
    /// result represents user-authored content independent of whatever
    /// theme and typography were active in the editor — so what we save to
    /// disk, fingerprint and push to Google Docs is the same on every
    /// device and renders in the destination's default colors.
    ///
    /// Bold, italic, underline, headings, lists, and links are all
    /// preserved, as is text with a font of its own.
    func writeyCanonicalForm() -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: self)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.removeAttribute(.foregroundColor, range: fullRange)
        mutable.removeAttribute(.backgroundColor, range: fullRange)
        // Tagged text from the editor, and text already in a standard style
        // (e.g. reopened from RTF, which saves the system font as Helvetica
        // Neue), both come out as the exact standard fonts — so the same
        // document always yields the same bytes and sync fingerprint.
        mutable.enumerateAttributes(in: fullRange) { attributes, run, _ in
            guard let font = attributes[.font] as? PlatformFont,
                  let level = (attributes[.writeyTextStyle] as? Int) ?? Typography.standardLevel(of: font)
            else { return }
            mutable.addAttributes([
                .font: Typography.standardFont(level: level, bold: font.writeyIsBold, italic: font.writeyIsItalic),
                .paragraphStyle: Typography.standardParagraphStyle(from: attributes[.paragraphStyle] as? NSParagraphStyle)
            ], range: run)
        }
        mutable.removeAttribute(.writeyTextStyle, range: fullRange)
        return mutable
    }
}
