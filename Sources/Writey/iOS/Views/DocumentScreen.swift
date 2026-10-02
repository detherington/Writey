import SwiftUI

/// Opens a document for the editor and saves and closes it on the way out.
struct DocumentScreen: View {
    let route: DocumentRoute

    @StateObject private var opener = DocumentOpener()
    @EnvironmentObject var library: DocumentLibrary

    var body: some View {
        Group {
            switch opener.state {
            case .opening:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .open(let file):
                ContentView(file: file, startsEditing: route.isNew)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't open this document", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
            }
        }
        .task { await opener.open(route) }
        .onDisappear {
            if case .open(let file) = opener.state {
                library.updatePreview(for: file.fileURL, text: file.model.attributedText.string)
            }
            Task {
                await opener.close()
                library.refresh()
            }
        }
    }
}

@MainActor
final class DocumentOpener: ObservableObject {
    enum State {
        case opening
        case open(WriteyFile)
        case failed(String)
    }

    @Published private(set) var state: State = .opening
    private var file: WriteyFile?
    private var scopedURL: URL?

    func open(_ route: DocumentRoute) async {
        guard file == nil else { return }
        // Files from outside Writey's folder need their sandbox access
        // switched on for as long as they're open.
        if route.isExternal, route.url.startAccessingSecurityScopedResource() {
            scopedURL = route.url
        }
        let file = WriteyFile(fileURL: route.url)
        self.file = file
        if await file.open() {
            state = .open(file)
        } else {
            state = .failed("It may have been moved or deleted, or it isn't a format Writey can read.")
        }
    }

    func close() async {
        if let file, file.documentState != .closed {
            _ = await file.close()
        }
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
}
