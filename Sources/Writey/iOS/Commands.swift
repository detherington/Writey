import SwiftUI

/// SwiftUI `Commands` on iPadOS surface in the menu that appears when you
/// hold ⌘ on a connected hardware keyboard. Mirroring the Mac's
/// "Appearance" menu here gives the same `⌥⌘0/1/2` shortcuts on iPad
/// (and a discoverable menu entry for anyone using a Magic Keyboard).
struct ThemeCommands: Commands {
    @ObservedObject var theme: ThemeManager

    var body: some Commands {
        CommandMenu("Appearance") {
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
                .keyboardShortcut(shortcut(for: option), modifiers: [.command, .option])
            }
        }
    }

    private func shortcut(for theme: AppTheme) -> KeyEquivalent {
        switch theme {
        case .system: return "0"
        case .light:  return "1"
        case .dark:   return "2"
        }
    }
}
