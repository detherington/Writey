import Foundation
import AppKit

/// Converts NSAttributedString <-> HTML for Google Docs round-tripping.
///
/// NSAttributedString already speaks HTML via Cocoa's document type
/// converters; we just wrap it with sensible defaults.
enum HTMLConverter {
    static func html(from attr: NSAttributedString) -> String {
        // Strip Writey's theme colors before pushing to Google Docs.
        // Bold / italic / underline / headings / lists / font size are
        // preserved; only foreground+background colors are dropped, so
        // the doc on the Google side renders in Google's default colors.
        let canonical = attr.writeyCanonicalForm()
        let range = NSRange(location: 0, length: canonical.length)
        let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let data = try? canonical.data(from: range, documentAttributes: attrs),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    static func attributedString(from html: String) -> NSAttributedString? {
        guard let data = html.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
    }
}
