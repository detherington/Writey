import Foundation

/// Thin wrapper around the Google Drive v3 REST endpoints we use.
///
/// Sync uses HTML as the lingua franca: we convert NSAttributedString
/// to/from HTML and let Google Docs do the heavy lifting on the cloud side.
/// HTML round-tripping isn't lossless for esoteric formatting but for a
/// minimalist editor (bold/italic/underline/headings/lists) it preserves
/// what matters and produces clean Google Docs.
struct DriveAPI {
    let accessToken: String

    struct FileMeta: Codable {
        let id: String
        let name: String
        let mimeType: String
        let modifiedTime: String?
        let headRevisionId: String?
    }

    // MARK: - Create

    /// Creates a new Google Doc populated from HTML, returning its file ID.
    func createDoc(name: String, html: String) async throws -> FileMeta {
        // multipart/related upload: metadata + body in a single POST.
        let boundary = "writey-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string:
            "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,mimeType,modifiedTime,headRevisionId"
        )!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let metadata: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.document"
        ]
        let metaData = try JSONSerialization.data(withJSONObject: metadata)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metaData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/html; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(html.data(using: .utf8)!)
        body.append("\r\n--\(boundary)--".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.throwIfError(data: data, response: response)
        return try JSONDecoder().decode(FileMeta.self, from: data)
    }

    // MARK: - Read

    /// Returns Drive metadata for a file.
    func metadata(fileID: String) async throws -> FileMeta {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?fields=id,name,mimeType,modifiedTime,headRevisionId")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.throwIfError(data: data, response: response)
        return try JSONDecoder().decode(FileMeta.self, from: data)
    }

    /// Exports a Google Doc as HTML.
    func exportAsHTML(fileID: String) async throws -> String {
        let url = URL(string:
            "https://www.googleapis.com/drive/v3/files/\(fileID)/export?mimeType=text/html"
        )!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.throwIfError(data: data, response: response)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Update

    /// Replaces the contents of an existing Google Doc with new HTML.
    func updateDocHTML(fileID: String, html: String) async throws -> FileMeta {
        // PATCH the file's media stream. Google converts on the fly because
        // the original mimeType is application/vnd.google-apps.document.
        var request = URLRequest(url: URL(string:
            "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media&fields=id,name,mimeType,modifiedTime,headRevisionId"
        )!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("text/html; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = html.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.throwIfError(data: data, response: response)
        return try JSONDecoder().decode(FileMeta.self, from: data)
    }

    // MARK: - Errors

    private static func throwIfError(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DriveAPIError.httpError(status: http.statusCode, body: body)
        }
    }

    enum DriveAPIError: LocalizedError {
        case httpError(status: Int, body: String)
        var errorDescription: String? {
            switch self {
            case .httpError(let status, let body):
                return "Drive API error \(status): \(body)"
            }
        }
    }
}
