import Foundation

/// User-selectable theme. Both platform `ThemeManager`s persist this same
/// enum to UserDefaults; the rendering logic is platform-specific.
public enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "Match System"
        case .light:  return "Light"
        case .dark:   return "Dark (True Black)"
        }
    }
}
