import SwiftUI

struct ContentView: View {
    @ObservedObject var file: WriteyFile
    var startsEditing = false
    @StateObject private var reference: ReferenceController
    @Environment(\.replaceDocument) private var replaceDocument

    init(file: WriteyFile, startsEditing: Bool = false) {
        self.file = file
        self.startsEditing = startsEditing
        _reference = StateObject(wrappedValue: ReferenceController(
            fileURL: file.fileURL,
            defaultSide: WritingSettings.storedReferenceSide
        ))
    }

    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var auth: GoogleAuth
    @EnvironmentObject var library: DocumentLibrary
    @EnvironmentObject var writing: WritingSettings
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
    /// iPhone: the reference has the screen, in place of the writing.
    @State private var isShowingReference = false

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
            } else if !showsReferenceFullScreen {
                // Formatting has nothing to act on while the iPhone shows
                // the reference.
                EditorToolbar(
                    fileURL: fileURL,
                    showingSyncSheet: $showingSyncSheet,
                    showingSettingsSheet: $showingSettingsSheet
                )
                Divider().background(EditorPalette.chromeStroke(colorScheme))
            }

            // One editor instance in both modes, and with or without the
            // reference, so toggling either keeps the cursor, scroll
            // position, undo and the keyboard.
            EditorSplitLayout(
                showsReference: showsReference,
                side: reference.side,
                fraction: $reference.fraction,
                onResizeEnded: reference.commitFraction
            ) {
                RichTextEditor(
                    document: document,
                    revision: file.revision,
                    editor: editor,
                    typography: writing.typography,
                    focus: writing.focusMode ? writing.focusUnit : nil,
                    openAsReference: { url in
                        reference.open(.web(url))
                        withAnimation(.easeInOut(duration: 0.25)) { isShowingReference = true }
                    }
                ) { [file] in
                    file.updateChangeCount(.done)
                }
                .frame(maxWidth: writing.typography.columnWidth.maxWidth ?? .infinity)
                .frame(maxWidth: .infinity)
            } reference: {
                referencePane
            }
            // iPhone: no room side by side, so the reference covers the
            // writing. The editor stays underneath, keeping its place.
            .overlay {
                if showsReferenceFullScreen {
                    referencePane
                        .transition(.move(edge: .trailing))
                }
            }

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
        .navigationSubtitle(editor.wordCount.summary)
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
                    reference: reference,
                    showingSyncSheet: $showingSyncSheet,
                    showingSettingsSheet: $showingSettingsSheet,
                    isDistractionFree: $isDistractionFree,
                    isShowingReference: $isShowingReference,
                    writing: writing
                )
            }
        }
        .environmentObject(editor)
        .environmentObject(sync)
        .environmentObject(reference)
        .focusedSceneObject(editor)
        .focusedSceneObject(reference)
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
                .environmentObject(writing)
        }
        // Showing the reference on iPhone flips to it; closing it flips back.
        .onChange(of: reference.isVisible) {
            withAnimation(.easeInOut(duration: 0.25)) { isShowingReference = reference.isVisible }
        }
        .onChange(of: showsReferenceFullScreen) {
            if showsReferenceFullScreen { editor.unfocus() }
        }
        .onAppear {
            sync.textEditor = editor
            if startsEditing {
                // After the text view is in the window, or it can't take focus.
                Task { @MainActor in editor.focus() }
            }
        }
    }

    /// Side by side needs a regular-width window (iPad); distraction-free
    /// mode puts the reference away.
    private var showsReference: Bool {
        reference.isVisible && !isDistractionFree && sizeClass == .regular
    }

    private var showsReferenceFullScreen: Bool {
        reference.isVisible && isShowingReference && !isDistractionFree && sizeClass == .compact
    }

    private var referencePane: some View {
        ReferencePane(
            reference: reference,
            documents: library.items.filter { !ReferenceController.samePath($0.url, file.fileURL) },
            typography: writing.typography,
            onEditInstead: editInstead
        )
    }

    /// The reference becomes the document being written, and this one its
    /// reference.
    private func editInstead(_ url: URL) {
        reference.prepareSwap(to: url)
        replaceDocument(url)
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
