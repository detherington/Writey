import Foundation
import Sparkle
import SwiftUI

/// Wraps `SPUStandardUpdaterController` so SwiftUI views can observe its
/// state and trigger a manual update check from the menu bar.
///
/// Sparkle reads its configuration from Info.plist:
///   - `SUFeedURL`        → appcast URL (points at our GitHub Release asset)
///   - `SUPublicEDKey`    → Ed25519 verification key (public; matching
///                          private key signs each release in CI)
///   - `SUEnableInstallerLauncherService` → required for sandboxed apps
///   - `SUEnableAutomaticChecks` → daily background check by default
///
/// The matching *private* signing key lives only in:
///   - your macOS Keychain locally (managed by Sparkle's generate_keys)
///   - GitHub Actions Secrets as SPARKLE_PRIVATE_KEY for CI signing
final class UpdaterService: NSObject, ObservableObject {
    let controller: SPUStandardUpdaterController

    @Published var canCheckForUpdates: Bool = false

    override init() {
        // `startingUpdater: true` means Sparkle begins its background
        // check schedule immediately on launch (subject to user defaults).
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

        // Mirror the underlying property so SwiftUI can disable the
        // menu item while a check is in flight.
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
