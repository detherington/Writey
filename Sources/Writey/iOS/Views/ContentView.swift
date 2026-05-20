import SwiftUI

struct ContentView: View {
    @ObservedObject var document: WriteyDocument
    var fileURL: URL?

    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var auth: GoogleAuth
    @StateObject private var editor = EditorController()
    @StateObject private var sync: SyncManager = {
        let manager = SyncManager()
        manager.conflictResolver = IOSConflictResolver()
        return manager
    }()

    @State private var showingSyncSheet = false
    @State private var showingSettingsSheet = false

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(
                document: document,
                fileURL: fileURL,
                showingSyncSheet: $showingSyncSheet,
                showingSettingsSheet: $showingSettingsSheet
            )
            Divider().background(theme.chromeStroke)

            RichTextEditor(text: $document.attributedText)
                .background(theme.editorBackground)
                .environmentObject(theme)
                .environmentObject(editor)

            if let status = sync.statusLine {
                Divider().background(theme.chromeStroke)
                Text(status)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(theme.chromeBackground)
            }
        }
        .background(theme.editorBackground)
        .environmentObject(editor)
        .environmentObject(sync)
        .sheet(isPresented: $showingSyncSheet) {
            GoogleSyncSheet(document: document, fileURL: fileURL)
                .environmentObject(theme)
                .environmentObject(auth)
                .environmentObject(sync)
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(auth)
        }
    }
}
