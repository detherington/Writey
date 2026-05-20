import SwiftUI
import AppKit

// AppTheme lives in Core/Theme/AppTheme.swift — shared with the iOS target.

/// Centralised light/dark/true-black theming.
///
/// - Stores the user's selection in UserDefaults.
/// - Drives SwiftUI's `preferredColorScheme` from the top of the scene tree.
/// - Overrides the NSApplication appearance so AppKit chrome (title bars,
///   menus, NSWindow background) follows the manual selection.
/// - Exposes "true black" surfaces so the editor and window backgrounds are
///   #000000 in dark mode rather than the default ~#1E1E1E system dark.
final class ThemeManager: ObservableObject {
    private static let storageKey = "WriteyAppTheme"

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: ThemeManager.storageKey)
            apply()
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: ThemeManager.storageKey) ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: raw) ?? .system
    }

    /// Called once from `WriteyApp.init` so the very first window opens with
    /// the correct NSApp.appearance, before any SwiftUI views are constructed.
    static func applyOnLaunch() {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppTheme.system.rawValue
        let theme = AppTheme(rawValue: raw) ?? .system
        DispatchQueue.main.async {
            applyAppearance(for: theme)
        }
    }

    func apply() {
        ThemeManager.applyAppearance(for: theme)
        // Repaint open windows with new true-black surfaces.
        for window in NSApp.windows {
            paint(window: window)
        }
    }

    private static func applyAppearance(for theme: AppTheme) {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// SwiftUI-level color scheme override (nil = follow system).
    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// The effective scheme right now, resolving `.system` against the OS.
    var effectiveColorScheme: ColorScheme {
        if let cs = preferredColorScheme { return cs }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark ? .dark : .light
    }

    // MARK: - Surfaces

    /// Background of the editor canvas.
    var editorBackground: Color {
        effectiveColorScheme == .dark ? .black : Color(nsColor: .white)
    }

    /// Foreground (typed) text color.
    var editorTextNSColor: NSColor {
        effectiveColorScheme == .dark
            ? NSColor(calibratedWhite: 0.93, alpha: 1.0)
            : NSColor(calibratedWhite: 0.08, alpha: 1.0)
    }

    /// Caret + selection accent.
    var caretNSColor: NSColor { editorTextNSColor }

    var selectionBackgroundNSColor: NSColor {
        effectiveColorScheme == .dark
            ? NSColor(calibratedWhite: 0.22, alpha: 1.0)
            : NSColor(calibratedWhite: 0.82, alpha: 1.0)
    }

    /// Chrome (toolbar) tint.
    var chromeBackground: Color {
        effectiveColorScheme == .dark ? Color.black : Color(nsColor: .windowBackgroundColor)
    }

    var chromeStroke: Color {
        effectiveColorScheme == .dark
            ? Color(white: 0.18)
            : Color(white: 0.85)
    }

    /// Paint a window so the title bar area visually matches the editor
    /// surface (true black in dark, pure white in light). This makes the
    /// distraction-free transparent-title-bar look seamless in both themes.
    func paint(window: NSWindow) {
        switch effectiveColorScheme {
        case .dark:
            window.backgroundColor = .black
        case .light:
            window.backgroundColor = .white
        @unknown default:
            window.backgroundColor = .white
        }
        // Don't reset titlebarAppearsTransparent here — distraction-free
        // mode owns that flag.
    }
}

// MARK: - Menu commands

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
