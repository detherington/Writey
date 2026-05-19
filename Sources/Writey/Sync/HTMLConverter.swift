import Foundation
import AppKit

/// Converts NSAttributedString <-> HTML for Google Docs round-tripping.
///
/// NSAttributedString already speaks HTML via Cocoa's document type
/// converters; we just wrap it with sensible defaults.
enum HTMLConverter {
    static func html(from attr: NSAttributedString) -> String {
        let range = NSRange(location: 0, length: attr.length)
        let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let data = try? attr.data(from: range, documentAttributes: attrs),
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
