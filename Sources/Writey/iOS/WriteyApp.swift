import SwiftUI

@main
struct WriteyApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var auth = GoogleAuth()
    @StateObject private var library = DocumentLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(theme)
                .environmentObject(auth)
                .environmentObject(library)
                .preferredColorScheme(theme.preferredColorScheme)
        }
        .commands {
            TextEditingCommands()
            FormatCommands()
            SyncCommands()
            ViewCommands()
            ThemeCommands(theme: theme)
        }
        // No `Settings` scene on iOS; settings open as a sheet.
    }
}

/// The document list, with documents pushed on top. Writey runs its own
/// list rather than DocumentGroup's launcher: on iOS 27 that launcher's
/// close animation flies the document into the wrong corner.
private struct RootView: View {
    @State private var path: [DocumentRoute] = []
    @EnvironmentObject var library: DocumentLibrary

    var body: some View {
        NavigationStack(path: $path) {
            DocumentListView(path: $path)
                .navigationDestination(for: DocumentRoute.self) { route in
                    DocumentScreen(route: route)
                }
        }
        // "Open in Writey" from the Files app or another app's share sheet.
        .onOpenURL { url in
            let inLibrary = library.location.folder.map {
                url.deletingLastPathComponent().resolvingSymlinksInPath().path == $0.resolvingSymlinksInPath().path
            } ?? false
            path = [DocumentRoute(url: url, isExternal: !inLibrary)]
        }
        .alert("Something went wrong", isPresented: hasError) {
            Button("OK") { library.lastError = nil }
        } message: {
            Text(library.lastError ?? "")
        }
    }

    private var hasError: Binding<Bool> {
        Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })
    }
}
