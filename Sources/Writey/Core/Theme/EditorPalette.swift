import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Editor colors for a resolved color scheme. Views pass in
/// `@Environment(\.colorScheme)`, so a system light/dark flip in
/// "Match System" mode re-renders with the right colors.
enum EditorPalette {
    static func text(_ scheme: ColorScheme) -> PlatformColor {
        scheme == .dark
            ? PlatformColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1)
            : PlatformColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
    }

    static func selection(_ scheme: ColorScheme) -> PlatformColor {
        scheme == .dark
            ? PlatformColor(red: 0.22, green: 0.22, blue: 0.22, alpha: 1)
            : PlatformColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1)
    }

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }

    static func chromeBackground(_ scheme: ColorScheme) -> Color {
        if scheme == .dark { return .black }
        #if canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    static func chromeStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.18) : Color(white: 0.85)
    }
}
