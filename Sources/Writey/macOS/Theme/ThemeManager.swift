import SwiftUI
import AppKit

/// Light / dark (true black) / match-system theming.
///
/// Persists the choice, drives SwiftUI's `preferredColorScheme`, and sets
/// `NSApp.appearance` so AppKit chrome (title bars, menus) follows a manual
/// choice. Editor colors live in `EditorPalette` and are resolved from the
/// SwiftUI environment, so they track OS light/dark flips in system mode.
final class ThemeManager: ObservableObject {
    private static let storageKey = "WriteyAppTheme"

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey)
            Self.applyAppearance(for: theme)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: raw) ?? .system
    }

    /// Called from `WriteyApp.init` so the first window opens with the right
    /// appearance before any SwiftUI views exist.
    static func applyOnLaunch() {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppTheme.system.rawValue
        let theme = AppTheme(rawValue: raw) ?? .system
        DispatchQueue.main.async { applyAppearance(for: theme) }
    }

    private static func applyAppearance(for theme: AppTheme) {
        switch theme {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Paints the window behind the title bar to match the editor surface,
    /// so the transparent distraction-free title bar blends in.
    func paint(window: NSWindow, scheme: ColorScheme) {
        window.backgroundColor = scheme == .dark ? .black : .white
    }
}
