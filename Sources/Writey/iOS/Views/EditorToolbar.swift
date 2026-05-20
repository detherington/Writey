import SwiftUI

struct EditorToolbar: View {
    @ObservedObject var document: WriteyDocument
    var fileURL: URL?
    @Binding var showingSyncSheet: Bool
    @Binding var showingSettingsSheet: Bool

    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var editor: EditorController
    @EnvironmentObject var sync: SyncManager
    @EnvironmentObject var auth: GoogleAuth

    var body: some View {
        HStack(spacing: 8) {
            Group {
                FormatToggle(systemImage: "bold", isOn: editor.isBold) { editor.toggleBold() }
                FormatToggle(systemImage: "italic", isOn: editor.isItalic) { editor.toggleItalic() }
                FormatToggle(systemImage: "underline", isOn: editor.isUnderline) { editor.toggleUnderline() }
            }

            Divider().frame(height: 18).padding(.horizontal, 4)

            Menu {
                Button("Title")      { editor.applyHeading(level: 1) }
                Button("Heading")    { editor.applyHeading(level: 2) }
                Button("Subheading") { editor.applyHeading(level: 3) }
                Divider()
                Button("Body")       { editor.applyHeading(level: 0) }
            } label: {
                Label("Style", systemImage: "textformat")
            }

            FormatToggle(systemImage: "list.bullet", isOn: false) { editor.toggleBulletList() }
            FormatToggle(systemImage: "list.number", isOn: false) { editor.toggleNumberedList() }

            Spacer()

            Menu {
                ForEach(AppTheme.allCases) { option in
                    Button {
                        theme.theme = option
                    } label: {
                        HStack {
                            Text(option.label)
                            if theme.theme == option {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: themeIcon)
                    .frame(width: 28, height: 28)
                    .padding(6)
            }
            .menuStyle(.borderlessButton)
            .help("Appearance")

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

            Button {
                showingSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.chromeBackground)
    }

    private var syncLabel: String {
        if !auth.isSignedIn { return "Connect" }
        if sync.isLinked(fileURL: fileURL) { return "Sync" }
        return "Link"
    }

    /// Icon reflects the *effective* theme (so "Match System" shows the
    /// resolved appearance), but the menu shows what the user actually
    /// picked via the checkmark.
    private var themeIcon: String {
        switch theme.theme {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon.fill"
        }
    }
}

private struct FormatToggle: View {
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? Color.accentColor.opacity(0.22) : Color.clear)
                )
                .foregroundColor(isOn ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}
