import SwiftUI
import UIKit

/// Light / dark (true black) / match-system theming for iOS.
///
/// Persists the choice and sets `overrideUserInterfaceStyle` on every window
/// so OS-rendered chrome (document browser, nav bars, status bar) follows a
/// manual choice — `preferredColorScheme` alone only reaches SwiftUI views.
/// Editor colors live in `EditorPalette`, resolved from the SwiftUI
/// environment so they track system light/dark flips.
@MainActor
final class ThemeManager: ObservableObject {
    private static let storageKey = "WriteyAppTheme"
    private var observers: [NSObjectProtocol] = []

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.storageKey)
            applyToActiveWindows()
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: raw) ?? .system

        // Windows created later (the document browser on launch, a document
        // scene when one opens) get the override as they become key.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeKeyNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyToActiveWindows() }
            }
        )
        Task { @MainActor [weak self] in self?.applyToActiveWindows() }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    func applyToActiveWindows() {
        let style: UIUserInterfaceStyle
        switch theme {
        case .system: style = .unspecified
        case .light:  style = .light
        case .dark:   style = .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}
