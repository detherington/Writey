import SwiftUI

struct ContentView: View {
    @ObservedObject var file: WriteyFile
    var startsEditing = false

    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var auth: GoogleAuth
    @EnvironmentObject var library: DocumentLibrary
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass
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

    @State private var showingRename = false
    @State private var newName = ""

    private var document: WriteyDocument { file.model }
    private var fileURL: URL? { file.fileURL }

    var body: some View {
        VStack(spacing: 0) {
            if isDistractionFree {
                // A row of its own: floated over the editor, the button's
                // taps went to the text view underneath.
                HStack {
                    Spacer()
                    exitButton
                }
            } else {
                EditorToolbar(
                    fileURL: fileURL,
                    showingSyncSheet: $showingSyncSheet,
                    showingSettingsSheet: $showingSettingsSheet
                )
                Divider().background(EditorPalette.chromeStroke(colorScheme))
            }

            // One editor instance in both modes, so toggling distraction-free
            // keeps the cursor, scroll position, undo and the keyboard.
            RichTextEditor(document: document, revision: file.revision, editor: editor) { [file] in
                file.updateChangeCount(.done)
            }
            .frame(maxWidth: isDistractionFree ? Self.distractionFreeColumnWidth : .infinity)
            .frame(maxWidth: .infinity)

            if !isDistractionFree, let status = file.saveError ?? sync.statusLine {
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
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        // An alert rather than the system's inline title rename, which
        // committed partway through typing.
        .toolbarTitleMenu {
            Button {
                newName = file.name
                showingRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }
        .alert("Rename Document", isPresented: $showingRename) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let url = file.fileURL
                let name = newName
                Task { await library.rename(url, to: name) }
            }
        }
        .toolbar {
            // At compact width the formatting bar has no room for these.
            if sizeClass == .compact {
                DocumentActions(
                    fileURL: fileURL,
                    sync: sync,
                    showingSyncSheet: $showingSyncSheet,
                    showingSettingsSheet: $showingSettingsSheet,
                    isDistractionFree: $isDistractionFree
                )
            }
        }
        .environmentObject(editor)
        .environmentObject(sync)
        .focusedSceneObject(editor)
        .focusedSceneValue(\.syncSheetPresented, $showingSyncSheet)
        .focusedSceneValue(\.distractionFree, $isDistractionFree)
        // Distraction-free hides the navigation bar, the status bar and the
        // home indicator.
        .toolbar(isDistractionFree ? .hidden : .visible, for: .navigationBar)
        .statusBarHidden(isDistractionFree)
        .persistentSystemOverlays(isDistractionFree ? .hidden : .automatic)
        .animation(.easeInOut(duration: 0.2), value: isDistractionFree)
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
        .onAppear {
            sync.textEditor = editor
            if startsEditing {
                // After the text view is in the window, or it can't take focus.
                Task { @MainActor in editor.focus() }
            }
        }
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
        .padding(.top, 8)
        .padding(.trailing, 16)
        .accessibilityLabel("Exit distraction-free mode")
        .keyboardShortcut(.escape, modifiers: [])
    }
}
