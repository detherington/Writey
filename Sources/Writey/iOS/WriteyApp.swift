import SwiftUI

@main
struct WriteyApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var auth = GoogleAuth()

    var body: some Scene {
        DocumentGroup(newDocument: { WriteyDocument() }) { configuration in
            ContentView(document: configuration.document, fileURL: configuration.fileURL)
                .environmentObject(theme)
                .environmentObject(auth)
                .preferredColorScheme(theme.preferredColorScheme)
        }
        .commands {
            ThemeCommands(theme: theme)
            ViewCommands()
        }
        // No `Settings` scene on iOS — settings are reached via an in-app
        // sheet from the toolbar.
    }
}
