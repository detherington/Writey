import SwiftUI

struct EditorToolbar: View {
    var fileURL: URL?
    @Binding var showingSyncSheet: Bool
    @Binding var showingSettingsSheet: Bool

    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var editor: EditorController
    @EnvironmentObject var sync: SyncManager
    @EnvironmentObject var auth: GoogleAuth
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            FormatToggle(systemImage: "bold", label: "Bold", isOn: editor.isBold) { editor.toggleBold() }
            FormatToggle(systemImage: "italic", label: "Italic", isOn: editor.isItalic) { editor.toggleItalic() }
            FormatToggle(systemImage: "underline", label: "Underline", isOn: editor.isUnderline) { editor.toggleUnderline() }

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

            FormatToggle(systemImage: "list.bullet", label: "Bulleted List", isOn: editor.isBulletList) {
                editor.toggleBulletList()
            }
            FormatToggle(systemImage: "list.number", label: "Numbered List", isOn: editor.isNumberedList) {
                editor.toggleNumberedList()
            }

            Spacer()

            Menu {
                Picker("Appearance", selection: $theme.theme) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Image(systemName: themeIcon)
                    .frame(width: 28, height: 28)
                    .padding(6)
            }
            .accessibilityLabel("Appearance")

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
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(EditorPalette.chromeBackground(colorScheme))
    }

    private var syncLabel: String {
        if !auth.isSignedIn { return "Connect" }
        if sync.isLinked(fileURL: fileURL) { return "Sync" }
        return "Link"
    }

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
    let label: String
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
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
