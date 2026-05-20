import AppKit

extension NSAttributedString {
    /// Returns a copy of the receiver with theme-only attributes (foreground
    /// and background color) stripped. The result represents user-authored
    /// content independent of whatever theme was active in the editor — so
    /// what we save to disk and push to Google Docs renders in the
    /// destination's default colors instead of the light-on-black we use
    /// for on-screen editing comfort.
    ///
    /// Bold, italic, underline, font size, headings, lists, and links are
    /// all preserved — only the *colors* are display-only and get dropped.
    func writeyCanonicalForm() -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: self)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.removeAttribute(.foregroundColor, range: fullRange)
        mutable.removeAttribute(.backgroundColor, range: fullRange)
        return mutable
    }
}
