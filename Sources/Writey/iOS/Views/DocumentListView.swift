import SwiftUI
import UniformTypeIdentifiers

/// Where the navigation stack can go from the list.
struct DocumentRoute: Hashable {
    let url: URL
    /// New documents open with the keyboard up.
    var isNew = false
    /// Opened from the Files app or "Open from Files…", outside Writey's folder.
    var isExternal = false
}

/// Writey's home screen: every document in the Writey folder, newest first.
struct DocumentListView: View {
    @Binding var path: [DocumentRoute]

    @EnvironmentObject var library: DocumentLibrary
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var auth: GoogleAuth
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var renaming: DocumentLibrary.Item?
    @State private var newName = ""
    @State private var deleting: DocumentLibrary.Item?
    @State private var showingImporter = false
    @State private var showingSettings = false

    var body: some View {
        List {
            if case .local = library.location {
                Text("iCloud Drive is off, so documents are saved on this device only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .listRowBackground(EditorPalette.background(colorScheme))
            }
            ForEach(filteredItems) { item in
                NavigationLink(value: DocumentRoute(url: item.url)) {
                    DocumentRow(item: item, preview: library.previews[item.url])
                }
                .swipeActions {
                    Button(role: .destructive) { deleting = item } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button { startRenaming(item) } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                }
                .contextMenu {
                    Button { startRenaming(item) } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { deleting = item } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .listRowBackground(EditorPalette.background(colorScheme))
        }
        .listStyle(.plain)
        // True black in dark mode, like the editor; the system background
        // turns dark gray in elevated contexts such as iPad multitasking.
        .scrollContentBackground(.hidden)
        .background(EditorPalette.background(colorScheme))
        .overlay { emptyState }
        .searchable(text: $searchText)
        .navigationTitle("Writey")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button { showingImporter = true } label: {
                        Label("Open from Files…", systemImage: "folder")
                    }
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                Button { createDocument() } label: {
                    Label("New Document", systemImage: "plus")
                }
                .keyboardShortcut("n")
            }
        }
        .refreshable { library.refresh() }
        .onAppear { library.refresh() }
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
            isPresented: isDeleting,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let item = deleting else { return }
                Task { await library.delete(item.url) }
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: Self.openableTypes) { result in
            if case .success(let url) = result {
                path.append(DocumentRoute(url: url, isExternal: true))
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(theme)
                .environmentObject(auth)
        }
    }

    static let openableTypes: [UTType] = [.rtf, .plainText] + [UTType("net.daringfireball.markdown")].compactMap { $0 }

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
                     : "New documents are saved on this device.")
            } actions: {
                Button("New Document") { createDocument() }
            }
        } else if !searchText.isEmpty && filteredItems.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func createDocument() {
        Task {
            if let url = await library.createDocument() {
                path.append(DocumentRoute(url: url, isNew: true))
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
}
