import UIKit

/// iOS implementation of `SyncConflictResolver`.
///
/// UIKit doesn't have a synchronous modal alert API the way AppKit does
/// (`NSAlert.runModal()`), so we drive a `UIAlertController` and block on
/// it using a Dispatch semaphore. This is OK because `SyncManager` calls
/// `resolveSyncConflict()` from the main actor — but only during the
/// rare conflict-prompt path, where blocking the run loop briefly while
/// the user picks is acceptable and matches the user's expectation of
/// a modal prompt.
final class IOSConflictResolver: SyncConflictResolver {
    @MainActor
    func resolveSyncConflict() -> SyncConflictChoice {
        guard let presenter = topPresentedViewController() else {
            return .cancel
        }

        let alert = UIAlertController(
            title: "Both versions have changed",
            message: "The local document and the Google Doc have both been edited since your last sync. Which copy should win?",
            preferredStyle: .alert
        )

        let semaphore = DispatchSemaphore(value: 0)
        var choice: SyncConflictChoice = .cancel

        alert.addAction(UIAlertAction(title: "Keep Local (push)", style: .default) { _ in
            choice = .keepLocal
            semaphore.signal()
        })
        alert.addAction(UIAlertAction(title: "Keep Google (pull)", style: .default) { _ in
            choice = .keepRemote
            semaphore.signal()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            choice = .cancel
            semaphore.signal()
        })

        presenter.present(alert, animated: true)
        // Yield to the run loop while we wait for the user.
        while semaphore.wait(timeout: .now() + 0.05) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return choice
    }

    @MainActor
    private func topPresentedViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
