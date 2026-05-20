import SwiftUI

@main
struct WriteyApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var auth = GoogleAuth()

    init() {
        ThemeManager.applyOnLaunch()
    }

    var body: some Scene {
        DocumentGroup(newDocument: { WriteyDocument() }) { configuration in
            ContentView(document: configuration.document, fileURL: configuration.fileURL)
                .environmentObject(theme)
                .environmentObject(auth)
                .preferredColorScheme(theme.preferredColorScheme)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Writey") { NSApp.orderFrontStandardAboutPanel(nil) }
            }
            ThemeCommands(theme: theme)
            FormatCommands()
            ViewCommands()
            SyncCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(auth)
                .preferredColorScheme(theme.preferredColorScheme)
        }
    }
}
