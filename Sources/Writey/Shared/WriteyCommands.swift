import SwiftUI

// Menu commands shared by the Mac app and the iPadOS 26 menu bar. Each
// document window publishes its editor and sheet/mode bindings as focused
// values, so a command acts on the frontmost document and is disabled when
// there isn't one. `EditorController` and `ThemeManager` are per-platform
// types with the same API.

extension FocusedValues {
    @Entry var syncSheetPresented: Binding<Bool>?
    @Entry var distractionFree: Binding<Bool>?
}

struct FormatCommands: Commands {
    @FocusedObject private var editor: EditorController?

    var body: some Commands {
        #if os(macOS)
        CommandMenu("Format") {
            Button("Bold") { editor?.toggleBold() }
                .keyboardShortcut("b")
            Button("Italic") { editor?.toggleItalic() }
                .keyboardShortcut("i")
            Button("Underline") { editor?.toggleUnderline() }
                .keyboardShortcut("u")
            Divider()
            styleButtons
        }
        #else
        // iPadOS already has Format ▸ Font ▸ Bold/Italic/Underline (⌘B/⌘I/⌘U)
        // wired straight to the text view; re-declaring those shortcuts here
        // would collide with it.
        CommandMenu("Style") {
            styleButtons
        }
        #endif
    }

    @ViewBuilder
    private var styleButtons: some View {
        Group {
            Button("Title") { editor?.applyHeading(level: 1) }
                .keyboardShortcut("1")
            Button("Heading") { editor?.applyHeading(level: 2) }
                .keyboardShortcut("2")
            Button("Subheading") { editor?.applyHeading(level: 3) }
                .keyboardShortcut("3")
            Button("Body") { editor?.applyHeading(level: 0) }
                .keyboardShortcut("0")
            Divider()
            // Same shortcuts as Google Docs.
            Button("Bulleted List") { editor?.toggleBulletList() }
                .keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Numbered List") { editor?.toggleNumberedList() }
                .keyboardShortcut("7", modifiers: [.command, .shift])
        }
        .disabled(editor == nil)
    }
}

struct SyncCommands: Commands {
    @FocusedBinding(\.syncSheetPresented) private var syncSheetPresented

    var body: some Commands {
        CommandMenu("Sync") {
            Button("Sync with Google Docs…") { syncSheetPresented = true }
                .keyboardShortcut("y", modifiers: [.command, .shift])
                .disabled(syncSheetPresented == nil)
        }
    }
}

struct ViewCommands: Commands {
    @FocusedBinding(\.distractionFree) private var distractionFree

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            // ⇧⌘D rather than ⌃⌘D: macOS reserves ⌃⌘D for Look Up.
            Button(distractionFree == true ? "Exit Distraction-Free Mode" : "Distraction-Free Mode") {
                if let current = distractionFree { distractionFree = !current }
            }
            .keyboardShortcut("d", modifiers: [.shift, .command])
            .disabled(distractionFree == nil)
        }
    }
}

struct ThemeCommands: Commands {
    @ObservedObject var theme: ThemeManager

    var body: some Commands {
        CommandMenu("Appearance") {
            // Toggles render as native checkmark items in menus.
            ForEach(AppTheme.allCases) { option in
                Toggle(option.label, isOn: Binding(
                    get: { theme.theme == option },
                    set: { if $0 { theme.theme = option } }
                ))
                .keyboardShortcut(Self.shortcut(for: option), modifiers: [.command, .option])
            }
        }
    }

    private static func shortcut(for theme: AppTheme) -> KeyEquivalent {
        switch theme {
        case .system: return "0"
        case .light:  return "1"
        case .dark:   return "2"
        }
    }
}
