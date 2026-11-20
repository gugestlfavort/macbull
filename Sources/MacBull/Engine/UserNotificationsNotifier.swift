import Foundation
import UserNotifications

/// The real notifier: UNUserNotificationCenter, only inside a .app bundle.
@MainActor
final class UserNotificationsNotifier: NSObject, Notifying {
    var onActivate: (@MainActor () -> Void)?

    /// `UNUserNotificationCenter.current()` crashes without a bundle identifier (`swift run`)
    /// and only works for a real .app bundle.
    private var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    private var delegateInstalled = false

    func requestAuthorization() {
        guard isAvailable else {
            Log.engine.notice("Notifications need the app bundle, skipping the permission request")
            return
        }
        Task { @MainActor in
            _ = await self.authorizedCenter()
        }
    }

    func post(_ notification: AppNotification) {
        guard isAvailable else {
            Log.engine.notice("Would notify (no app bundle): \(notification.body, privacy: .public)")
            return
        }
        Task { @MainActor in
            guard let center = await self.authorizedCenter() else { return }
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            if let thread = notification.threadID { content.threadIdentifier = thread }
            if let file = notification.soundFile {
                content.sound = UNNotificationSound(named: UNNotificationSoundName("Sounds/\(file)"))
            } else {
                content.sound = .default
            }
            let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                Log.engine.error("Could not post the notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func withdraw(identifier: String) {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// The center if we may post, asking the user the first time. nil when denied.
    private func authorizedCenter() async -> UNUserNotificationCenter? {
        let center = UNUserNotificationCenter.current()
        installDelegate(on: center)
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return center
        case .notDetermined:
            do {
                if try await center.requestAuthorization(options: [.alert, .sound]) { return center }
            } catch {
                Log.engine.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
            }
            Log.engine.notice("Notifications were not allowed")
            return nil
        default:
            Log.engine.notice("Notifications are turned off for MacBull in System Settings")
            return nil
        }
    }

    private func installDelegate(on center: UNUserNotificationCenter) {
        guard !delegateInstalled else { return }
        delegateInstalled = true
        center.delegate = self
    }
}

extension UserNotificationsNotifier: UNUserNotificationCenterDelegate {
    /// Show banners even while one of our own windows is in front.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { self.onActivate?() }
    }
}
