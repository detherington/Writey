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
    @State private var isDistractionFree = false

    /// Max writing column width when in distraction-free mode. Mirrors the
    /// Mac version exactly so a 13" iPad in landscape gets the same
    /// comfortable measure as a 27" display.
    private let distractionFreeColumnWidth: CGFloat = 720

    var body: some View {
        VStack(spacing: 0) {
            if !isDistractionFree {
                EditorToolbar(
                    document: document,
                    fileURL: fileURL,
                    showingSyncSheet: $showingSyncSheet,
                    showingSettingsSheet: $showingSettingsSheet
                )
                Divider().background(theme.chromeStroke)
            }

            editorArea

            if !isDistractionFree, let status = sync.statusLine {
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
        // Hide the navigation bar DocumentGroup wraps us in, the status
        // bar, and the home indicator when we go distraction-free. The
        // editor's UITextView still gets all touch events — only the
        // OS-rendered chrome disappears.
        .toolbar(isDistractionFree ? .hidden : .visible, for: .navigationBar)
        .statusBar(hidden: isDistractionFree)
        .persistentSystemOverlays(isDistractionFree ? .hidden : .automatic)
        .overlay(alignment: .topTrailing) {
            if isDistractionFree {
                exitButton
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .writeyToggleDistractionFree)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isDistractionFree.toggle()
            }
        }
    }

    @ViewBuilder
    private var editorArea: some View {
        if isDistractionFree {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                RichTextEditor(text: $document.attributedText)
                    .frame(maxWidth: distractionFreeColumnWidth)
                Spacer(minLength: 0)
            }
            .background(theme.editorBackground)
            .environmentObject(theme)
            .environmentObject(editor)
        } else {
            RichTextEditor(text: $document.attributedText)
                .background(theme.editorBackground)
                .environmentObject(theme)
                .environmentObject(editor)
        }
    }

    /// Discreet escape hatch for touch users — sits at low opacity so it
    /// doesn't intrude, brightens on hover (iPad pointer) or press.
    private var exitButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isDistractionFree = false
            }
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
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
