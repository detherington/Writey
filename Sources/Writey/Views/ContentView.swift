import SwiftUI

struct ContentView: View {
    @ObservedObject var document: WriteyDocument
    var fileURL: URL?

    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var auth: GoogleAuth
    @StateObject private var editor = EditorController()
    @StateObject private var sync = SyncManager()
    @State private var showingSyncSheet = false
    @State private var isDistractionFree = false
    @State private var hostWindow: NSWindow?

    /// Max writing column width when in distraction-free mode. Mirrors what
    /// iA Writer / Bear / Ulysses do — keeps measure comfortable on wide
    /// monitors instead of letting prose sprawl edge-to-edge.
    private let distractionFreeColumnWidth: CGFloat = 720

    var body: some View {
        VStack(spacing: 0) {
            if !isDistractionFree {
                EditorToolbar(
                    document: document,
                    fileURL: fileURL,
                    showingSyncSheet: $showingSyncSheet
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
                    .padding(.vertical, 4)
                    .background(theme.chromeBackground)
            }
        }
        .background(theme.editorBackground)
        .environmentObject(editor)
        .environmentObject(sync)
        .frame(minWidth: 640, minHeight: 480)
        .sheet(isPresented: $showingSyncSheet) {
            GoogleSyncSheet(
                document: document,
                fileURL: fileURL
            )
            .environmentObject(theme)
            .environmentObject(auth)
            .environmentObject(sync)
        }
        .background(WindowAccessor { window in
            hostWindow = window
            theme.paint(window: window)
            applyDistractionFreeChrome(isDistractionFree, to: window)
        })
        .onChange(of: theme.theme) { _, _ in
            if let window = hostWindow { theme.paint(window: window) }
        }
        .onChange(of: isDistractionFree) { _, df in
            if let window = hostWindow {
                applyDistractionFreeChrome(df, to: window)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .writeyToggleDistractionFree)) { _ in
            // Only the key window responds, so toggling from the menu bar
            // affects just the focused document — not every open window.
            guard let window = hostWindow, window.isKeyWindow else { return }
            isDistractionFree.toggle()
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

    /// Makes the title bar transparent and hides the document title when
    /// entering distraction-free mode. Traffic lights stay so users can
    /// still close / minimize / zoom.
    ///
    /// We intentionally don't add `.fullSizeContentView` to the style mask
    /// — keeping the editor below the (now-invisible) title bar means the
    /// traffic lights never overlap typed text.
    private func applyDistractionFreeChrome(_ on: Bool, to window: NSWindow) {
        window.titlebarAppearsTransparent = on
        window.titleVisibility = on ? .hidden : .visible
        window.isMovableByWindowBackground = on
        theme.paint(window: window)
    }
}

/// Tiny helper that hands us the hosting NSWindow once it exists, so we can
/// override its backgroundColor and chrome.
private struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { callback(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { callback(window) }
        }
    }
}
