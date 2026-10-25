import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// The reference beside the writing: another document, read-only, a web
/// page, or a PDF or other file. A header like the editor's toolbar holds
/// the address or title, the source menu, and close. Files and web links
/// can be dropped on it.
struct ReferencePane: View {
    @ObservedObject var reference: ReferenceController
    /// Writey documents that can be opened here (not the one being written).
    let documents: [DocumentLibrary.Item]
    let typography: Typography
    /// Opens the reference document for editing, swapping it with the writing.
    let onEditInstead: (URL) -> Void

    @EnvironmentObject var library: DocumentLibrary
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var address = ""
    @FocusState private var addressFocused: Bool
    @State private var isAddingFile = false
    @State private var addFileError: String?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(EditorPalette.chromeStroke(colorScheme))
            if reference.isInRecentlyDeleted {
                Label("This document is in Recently Deleted.", systemImage: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(EditorPalette.background(colorScheme))
        .onAppear { address = reference.webAddress }
        .onChange(of: reference.source) {
            if !addressFocused { address = reference.webAddress }
        }
        .onChange(of: reference.isEnteringAddress) {
            if reference.isEnteringAddress { addressFocused = true }
        }
        .onChange(of: reference.page?.url) {
            if !addressFocused { address = reference.webAddress }
            reference.pageDidNavigate()
        }
        .fileImporter(isPresented: $isAddingFile, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { addFile(url) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            if url.isFileURL {
                addFile(url)
            } else if ["http", "https"].contains(url.scheme?.lowercased()) {
                reference.open(.web(url))
            } else {
                return false
            }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .alert("Couldn't Add File", isPresented: Binding(
            get: { addFileError != nil },
            set: { if !$0 { addFileError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(addFileError ?? "")
        }
    }

    /// A file picked or dropped: copied into the References folder, so it
    /// syncs with the documents, then shown.
    private func addFile(_ url: URL) {
        Task {
            do {
                let copy = try await library.addReferenceFile(from: url)
                reference.open(.forFile(copy))
            } catch {
                addFileError = error.localizedDescription
            }
        }
    }

    // MARK: - Header

    private var showsAddressField: Bool {
        switch reference.source {
        case nil, .web?: return true
        case .document?, .file?: return reference.isEnteringAddress
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if showsAddressField {
                if case .web? = reference.source, let page = reference.page {
                    WebNavigationButtons(page: page)
                }
                addressField
            } else if let source = reference.source {
                Image(systemName: source.systemImage)
                    .foregroundStyle(.secondary)
                Text(source.title)
                    .font(.headline)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if case .document(let url) = source, !reference.isInRecentlyDeleted {
                    editInsteadButton(url)
                }
            }
            sourceMenu
            Button {
                reference.close()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close Reference")
            .accessibilityLabel("Close Reference")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(EditorPalette.chromeBackground(colorScheme))
    }

    /// Spelled out when the pane has room, an icon when the title needs it.
    private func editInsteadButton(_ url: URL) -> some View {
        ViewThatFits(in: .horizontal) {
            Button("Edit This Instead") { onEditInstead(url) }
                .fixedSize()
            Button { onEditInstead(url) } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("Edit This Instead")
        }
        .buttonStyle(.borderless)
        .help("Open this document for editing, with the one you're writing as its reference")
    }

    private var addressField: some View {
        TextField("Search or enter website", text: $address)
            .textFieldStyle(.plain)
            .focused($addressFocused)
            .onSubmit {
                reference.openAddress(address)
                addressFocused = false
            }
            #if os(iOS)
            .keyboardType(.webSearch)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
    }

    private var sourceMenu: some View {
        Menu {
            if !documents.isEmpty {
                Section("Writey Documents") {
                    ForEach(documents.prefix(30)) { item in
                        Button { reference.open(.document(item.url)) } label: {
                            Label(item.name, systemImage: "doc.text")
                        }
                    }
                }
            }
            if !library.referenceFiles.isEmpty {
                Section("Files") {
                    ForEach(library.referenceFiles.prefix(20)) { item in
                        Button { reference.open(.file(item.url)) } label: {
                            Label(item.name, systemImage: ReferenceSource.systemImage(forFile: item.url))
                        }
                    }
                }
            }
            Button {
                address = ""
                reference.isEnteringAddress = true
                addressFocused = true
            } label: {
                Label("Open Web Page…", systemImage: "globe")
            }
            Button { isAddingFile = true } label: {
                Label("Add File…", systemImage: "doc.badge.plus")
            }
            let recents = ReferenceStore.shared.recents.filter { $0 != reference.source }
            if !recents.isEmpty {
                Menu("Recent") {
                    ForEach(recents, id: \.self) { source in
                        Button { reference.open(source) } label: {
                            Label(source.title, systemImage: source.systemImage)
                        }
                    }
                }
            }
            Divider()
            Button { reference.swapSides() } label: {
                Label("Swap Sides", systemImage: "arrow.left.arrow.right")
            }
            if case .web(let url)? = reference.source {
                Button { openURL(url) } label: {
                    Label("Open in Browser", systemImage: "safari")
                }
            }
            #if os(macOS)
            if let url = reference.source?.fileURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            #endif
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        #endif
        .fixedSize()
        .help("Choose a reference")
        .accessibilityLabel("Reference Options")
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch reference.source {
        case nil:
            emptyState
        case .document?, .file?:
            switch reference.documentState {
            case .loading:
                ProgressView()
            case .loaded(let text):
                ReferenceTextView(text: text, typography: typography) { reference.open(.web($0)) }
            case .file(let url, let version):
                filePreview(url).id(version)
            case .unavailable(let message):
                ContentUnavailableView(
                    reference.source?.isFile == true ? "Can't Show This File" : "Can't Show This Document",
                    systemImage: "doc.questionmark",
                    description: Text(message)
                )
            }
        case .web?:
            if let message = reference.pageError {
                ContentUnavailableView {
                    Label("Can't Open This Page", systemImage: "globe")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { reference.retryPage() }
                }
            } else if let page = reference.page {
                WebView(page)
            }
        }
    }

    @ViewBuilder private func filePreview(_ url: URL) -> some View {
        if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
            PDFReferenceView(url: url)
        } else {
            QuickLookReferenceView(url: url)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Keep a document, a web page or a file beside your writing. Type an address above, pick a document, or add a PDF or other file.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(documents.prefix(12)) { item in
                    emptyStateRow(item.name, systemImage: "doc.text") { reference.open(.document(item.url)) }
                }
                ForEach(library.referenceFiles.prefix(6)) { item in
                    emptyStateRow(item.name, systemImage: ReferenceSource.systemImage(forFile: item.url)) {
                        reference.open(.file(item.url))
                    }
                }
                Button { isAddingFile = true } label: {
                    Label("Add a File…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
            }
            .padding(20)
        }
    }

    private func emptyStateRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // A fixed icon column, so names line up whatever the icon's width.
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 24)
                Text(title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Back, forward and reload for the reference's web page.
private struct WebNavigationButtons: View {
    let page: WebPage

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if let item = page.backForwardList.backList.last { page.load(item) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(page.backForwardList.backList.isEmpty)
            .help("Back")

            Button {
                if let item = page.backForwardList.forwardList.first { page.load(item) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(page.backForwardList.forwardList.isEmpty)
            .help("Forward")

            if page.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button { page.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")
            }
        }
        .buttonStyle(.borderless)
    }
}
