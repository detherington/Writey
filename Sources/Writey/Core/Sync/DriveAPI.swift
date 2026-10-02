import Foundation

/// Thin wrapper around the Google Drive v3 REST endpoints we use.
///
/// Sync uses HTML as the lingua franca: we convert NSAttributedString
/// to/from HTML and let Google Docs do the heavy lifting on the cloud side.
struct DriveAPI {
    /// Returns an access token; `true` forces a refresh.
    typealias TokenProvider = (_ forceRefresh: Bool) async throws -> String

    let token: TokenProvider

    struct FileMeta: Codable {
        let id: String
        let name: String
        let mimeType: String
        let modifiedTime: String?
    }

    private static let metaFields = "id,name,mimeType,modifiedTime"

    // MARK: - Create

    /// Creates a new Google Doc populated from HTML.
    func createDoc(name: String, html: String) async throws -> FileMeta {
        let boundary = "writey-\(UUID().uuidString)"
        let metadata = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "mimeType": "application/vnd.google-apps.document"
        ])
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
        body.append(metadata)
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n".utf8))
        body.append(Data(html.utf8))
        body.append(Data("\r\n--\(boundary)--".utf8))

        let data = try await send { accessToken in
            var request = URLRequest(url: URL(string:
                "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=\(Self.metaFields)"
            )!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            return request
        }
        return try JSONDecoder().decode(FileMeta.self, from: data)
    }

    // MARK: - Read

    /// Exports a Google Doc as HTML.
    func exportAsHTML(fileID: String) async throws -> String {
        let data = try await send { accessToken in
            var request = URLRequest(url: URL(string:
                "https://www.googleapis.com/drive/v3/files/\(fileID)/export?mimeType=text/html"
            )!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            return request
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Update

    /// Replaces the contents of an existing Google Doc with new HTML. Drive
    /// converts on the fly because the file's mimeType is a Google Doc.
    func updateDocHTML(fileID: String, html: String) async throws -> FileMeta {
        let data = try await send { accessToken in
            var request = URLRequest(url: URL(string:
                "https://www.googleapis.com/upload/drive/v3/files/\(fileID)?uploadType=media&fields=\(Self.metaFields)"
            )!)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("text/html; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(html.utf8)
            return request
        }
        return try JSONDecoder().decode(FileMeta.self, from: data)
    }

    // MARK: - Transport

    /// Sends a request, retrying once with a freshly refreshed token if
    /// Google says the current one is no longer valid.
    private func send(_ makeRequest: (String) -> URLRequest) async throws -> Data {
        var (data, response) = try await URLSession.shared.data(for: makeRequest(try await token(false)))
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            (data, response) = try await URLSession.shared.data(for: makeRequest(try await token(true)))
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw DriveAPIError(status: http.statusCode, googleMessage: Self.googleMessage(in: data))
        }
        return data
    }

    /// Pulls `error.message` out of Google's JSON error envelope.
    private static func googleMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    struct DriveAPIError: LocalizedError {
        let status: Int
        let googleMessage: String?

        var errorDescription: String? {
            switch status {
            case 401:
                return "Google rejected Writey's sign-in. Sign out and back in from Settings."
            case 403:
                return "Google Drive denied access" + (googleMessage.map { ": \($0)" } ?? ".")
            case 404:
                return "Writey couldn't find that Google Doc. It may have been deleted, or this Google account can't open it."
            case 429, 500...:
                return "Google Drive is busy right now. Try again in a minute."
            default:
                return googleMessage ?? "Google Drive returned an error (\(status))."
            }
        }
    }
}
