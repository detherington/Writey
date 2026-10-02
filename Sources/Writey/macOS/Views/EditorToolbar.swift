import SwiftUI

struct EditorToolbar: View {
    var fileURL: URL?
    @Binding var showingSyncSheet: Bool

    @EnvironmentObject var editor: EditorController
    @EnvironmentObject var sync: SyncManager
    @EnvironmentObject var auth: GoogleAuth
    @Environment(\.colorScheme) private var colorScheme

    // Keyboard shortcuts live on the Format menu, not here, so each is
    // bound exactly once.
    var body: some View {
        HStack(spacing: 6) {
            FormatToggle(systemImage: "bold", help: "Bold (⌘B)", isOn: editor.isBold) { editor.toggleBold() }
            FormatToggle(systemImage: "italic", help: "Italic (⌘I)", isOn: editor.isItalic) { editor.toggleItalic() }
            FormatToggle(systemImage: "underline", help: "Underline (⌘U)", isOn: editor.isUnderline) { editor.toggleUnderline() }

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

            FormatToggle(systemImage: "list.bullet", help: "Bulleted List (⇧⌘8)", isOn: editor.isBulletList) {
                editor.toggleBulletList()
            }
            FormatToggle(systemImage: "list.number", help: "Numbered List (⇧⌘7)", isOn: editor.isNumberedList) {
                editor.toggleNumberedList()
            }

            Spacer()

            syncButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(EditorPalette.chromeBackground(colorScheme))
    }

    private var syncButton: some View {
        Button {
            showingSyncSheet = true
        } label: {
            HStack(spacing: 6) {
                if sync.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: sync.isLinked(fileURL: fileURL)
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
        if sync.isLinked(fileURL: fileURL) { return "Sync" }
        return "Link to Google Doc"
    }

    private var syncTooltip: String {
        if !auth.isSignedIn { return "Sign in to Google to enable sync" }
        if sync.isLinked(fileURL: fileURL) { return "Push and pull the latest with Google Docs (⇧⌘Y)" }
        if fileURL == nil { return "Save this document (⌘S) before linking it to a Google Doc" }
        return "Create or attach a Google Doc for this file"
    }
}

private struct FormatToggle: View {
    let systemImage: String
    let help: String
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
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
