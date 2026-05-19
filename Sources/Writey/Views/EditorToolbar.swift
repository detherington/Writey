import SwiftUI

struct EditorToolbar: View {
    @ObservedObject var document: WriteyDocument
    var fileURL: URL?
    @Binding var showingSyncSheet: Bool

    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var editor: EditorController
    @EnvironmentObject var sync: SyncManager
    @EnvironmentObject var auth: GoogleAuth

    var body: some View {
        HStack(spacing: 6) {
            FormatToggle(systemImage: "bold", isOn: editor.isBold) { editor.toggleBold() }
                .keyboardShortcut("b", modifiers: .command)
            FormatToggle(systemImage: "italic", isOn: editor.isItalic) { editor.toggleItalic() }
                .keyboardShortcut("i", modifiers: .command)
            FormatToggle(systemImage: "underline", isOn: editor.isUnderline) { editor.toggleUnderline() }
                .keyboardShortcut("u", modifiers: .command)

            Divider().frame(height: 16).padding(.horizontal, 4)

            Menu {
                Button("Title")      { editor.applyHeading(level: 1) }
                Button("Heading")    { editor.applyHeading(level: 2) }
                Button("Subheading") { editor.applyHeading(level: 3) }
                Divider()
                Button("Body")       { editor.applyHeading(level: 0) }
            } label: {
                Label("Style", systemImage: "textformat")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            FormatToggle(systemImage: "list.bullet", isOn: false) { editor.toggleBulletList() }
            FormatToggle(systemImage: "list.number", isOn: false) { editor.toggleNumberedList() }

            Spacer()

            syncButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(theme.chromeBackground)
    }

    @ViewBuilder
    private var syncButton: some View {
        Button {
            showingSyncSheet = true
        } label: {
            HStack(spacing: 6) {
                if sync.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: sync.isLinked(fileURL: fileURL, documentID: document.documentID)
                          ? "arrow.triangle.2.circlepath"
                          : "icloud.and.arrow.up")
                }
                Text(syncLabel)
            }
        }
        .buttonStyle(.borderless)
        .help(syncTooltip)
    }

    private var syncLabel: String {
        if !auth.isSignedIn { return "Connect Google" }
        if sync.isLinked(fileURL: fileURL, documentID: document.documentID) { return "Sync" }
        return "Link to Google Doc"
    }

    private var syncTooltip: String {
        if !auth.isSignedIn { return "Sign in to Google to enable sync" }
        if sync.isLinked(fileURL: fileURL, documentID: document.documentID) {
            return "Push and pull the latest with Google Docs"
        }
        return "Create or attach a Google Doc for this file"
    }
}

private struct FormatToggle: View {
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 22, height: 22)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? Color.accentColor.opacity(0.20) : Color.clear)
                )
                .foregroundColor(isOn ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}
