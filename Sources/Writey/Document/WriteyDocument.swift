import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// The document model.
///
/// Backed by `NSAttributedString` so we get light rich text (bold, italic,
/// underline, headings, lists) for free. Stored on disk as RTF so:
///   - macOS NSDocument autosave-in-place + Versions work out of the box
///   - users can open the file in TextEdit, Pages, Word, etc.
///
/// We use `ReferenceFileDocument` (rather than `FileDocument`) because the
/// underlying type is a reference (`NSAttributedString` mutated through a
/// text view), and because `ReferenceFileDocument`'s snapshot model maps
/// cleanly to the way NSTextView drives edits.
final class WriteyDocument: ReferenceFileDocument {
    typealias Snapshot = Data

    static var readableContentTypes: [UTType] {
        [.rtf, .plainText]
    }

    static var writableContentTypes: [UTType] {
        [.rtf]
    }

    @Published var attributedText: NSAttributedString

    /// Unique document identifier used by the sync-link store so we can
    /// remember the Google Doc this document is linked to even if the file
    /// is moved or renamed. Persisted into the RTF document attributes.
    let documentID: String

    init() {
        self.attributedText = NSAttributedString(
            string: "",
            attributes: WriteyDocument.defaultBodyAttributes()
        )
        self.documentID = UUID().uuidString
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        if configuration.contentType == .plainText {
            let text = String(data: data, encoding: .utf8) ?? ""
            self.attributedText = NSAttributedString(
                string: text,
                attributes: WriteyDocument.defaultBodyAttributes()
            )
            self.documentID = UUID().uuidString
            return
        }

        var documentAttributes: NSDictionary?
        let attr = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: &documentAttributes
        )
        self.attributedText = attr

        // Recover (or mint) a stable document ID stored in RTF metadata.
        if let custom = documentAttributes?["WriteyDocumentID"] as? String, !custom.isEmpty {
            self.documentID = custom
        } else {
            self.documentID = UUID().uuidString
        }
    }

    func snapshot(contentType: UTType) throws -> Data {
        let range = NSRange(location: 0, length: attributedText.length)
        let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf,
            // Custom attributes are written into the RTF \*\info group and
            // round-tripped on read.
            NSAttributedString.DocumentAttributeKey(rawValue: "WriteyDocumentID"): documentID
        ]
        return try attributedText.data(from: range, documentAttributes: attrs)
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }

    // MARK: - Default styling

    static func defaultBodyAttributes() -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.4
        return [
            .font: NSFont.systemFont(ofSize: 16, weight: .regular),
            .paragraphStyle: para
        ]
    }
}
