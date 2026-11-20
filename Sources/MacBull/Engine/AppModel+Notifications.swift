import Foundation

/// Notification rules: the engine decides, the notifier posts.
extension AppModel {
    /// Notifications are on in Settings and the app is not quitting.
    var canNotify: Bool {
        settings.notifications && !state.quitting
    }

    /// The custom sound file when notification sounds are on; nil means the default sound.
    func sound(_ file: String) -> String? {
        settings.notificationSounds ? file : nil
    }

    /// Posts when allowed. Returns whether it went out.
    @discardableResult
    func deliver(_ notification: AppNotification) -> Bool {
        guard canNotify else {
            Log.engine.notice("Notification not sent (off or quitting)")
            return false
        }
        notifier.post(notification)
        return true
    }

    private func deliverThrottled(_ kind: NotificationThrottle.Kind, _ notification: AppNotification) {
        guard canNotify else { return }
        guard memory.throttle.allow(kind, at: now()) else {
            Log.engine.notice("Notification throttled")
            return
        }
        notifier.post(notification)
    }

    func notifySafetyStop(_ stop: SafetyStop, agentsWereWorking: Bool) {
        let notification = NotificationText.safetyStop(
            stop,
            agentsWereWorking: agentsWereWorking,
            batteryPercent: state.batteryPercent,
            soundFile: sound(NotificationSound.safetyStop)
        )
        deliverThrottled(stop == .heat ? .heat : .battery, notification)
    }

    /// Held notices fold into the receipt while away; blips under two minutes say nothing.
    func notifyAgentsDone(heldFor: TimeInterval) {
        guard heldFor >= EngineTiming.minimumHoldForDoneNoticeSeconds else { return }
        guard !(state.isAway && settings.bundleWhileAway) else {
            Log.engine.info("Agents done notice held for the receipt")
            return
        }
        let sleeping = state.closedInBag && state.lidHeld
        let notification = NotificationText.agentsDone(
            puttingMacToSleep: sleeping,
            soundFile: sound(NotificationSound.agentsDone)
        )
        deliverThrottled(.agentsDone, notification)
    }
}
