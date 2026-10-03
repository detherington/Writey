import SwiftUI
import AppKit

/// Writey's home window on the Mac: every document in the Writey folder,
/// newest first — the same list as the iOS home screen. Opens at launch in
/// place of the system Open panel, and paints true black in dark mode like
/// the editor.
struct LibraryView: View {
    static let windowID = "library"

    @EnvironmentObject var library: DocumentLibrary
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openDocument) private var openDocument

    @State private var searchText = ""
    @State private var selection = Set<URL>()
    @State private var renaming: DocumentLibrary.Item?
    @State private var newName = ""
    @State private var deleting: DocumentLibrary.Item?
    @State private var hostWindow: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            header
            // Large title over the list, as on iOS, even though the title
            // bar says it too.
            Text("Writey")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 2)
            list
        }
        .background(EditorPalette.background(colorScheme))
        .frame(minWidth: 420, minHeight: 320)
        // Title bar shows the window's color, so it's black too.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(WindowAccessor { window in
            hostWindow = window
            theme.paint(window: window, scheme: colorScheme)
        })
        .onChange(of: colorScheme) {
            if let hostWindow { theme.paint(window: hostWindow, scheme: colorScheme) }
        }
        // Without iCloud there's no live query, so re-read the folder when
        // the window comes forward (e.g. after closing a document).
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            library.refresh()
        }
        .alert("Something went wrong", isPresented: hasError) {
            Button("OK") { library.lastError = nil }
        } message: {
            Text(library.lastError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            .frame(maxWidth: 260)

            Spacer()

            Button {
                NSDocumentController.shared.openDocument(nil)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open a document from anywhere on your Mac")

            Button {
                createDocument()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Document")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(EditorPalette.chromeBackground(colorScheme))
    }

    private var list: some View {
        List(selection: $selection) {
            if case .local = library.location {
                Text("iCloud Drive is off, so documents are saved on this Mac only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                LibraryRow(
                    item: item,
                    preview: library.previews[item.url],
                    showsTopLine: index == 0 && !isShowingLocalNote
                )
                .tag(item.url)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: URL.self) { urls in
            if let item = item(for: urls) {
                Button("Open") { open(item.url) }
                Button("Rename…") { startRenaming(item) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                Divider()
                Button("Delete…", role: .destructive) { deleting = item }
            }
        } primaryAction: { urls in
            // Double-click or Return.
            urls.forEach(open)
        }
        .onDeleteCommand {
            if let item = item(for: selection) { deleting = item }
        }
        .overlay { emptyState }
        .alert("Rename Document", isPresented: isRenaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                guard let item = renaming else { return }
                let name = newName
                Task { await library.rename(item.url, to: name) }
            }
        }
        .confirmationDialog(
            deleting.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: isDeleting
        ) {
            Button("Delete", role: .destructive) {
                guard let item = deleting else { return }
                Task { await library.delete(item.url) }
            }
        }
    }

    private var filteredItems: [DocumentLibrary.Item] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return library.items }
        return library.items.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || (library.previews[$0.url]?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if library.hasLoaded && library.items.isEmpty {
            ContentUnavailableView {
                Label("No documents yet", systemImage: "doc.text")
            } description: {
                Text(library.location == .resolving || library.location.isICloud
                     ? "New documents are saved to Writey in iCloud Drive."
                     : "New documents are saved on this Mac.")
            } actions: {
                Button("New Document") { createDocument() }
            }
        } else if !searchText.isEmpty && filteredItems.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private var isShowingLocalNote: Bool {
        if case .local = library.location { return true }
        return false
    }

    private func item(for urls: Set<URL>) -> DocumentLibrary.Item? {
        guard urls.count == 1, let url = urls.first else { return nil }
        return library.items.first { $0.url == url }
    }

    private func open(_ url: URL) {
        Task {
            do {
                try await openDocument(at: url)
            } catch {
                library.lastError = "Couldn't open “\(url.deletingPathExtension().lastPathComponent)”: \(error.localizedDescription)"
            }
        }
    }

    private func createDocument() {
        Task {
            if let url = await library.createDocument() {
                selection = [url]
                open(url)
            }
        }
    }

    private func startRenaming(_ item: DocumentLibrary.Item) {
        newName = item.name
        renaming = item
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var hasError: Binding<Bool> {
        Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })
    }
}

/// A document in the library, with hairlines like the iOS list: one under
/// every document and one above the first. The Mac's List only draws lines
/// between rows, so the row draws its own.
struct LibraryRow: View {
    let item: DocumentLibrary.Item
    let preview: String?
    let showsTopLine: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        DocumentRow(item: item, preview: preview)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { if showsTopLine { line } }
            .overlay(alignment: .bottom) { line }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }

    private var line: some View {
        Rectangle()
            .fill(EditorPalette.chromeStroke(colorScheme))
            .frame(height: 1 / displayScale)
    }
}

/// File ▸ New Document (⌘N) makes the document in the Writey folder, like
/// the library's + button, instead of an untitled one that isn't anywhere yet.
struct NewDocumentCommands: Commands {
    @ObservedObject var library: DocumentLibrary
    @Environment(\.openDocument) private var openDocument

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Document") {
                Task {
                    guard let url = await library.createDocument() else { return }
                    do {
                        try await openDocument(at: url)
                    } catch {
                        library.lastError = "Couldn't open the new document: \(error.localizedDescription)"
                    }
                }
            }
            .keyboardShortcut("n")
        }
    }
}
