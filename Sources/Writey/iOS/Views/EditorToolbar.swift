import SwiftUI

/// Formatting bar above the editor. At regular width (iPad) it also holds
/// the document actions. At compact width (iPhone, narrow iPad split view)
/// the buttons go icon-only and spread across the bar, and the document
/// actions move to the navigation bar — see `DocumentActions`.
struct EditorToolbar: View {
    var fileURL: URL?
    @Binding var showingSyncSheet: Bool
    @Binding var showingSettingsSheet: Bool

    @EnvironmentObject var editor: EditorController
    @EnvironmentObject var sync: SyncManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if sizeClass == .compact {
                HStack(spacing: 0) {
                    Group {
                        textStyleButtons
                        paragraphButtons(iconOnly: true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 8)
            } else {
                HStack(spacing: 8) {
                    textStyleButtons
                    Divider().frame(height: 18).padding(.horizontal, 4)
                    paragraphButtons(iconOnly: false)
                    Spacer()
                    ThemeMenu()
                    SyncButton(fileURL: fileURL, sync: sync, showsTitle: true) {
                        showingSyncSheet = true
                    }
                    Button {
                        showingSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 10)
        .background(EditorPalette.chromeBackground(colorScheme))
    }

    @ViewBuilder private var textStyleButtons: some View {
        FormatToggle(systemImage: "bold", label: "Bold", isOn: editor.isBold) { editor.toggleBold() }
        FormatToggle(systemImage: "italic", label: "Italic", isOn: editor.isItalic) { editor.toggleItalic() }
        FormatToggle(systemImage: "underline", label: "Underline", isOn: editor.isUnderline) { editor.toggleUnderline() }
    }

    @ViewBuilder private func paragraphButtons(iconOnly: Bool) -> some View {
        Menu {
            Button("Title")      { editor.applyHeading(level: 1) }
            Button("Heading")    { editor.applyHeading(level: 2) }
            Button("Subheading") { editor.applyHeading(level: 3) }
            Divider()
            Button("Body")       { editor.applyHeading(level: 0) }
        } label: {
            if iconOnly {
                Image(systemName: "textformat")
                    .frame(width: 28, height: 28)
                    .padding(6)
            } else {
                Label("Style", systemImage: "textformat")
            }
        }
        .accessibilityLabel("Style")

        FormatToggle(systemImage: "list.bullet", label: "Bulleted List", isOn: editor.isBulletList) {
            editor.toggleBulletList()
        }
        FormatToggle(systemImage: "list.number", label: "Numbered List", isOn: editor.isNumberedList) {
            editor.toggleNumberedList()
        }
    }
}

/// Sync plus a More menu (appearance, distraction-free, settings), for the
/// navigation bar at compact width. Dependencies are passed in rather than
/// read from the environment, since toolbar items live outside the view.
struct DocumentActions: ToolbarContent {
    var fileURL: URL?
    let sync: SyncManager
    @Binding var showingSyncSheet: Bool
    @Binding var showingSettingsSheet: Bool
    @Binding var isDistractionFree: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            SyncButton(fileURL: fileURL, sync: sync, showsTitle: false) {
                showingSyncSheet = true
            }
            Menu {
                ThemePicker(asSubmenu: true)
                Button {
                    isDistractionFree = true
                } label: {
                    Label("Distraction-Free", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Button {
                    showingSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
        }
    }
}

private struct SyncButton: View {
    var fileURL: URL?
    @ObservedObject var sync: SyncManager
    let showsTitle: Bool
    let action: () -> Void

    @EnvironmentObject var auth: GoogleAuth

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if sync.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: sync.isLinked(fileURL: fileURL)
                          ? "arrow.triangle.2.circlepath"
                          : "icloud.and.arrow.up")
                }
                if showsTitle { Text(title) }
            }
        }
        .accessibilityLabel(title)
    }

    private var title: String {
        if !auth.isSignedIn { return "Connect" }
        if sync.isLinked(fileURL: fileURL) { return "Sync" }
        return "Link"
    }
}

private struct ThemeMenu: View {
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        Menu {
            ThemePicker()
        } label: {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .padding(6)
        }
        .accessibilityLabel("Appearance")
    }

    private var icon: String {
        switch theme.theme {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon.fill"
        }
    }
}

/// Inline options by default; `asSubmenu` nests them under "Appearance"
/// when they share a menu with other actions.
private struct ThemePicker: View {
    var asSubmenu = false
    @EnvironmentObject var theme: ThemeManager

    var body: some View {
        let picker = Picker(selection: $theme.theme) {
            ForEach(AppTheme.allCases) { option in
                Text(option.label).tag(option)
            }
        } label: {
            Label("Appearance", systemImage: "circle.lefthalf.filled")
        }
        if asSubmenu {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.inline)
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
