import SwiftUI

@main
struct WriteyApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var auth = GoogleAuth()
    @StateObject private var library = DocumentLibrary()

    init() {
        ThemeManager.applyOnLaunch()
    }

    var body: some Scene {
        // Writey's home: the Writey folder's documents, shown at launch
        // instead of the system Open panel. Window ▸ Writey brings it back.
        Window("Writey", id: LibraryView.windowID) {
            LibraryView()
                .environmentObject(theme)
                .environmentObject(library)
                .preferredColorScheme(theme.preferredColorScheme)
        }
        .defaultSize(width: 560, height: 640)
        .defaultLaunchBehavior(.presented)

        DocumentGroup(newDocument: { WriteyDocument() }) { configuration in
            ContentView(document: configuration.document, fileURL: configuration.fileURL)
                .environmentObject(theme)
                .environmentObject(auth)
                .preferredColorScheme(theme.preferredColorScheme)
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Writey") { NSApp.orderFrontStandardAboutPanel(nil) }
            }
            NewDocumentCommands(library: library)
            // Find (⌘F, wired to NSTextView's find bar), spelling, substitutions.
            TextEditingCommands()
            FormatCommands()
            SyncCommands()
            ViewCommands()
            ThemeCommands(theme: theme)
        }

        Settings {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(auth)
                .preferredColorScheme(theme.preferredColorScheme)
        }
    }
}
