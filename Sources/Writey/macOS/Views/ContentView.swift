import SwiftUI

struct ContentView: View {
    @ObservedObject var document: WriteyDocument
    var fileURL: URL?

    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var auth: GoogleAuth
    @EnvironmentObject var writing: WritingSettings
    @EnvironmentObject var library: DocumentLibrary
    @Environment(\.openDocument) private var openDocument
    @StateObject private var reference: ReferenceController

    init(document: WriteyDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _reference = StateObject(wrappedValue: ReferenceController(
            fileURL: fileURL,
            defaultSide: WritingSettings.storedReferenceSide
        ))
    }
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

    var body: some View {
        VStack(spacing: 0) {
            if !isDistractionFree {
                EditorToolbar(fileURL: fileURL, showingSyncSheet: $showingSyncSheet)
                Divider().background(EditorPalette.chromeStroke(colorScheme))
            }

            // One editor instance in both modes, and with or without the
            // reference, so toggling either keeps the cursor, scroll
            // position and undo history. Column width keeps line length
            // comfortable on wide windows.
            EditorSplitLayout(
                showsReference: showsReference,
                side: reference.side,
                fraction: $reference.fraction,
                onResizeEnded: reference.commitFraction
            ) {
                RichTextEditor(
                    document: document,
                    editor: editor,
                    typography: writing.typography,
                    focus: writing.focusMode ? writing.focusUnit : nil
                )
                .frame(maxWidth: writing.typography.columnWidth.maxWidth ?? .infinity)
                .frame(maxWidth: .infinity)
            } reference: {
                ReferencePane(
                    reference: reference,
                    documents: library.items.filter { item in
                        fileURL.map { !ReferenceController.samePath(item.url, $0) } ?? true
                    },
                    typography: writing.typography,
                    onEditInstead: editInstead
                )
            }

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
        .navigationSubtitle(editor.wordCount.summary)
        .environmentObject(editor)
        .environmentObject(sync)
        .environmentObject(reference)
        .focusedSceneObject(editor)
        .focusedSceneObject(reference)
        .focusedSceneValue(\.syncSheetPresented, $showingSyncSheet)
        .focusedSceneValue(\.distractionFree, $isDistractionFree)
        .frame(minWidth: showsReference ? 780 : 640, minHeight: 480)
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
        .onChange(of: showsReference) { if showsReference { makeRoomForReference() } }
        // Rename or Save As: the reference memory moves with the document.
        .onChange(of: fileURL) { reference.documentMoved(to: fileURL) }
        .onAppear { sync.textEditor = editor }
    }

    /// Distraction-free mode puts the reference away.
    private var showsReference: Bool {
        reference.isVisible && !isDistractionFree
    }

    /// A window too narrow for two panes widens, staying on screen.
    private func makeRoomForReference() {
        guard let window = hostWindow, window.frame.width < 1000,
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        frame.size.width = min(1200, visible.width)
        frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        window.setFrame(frame, display: true, animate: true)
    }

    /// The reference opens for editing, with this document as its
    /// reference, and this window closes: the two swap places.
    private func editInstead(_ url: URL) {
        reference.prepareSwap(to: url)
        Task {
            do {
                try await openDocument(at: url)
                hostWindow?.performClose(nil)
            } catch {
                NSSound.beep()
            }
        }
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
