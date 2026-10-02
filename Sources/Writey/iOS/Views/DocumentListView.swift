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
        }
        .listStyle(.plain)
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

private struct DocumentRow: View {
    let item: DocumentLibrary.Item
    let preview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                if !item.isDownloaded {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Downloading from iCloud")
                }
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let date = Self.format(item.modified)
        guard let preview else { return date }
        return "\(date)  \(preview.isEmpty ? "Empty" : preview)"
    }

    /// Today shows the time, yesterday says so, older shows the date — like Notes.
    private static func format(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

extension DocumentLibrary.Location {
    var isICloud: Bool {
        if case .iCloud = self { return true }
        return false
    }
}
