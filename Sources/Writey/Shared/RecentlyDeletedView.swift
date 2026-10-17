import SwiftUI

/// Documents deleted in the last 30 days, with Restore and Delete Now.
/// A sheet from the iOS home screen and the Mac library window.
struct RecentlyDeletedView: View {
    @EnvironmentObject var library: DocumentLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var deletingNow: DocumentLibrary.DeletedItem?
    @State private var confirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                if !library.deletedItems.isEmpty {
                    Text("Documents are deleted for good 30 days after you delete them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(EditorPalette.background(colorScheme))
                }
                ForEach(library.deletedItems) { item in
                    row(item)
                        .listRowBackground(EditorPalette.background(colorScheme))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(EditorPalette.background(colorScheme))
            .overlay {
                if library.deletedItems.isEmpty {
                    ContentUnavailableView(
                        "No Recently Deleted Documents",
                        systemImage: "trash",
                        description: Text("Deleted documents stay here for 30 days.")
                    )
                }
            }
            .navigationTitle("Recently Deleted")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: deleteAllPlacement) {
                    Button("Delete All", role: .destructive) { confirmingDeleteAll = true }
                        .disabled(library.deletedItems.isEmpty)
                }
            }
            .confirmationDialog(
                deletingNow.map { "Delete “\($0.name)” now?" } ?? "",
                isPresented: isDeletingNow,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let item = deletingNow else { return }
                    Task { await library.deletePermanently(item) }
                }
            } message: {
                Text("You can't undo this.")
            }
            .confirmationDialog(
                "Delete all \(library.deletedItems.count) documents now?",
                isPresented: $confirmingDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    Task { await library.emptyRecentlyDeleted() }
                }
            } message: {
                Text("You can't undo this.")
            }
        }
        .presentationBackground(EditorPalette.background(colorScheme))
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
    }

    private func row(_ item: DocumentLibrary.DeletedItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(Self.timeLeft(item.daysLeft))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") { restore(item) }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button { restore(item) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) { deletingNow = item } label: {
                Label("Delete Now…", systemImage: "trash")
            }
        }
        #if os(iOS)
        .swipeActions(edge: .leading) {
            Button { restore(item) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.green)
        }
        .swipeActions {
            // Not role: .destructive, which would slide the row away before
            // the confirmation is answered.
            Button { deletingNow = item } label: {
                Label("Delete Now", systemImage: "trash")
            }
            .tint(.red)
        }
        #endif
    }

    private var deleteAllPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .destructiveAction
        #endif
    }

    private func restore(_ item: DocumentLibrary.DeletedItem) {
        Task { await library.restore(item) }
    }

    static func timeLeft(_ days: Int) -> String {
        switch days {
        case 0: return "Deleted for good within a day"
        case 1: return "1 day left"
        default: return "\(days) days left"
        }
    }

    private var isDeletingNow: Binding<Bool> {
        Binding(get: { deletingNow != nil }, set: { if !$0 { deletingNow = nil } })
    }
}
