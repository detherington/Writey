import SwiftUI
import UIKit

/// iOS theme manager — much smaller than the macOS one because:
///   - iOS handles dark mode natively at the OS level
///   - There's no NSWindow to repaint
///   - There's no NSApp.appearance override
///
/// All we do here is persist the user's choice and expose the SwiftUI
/// `preferredColorScheme` plus a handful of editor colors (foreground,
/// background, selection) that the editor view applies to its UITextView.
final class ThemeManager: ObservableObject {
    private static let storageKey = "WriteyAppTheme"

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: ThemeManager.storageKey)
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: ThemeManager.storageKey) ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: raw) ?? .system
    }

    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Resolves `.system` against the OS at call time.
    var effectiveColorScheme: ColorScheme {
        if let cs = preferredColorScheme { return cs }
        return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
    }

    // MARK: - Surfaces

    var editorBackground: Color {
        effectiveColorScheme == .dark ? .black : .white
    }

    var editorTextUIColor: UIColor {
        effectiveColorScheme == .dark
            ? UIColor(white: 0.93, alpha: 1.0)
            : UIColor(white: 0.08, alpha: 1.0)
    }

    var caretUIColor: UIColor { editorTextUIColor }

    var selectionBackgroundUIColor: UIColor {
        effectiveColorScheme == .dark
            ? UIColor(white: 0.22, alpha: 1.0)
            : UIColor(white: 0.82, alpha: 1.0)
    }

    var chromeBackground: Color {
        effectiveColorScheme == .dark ? .black : Color(uiColor: .systemBackground)
    }

    var chromeStroke: Color {
        effectiveColorScheme == .dark ? Color(white: 0.18) : Color(white: 0.85)
    }
}
