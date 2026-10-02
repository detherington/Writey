import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

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
///
/// Google Doc linking is keyed by the file's path on disk (see
/// `SyncLinkStore`), not by anything stored inside the document — Cocoa's
/// RTF writer silently strips custom document-attribute keys, so any UUID
/// we tried to round-trip through the file would be lost on every save.
final class WriteyDocument: ReferenceFileDocument {
    typealias Snapshot = Data

    /// Includes Markdown explicitly so `.md` files show as openable in the
    /// iOS DocumentGroup file browser (which filters on exact declared types,
    /// not UTI conformance).
    static var readableContentTypes: [UTType] {
        var types: [UTType] = [.rtf, .plainText]
        if let markdown = UTType("net.daringfireball.markdown") {
            types.append(markdown)
        }
        return types
    }

    static var writableContentTypes: [UTType] {
        [.rtf]
    }

    /// Deliberately not `@Published`: the text view owns live editing and
    /// copies its storage here on every change. Publishing would re-render
    /// the whole window per keystroke. Change tracking for autosave comes
    /// from the undo manager, not from this property.
    var attributedText: NSAttributedString

    init() {
        self.attributedText = NSAttributedString(
            string: "",
            attributes: WriteyDocument.defaultBodyAttributes()
        )
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.attributedText = try Self.decode(data, as: configuration.contentType)
    }

    func snapshot(contentType: UTType) throws -> Data {
        try Self.encode(attributedText, as: contentType)
    }

    // MARK: - Reading and writing

    /// Anything that conforms to plain text — .txt, .md, .swift, etc. — is
    /// read as UTF-8. Conformance check instead of `== .plainText` so
    /// subtypes like markdown (net.daringfireball.markdown) route here
    /// instead of falling through to the RTF path and crashing.
    static func decode(_ data: Data, as contentType: UTType) throws -> NSAttributedString {
        if contentType.conforms(to: .plainText) {
            return NSAttributedString(
                string: String(decoding: data, as: UTF8.self),
                attributes: defaultBodyAttributes()
            )
        }
        return try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    /// Plain-text types are written back as plain text, so editing a .md or
    /// .txt file never fills it with RTF. Everything else is RTF, with
    /// theme-only colors stripped so the file renders in other apps' default
    /// colors, not Writey's dark-mode grey.
    static func encode(_ text: NSAttributedString, as contentType: UTType) throws -> Data {
        if contentType.conforms(to: .plainText) {
            return Data(text.string.utf8)
        }
        let canonical = text.writeyCanonicalForm()
        return try canonical.data(
            from: NSRange(location: 0, length: canonical.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }

    // MARK: - Default styling

    static func defaultBodyAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: font(forHeadingLevel: 0),
            .paragraphStyle: defaultParagraphStyle()
        ]
    }

    static func defaultParagraphStyle() -> NSMutableParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.4
        return para
    }

    /// 0 = body, 1 = title, 2 = heading, 3 = subheading.
    static func font(forHeadingLevel level: Int) -> PlatformFont {
        switch level {
        case 1:  return .systemFont(ofSize: 28, weight: .bold)
        case 2:  return .systemFont(ofSize: 22, weight: .semibold)
        case 3:  return .systemFont(ofSize: 18, weight: .semibold)
        default: return .systemFont(ofSize: 16, weight: .regular)
        }
    }
}
