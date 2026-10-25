import Foundation
import UniformTypeIdentifiers

/// What the reference pane shows beside the document being written.
enum ReferenceSource: Codable, Hashable {
    /// Another document, shown read-only.
    case document(URL)
    case web(URL)
    /// A PDF, image or other file, previewed. Added files are kept in the
    /// Writey folder's References folder, so every device has them.
    case file(URL)

    var title: String {
        switch self {
        case .document(let url), .file(let url): return url.deletingPathExtension().lastPathComponent
        case .web(let url): return url.host() ?? url.absoluteString
        }
    }

    /// Where a document or file reference is on disk; nil for a web page.
    var fileURL: URL? {
        switch self {
        case .document(let url), .file(let url): return url
        case .web: return nil
        }
    }

    var isFile: Bool {
        if case .file = self { return true }
        return false
    }

    var systemImage: String {
        switch self {
        case .document: return "doc.text"
        case .web: return "globe"
        case .file(let url): return Self.systemImage(forFile: url)
        }
    }

    static func systemImage(forFile url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) || type.conforms(to: .audio) { return "play.rectangle" }
        return "doc"
    }

    /// The reference for a file: a Writey document, or anything else.
    static func forFile(_ url: URL) -> ReferenceSource {
        DocumentLibrary.isDocument(url) ? .document(url) : .file(url)
    }

    /// Two sources are the same if they show the same page, or the same
    /// file however its path is spelled.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }

    func hash(into hasher: inout Hasher) { hasher.combine(identity) }

    private var identity: String {
        switch self {
        case .document(let url): return "document:" + StableFilePath.string(for: url)
        case .web(let url): return "web:" + url.absoluteString
        case .file(let url): return "file:" + StableFilePath.string(for: url)
        }
    }

    // Documents and files are saved by StableFilePath, so they're found
    // again after the app's container moves.
    private enum CodingKeys: String, CodingKey { case document, web, file }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let path = try container.decodeIfPresent(String.self, forKey: .document) {
            self = .document(StableFilePath.url(for: path))
        } else if let path = try container.decodeIfPresent(String.self, forKey: .file) {
            self = .file(StableFilePath.url(for: path))
        } else {
            self = .web(try container.decode(URL.self, forKey: .web))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .document(let url): try container.encode(StableFilePath.string(for: url), forKey: .document)
        case .web(let url): try container.encode(url, forKey: .web)
        case .file(let url): try container.encode(StableFilePath.string(for: url), forKey: .file)
        }
    }
}

/// A file's path written so it still finds the file after the app's data
/// container moves, which iOS does on reinstall and on some updates: paths
/// inside the container are saved relative to it, as "~/Documents/…".
/// Also the key for "same file", ignoring the /private prefix on /var.
enum StableFilePath {
    static func string(for url: URL) -> String {
        let path = normalized(url.path)
        let home = normalized(NSHomeDirectory())
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    static func url(for string: String) -> URL {
        if string.hasPrefix("~/") {
            return URL(fileURLWithPath: NSHomeDirectory() + string.dropFirst())
        }
        return URL(fileURLWithPath: string)
    }

    private static func normalized(_ path: String) -> String {
        let path = (path as NSString).standardizingPath
        return path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }
}

/// Which side of the writing the reference pane sits on.
enum ReferenceSide: String, Codable, CaseIterable, Identifiable {
    case right, left
    var id: String { rawValue }
    var label: String { self == .right ? "Right" : "Left" }
    var opposite: ReferenceSide { self == .right ? .left : .right }
}
