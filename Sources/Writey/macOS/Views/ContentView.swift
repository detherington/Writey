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
        manager.conflictResolver = MacConflictResolver()
        return manager
    }()
    @State private var showingSyncSheet = false
    @State private var isDistractionFree = false
    @State private var hostWindow: NSWindow?

    /// Writing-column width in distraction-free mode, as in iA Writer /
    /// Ulysses: keeps line length comfortable on wide displays.
    private static let distractionFreeColumnWidth: CGFloat = 720

    var body: some View {
        VStack(spacing: 0) {
            if !isDistractionFree {
                EditorToolbar(fileURL: fileURL, showingSyncSheet: $showingSyncSheet)
                Divider().background(EditorPalette.chromeStroke(colorScheme))
            }

            // One editor instance in both modes, so toggling distraction-free
            // keeps the cursor, scroll position and undo history.
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
                    .padding(.vertical, 4)
                    .background(EditorPalette.chromeBackground(colorScheme))
            }
        }
        .background(EditorPalette.background(colorScheme))
        .environmentObject(editor)
        .environmentObject(sync)
        .focusedSceneObject(editor)
        .focusedSceneValue(\.syncSheetPresented, $showingSyncSheet)
        .focusedSceneValue(\.distractionFree, $isDistractionFree)
        .frame(minWidth: 640, minHeight: 480)
        .sheet(isPresented: $showingSyncSheet) {
            GoogleSyncSheet(document: document, fileURL: fileURL)
                .environmentObject(auth)
                .environmentObject(sync)
        }
        .background(WindowAccessor { window in
            hostWindow = window
            applyWindowChrome()
        })
        .onChange(of: colorScheme) { applyWindowChrome() }
        .onChange(of: isDistractionFree) { applyWindowChrome() }
        .onAppear { sync.textEditor = editor }
    }

    /// Paints the window to match the editor surface, and makes the title
    /// bar transparent with no title in distraction-free mode. Traffic lights
    /// stay. No `.fullSizeContentView`, so they never overlap the text.
    private func applyWindowChrome() {
        guard let window = hostWindow else { return }
        theme.paint(window: window, scheme: colorScheme)
        window.titlebarAppearsTransparent = isDistractionFree
        window.titleVisibility = isDistractionFree ? .hidden : .visible
        window.isMovableByWindowBackground = isDistractionFree
    }
}

/// Reports the hosting NSWindow once it exists.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: ReportingView, context: Context) {
        view.onWindow = onWindow
    }

    final class ReportingView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Deferred: this can fire mid view-update, where setting @State
            // isn't allowed.
            DispatchQueue.main.async { [weak self] in self?.onWindow?(window) }
        }
    }
}
