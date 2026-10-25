import SwiftUI
import WebKit

/// The reference beside the writing: another document, read-only, or a
/// web page. A header like the editor's toolbar holds the address or title,
/// the source menu, and close.
struct ReferencePane: View {
    @ObservedObject var reference: ReferenceController
    /// Writey documents that can be opened here (not the one being written).
    let documents: [DocumentLibrary.Item]
    let typography: Typography
    /// Opens the reference document for editing, swapping it with the writing.
    let onEditInstead: (URL) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var address = ""
    @FocusState private var addressFocused: Bool

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
    }

    // MARK: - Header

    private var showsAddressField: Bool {
        switch reference.source {
        case nil, .web?: return true
        case .document?: return reference.isEnteringAddress
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if showsAddressField {
                if case .web? = reference.source, let page = reference.page {
                    WebNavigationButtons(page: page)
                }
                addressField
            } else if case .document(let url)? = reference.source {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(reference.source?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if !reference.isInRecentlyDeleted {
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
            Button {
                address = ""
                reference.isEnteringAddress = true
                addressFocused = true
            } label: {
                Label("Open Web Page…", systemImage: "globe")
            }
            let recents = ReferenceStore.shared.recents.filter { $0 != reference.source }
            if !recents.isEmpty {
                Menu("Recent") {
                    ForEach(recents, id: \.self) { source in
                        Button { reference.open(source) } label: {
                            Label(source.title, systemImage: icon(for: source))
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

    private func icon(for source: ReferenceSource) -> String {
        if case .web = source { return "globe" }
        return "doc.text"
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch reference.source {
        case nil:
            emptyState
        case .document?:
            switch reference.documentState {
            case .loading:
                ProgressView()
            case .loaded(let text):
                ReferenceTextView(text: text, typography: typography)
            case .unavailable(let message):
                ContentUnavailableView("Can't Show This Document", systemImage: "doc.questionmark", description: Text(message))
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

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Keep a document or a web page beside your writing. Type an address above, or pick a document.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(documents.prefix(12)) { item in
                    Button { reference.open(.document(item.url)) } label: {
                        Label(item.name, systemImage: "doc.text")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
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
