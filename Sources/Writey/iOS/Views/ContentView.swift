import SwiftUI

struct ContentView: View {
    @ObservedObject var document: WriteyDocument
    var fileURL: URL?

    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var auth: GoogleAuth
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var editor = EditorController()
    @StateObject private var sync: SyncManager = {
        let manager = SyncManager()
        manager.conflictResolver = IOSConflictResolver()
        return manager
    }()

    @State private var showingSyncSheet = false
    @State private var showingSettingsSheet = false
    @State private var isDistractionFree = false

    /// Same writing-column width as the Mac.
    private static let distractionFreeColumnWidth: CGFloat = 720

    var body: some View {
        VStack(spacing: 0) {
            if !isDistractionFree {
                EditorToolbar(
                    fileURL: fileURL,
                    showingSyncSheet: $showingSyncSheet,
                    showingSettingsSheet: $showingSettingsSheet
                )
                Divider().background(EditorPalette.chromeStroke(colorScheme))
            }

            // One editor instance in both modes, so toggling distraction-free
            // keeps the cursor, scroll position, undo and the keyboard.
            RichTextEditor(document: document, editor: editor)
                .frame(maxWidth: isDistractionFree ? Self.distractionFreeColumnWidth : .infinity)
                .frame(maxWidth: .infinity)

            if !isDistractionFree, let status = sync.statusLine {
                Divider().background(EditorPalette.chromeStroke(colorScheme))
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(EditorPalette.chromeBackground(colorScheme))
            }
        }
        .background(EditorPalette.background(colorScheme))
        .environmentObject(editor)
        .environmentObject(sync)
        .focusedSceneObject(editor)
        .focusedSceneValue(\.syncSheetPresented, $showingSyncSheet)
        .focusedSceneValue(\.distractionFree, $isDistractionFree)
        // Distraction-free hides the nav bar DocumentGroup wraps us in, the
        // status bar and the home indicator.
        .toolbar(isDistractionFree ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(isDistractionFree)
        .persistentSystemOverlays(isDistractionFree ? .hidden : .automatic)
        .animation(.easeInOut(duration: 0.2), value: isDistractionFree)
        .overlay(alignment: .topTrailing) {
            if isDistractionFree { exitButton }
        }
        .sheet(isPresented: $showingSyncSheet) {
            GoogleSyncSheet(document: document, fileURL: fileURL)
                .environmentObject(auth)
                .environmentObject(sync)
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(auth)
        }
        .onAppear { sync.textEditor = editor }
    }

    /// Discreet way out for touch users: low opacity, lifts under the iPad
    /// pointer. Escape also exits.
    private var exitButton: some View {
        Button {
            isDistractionFree = false
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(12)
                .background(.thinMaterial, in: Circle())
        }
        .opacity(0.35)
        .hoverEffect(.lift)
        .padding(.top, 20)
        .padding(.trailing, 20)
        .accessibilityLabel("Exit distraction-free mode")
        .keyboardShortcut(.escape, modifiers: [])
    }
}
