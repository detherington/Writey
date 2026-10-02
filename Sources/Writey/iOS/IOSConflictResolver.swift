import UIKit

/// Asks "which copy wins?" with a UIAlertController and awaits the answer.
/// (The previous version blocked by spinning the run loop, and hung the app
/// forever if the alert failed to present.)
final class IOSConflictResolver: SyncConflictResolver {
    @MainActor
    func resolveSyncConflict() async -> SyncConflictChoice {
        guard let presenter = topPresentedViewController() else { return .cancel }

        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Both versions have changed",
                message: "This document and its Google Doc have both been edited since your last sync. Which copy should win? Writey saves your copy before replacing it, and Google Docs keeps its own version history.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Keep Mine (push)", style: .default) { _ in
                continuation.resume(returning: .keepLocal)
            })
            alert.addAction(UIAlertAction(title: "Keep Google's (pull)", style: .default) { _ in
                continuation.resume(returning: .keepRemote)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: .cancel)
            })
            presenter.present(alert, animated: true)

            // UIKit declines to present (silently) if the presenter is busy;
            // then no action can ever fire, so answer for it.
            if presenter.presentedViewController !== alert {
                continuation.resume(returning: .cancel)
            }
        }
    }

    @MainActor
    private func topPresentedViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
