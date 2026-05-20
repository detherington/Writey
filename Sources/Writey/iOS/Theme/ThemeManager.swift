import SwiftUI
import UIKit

/// iOS theme manager — matches the Mac's three-option model and "true
/// black" dark surface, but uses `UIWindow.overrideUserInterfaceStyle`
/// (instead of `NSApp.appearance`) to make sure the OS-rendered chrome —
/// the document browser, navigation bars, status bar — follows the user's
/// pick rather than the system setting.
@MainActor
final class ThemeManager: ObservableObject {
    private static let storageKey = "WriteyAppTheme"
    private var observers: [NSObjectProtocol] = []

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: ThemeManager.storageKey)
            applyToActiveWindows()
        }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: ThemeManager.storageKey) ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: raw) ?? .system

        // Paint every window that becomes key as it's created. This is what
        // pulls the document browser (on cold launch) and the document
        // detail scene (when you open a doc) into the user's chosen theme
        // — `preferredColorScheme()` alone only affects SwiftUI subtrees
        // and skips OS-managed chrome.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: UIWindow.didBecomeKeyNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                // The notification queue is .main, so we're on the main
                // thread — assert main-actor isolation explicitly so the
                // call to a @MainActor method is clean under Swift 6.
                MainActor.assumeIsolated {
                    self?.applyToActiveWindows()
                }
            }
        )

        // Initial paint, after the runloop ticks far enough that the
        // document browser scene exists.
        Task { @MainActor [weak self] in
            self?.applyToActiveWindows()
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// SwiftUI subtree color scheme — keeps Writey's own views consistent
    /// even before the per-window override has propagated.
    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// Resolves `.system` against the OS at call time. Used by the editor
    /// color accessors below to pick true-black vs. white surfaces.
    var effectiveColorScheme: ColorScheme {
        if let cs = preferredColorScheme { return cs }
        return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
    }

    /// Walks every UIWindow in every connected scene and sets
    /// `overrideUserInterfaceStyle`. iOS's analogue of macOS's
    /// `NSApp.appearance = .darkAqua`.
    func applyToActiveWindows() {
        let style: UIUserInterfaceStyle = {
            switch theme {
            case .system: return .unspecified
            case .light:  return .light
            case .dark:   return .dark
            }
        }()
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
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
