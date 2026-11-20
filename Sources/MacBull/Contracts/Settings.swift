import Foundation
import Observation

/// Every user setting, stored in UserDefaults. Changing any value saves it and calls `onChange`.
@MainActor
@Observable
final class Settings {
    static let shared = Settings(defaults: .standard)

    @ObservationIgnored private let defaults: UserDefaults
    /// Set by the engine: re-evaluate after any change.
    @ObservationIgnored var onChange: (() -> Void)?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: Self.registered)
        keepDisplayOn = defaults.bool(forKey: Key.keepDisplayOn)
        defaultMinutes = defaults.integer(forKey: Key.defaultMinutes)
        clickToggles = defaults.bool(forKey: Key.clickToggles)
        startOnLaunch = defaults.bool(forKey: Key.startOnLaunch)
        notifications = defaults.bool(forKey: Key.notifications)
        welcomeDone = defaults.bool(forKey: Key.welcomeDone)
        lidHold = defaults.bool(forKey: Key.lidHold)
        lowPowerInBag = defaults.bool(forKey: Key.lowPowerInBag)
        agentMode = defaults.bool(forKey: Key.agentMode)
        graceMinutes = defaults.integer(forKey: Key.graceMinutes)
        customAgents = defaults.stringArray(forKey: Key.customAgents) ?? []
        claudeHooks = defaults.bool(forKey: Key.claudeHooks)
        stallWatchdog = defaults.bool(forKey: Key.stallWatchdog)
        batteryGuard = defaults.bool(forKey: Key.batteryGuard)
        batteryPercent = defaults.integer(forKey: Key.batteryPercent)
        heatGuard = defaults.bool(forKey: Key.heatGuard)
        showWaitingCount = defaults.bool(forKey: Key.showWaitingCount)
        wakeScreenWhenWaiting = defaults.bool(forKey: Key.wakeScreenWhenWaiting)
        quietHoursStart = defaults.integer(forKey: Key.quietHoursStart)
        quietHoursEnd = defaults.integer(forKey: Key.quietHoursEnd)
        remindAfterMinutes = defaults.integer(forKey: Key.remindAfterMinutes)
        bundleWhileAway = defaults.bool(forKey: Key.bundleWhileAway)
        receiptMinAwayMinutes = defaults.integer(forKey: Key.receiptMinAwayMinutes)
        showProjectNames = defaults.bool(forKey: Key.showProjectNames)
        historyDays = defaults.integer(forKey: Key.historyDays)
        sounds = defaults.bool(forKey: Key.sounds)
        soundVolume = defaults.double(forKey: Key.soundVolume)
        haptics = defaults.bool(forKey: Key.haptics)
        notificationSounds = defaults.bool(forKey: Key.notificationSounds)
    }

    // MARK: General

    var keepDisplayOn: Bool { didSet { save(keepDisplayOn, Key.keepDisplayOn) } }
    /// Default duration in minutes; 0 means until turned off.
    var defaultMinutes: Int { didSet { save(defaultMinutes, Key.defaultMinutes) } }
    /// A plain left click on the menu bar can switches awake on and off instead of opening the panel.
    var clickToggles: Bool { didSet { save(clickToggles, Key.clickToggles) } }
    var startOnLaunch: Bool { didSet { save(startOnLaunch, Key.startOnLaunch) } }
    var notifications: Bool { didSet { save(notifications, Key.notifications) } }
    var welcomeDone: Bool { didSet { save(welcomeDone, Key.welcomeDone) } }

    // MARK: Lid closed

    var lidHold: Bool { didSet { save(lidHold, Key.lidHold) } }
    var lowPowerInBag: Bool { didSet { save(lowPowerInBag, Key.lowPowerInBag) } }

    // MARK: AI agents

    var agentMode: Bool { didSet { save(agentMode, Key.agentMode) } }
    /// Grace period after the last agent stops working. Choices 1, 2, 3, 5, 10.
    var graceMinutes: Int { didSet { save(graceMinutes, Key.graceMinutes) } }
    /// Normalised command or script names the user added.
    var customAgents: [String] { didSet { save(customAgents, Key.customAgents) } }
    var claudeHooks: Bool { didSet { save(claudeHooks, Key.claudeHooks) } }
    /// Flag sessions that claim to work but show no sign of life (Stall Watchdog).
    var stallWatchdog: Bool { didSet { save(stallWatchdog, Key.stallWatchdog) } }

    // MARK: Your Turn

    var showWaitingCount: Bool { didSet { save(showWaitingCount, Key.showWaitingCount) } }
    var wakeScreenWhenWaiting: Bool { didSet { save(wakeScreenWhenWaiting, Key.wakeScreenWhenWaiting) } }
    /// Hour of day (0-23) when quiet hours start and end; equal values mean no quiet hours.
    var quietHoursStart: Int { didSet { save(quietHoursStart, Key.quietHoursStart) } }
    var quietHoursEnd: Int { didSet { save(quietHoursEnd, Key.quietHoursEnd) } }
    /// Reminder when a session still waits for you; 0 means off. Choices 0, 2, 5, 15.
    var remindAfterMinutes: Int { didSet { save(remindAfterMinutes, Key.remindAfterMinutes) } }

    // MARK: Safety

    var batteryGuard: Bool { didSet { save(batteryGuard, Key.batteryGuard) } }
    /// Choices 10, 15, 20, 30, 50.
    var batteryPercent: Int { didSet { save(batteryPercent, Key.batteryPercent) } }
    var heatGuard: Bool { didSet { save(heatGuard, Key.heatGuard) } }

    // MARK: Away (Receipt) and history

    var bundleWhileAway: Bool { didSet { save(bundleWhileAway, Key.bundleWhileAway) } }
    var receiptMinAwayMinutes: Int { didSet { save(receiptMinAwayMinutes, Key.receiptMinAwayMinutes) } }
    var showProjectNames: Bool { didSet { save(showProjectNames, Key.showProjectNames) } }
    var historyDays: Int { didSet { save(historyDays, Key.historyDays) } }

    // MARK: Sound and feel

    var sounds: Bool { didSet { save(sounds, Key.sounds) } }
    /// 0...1, relative to system volume.
    var soundVolume: Double { didSet { save(soundVolume, Key.soundVolume) } }
    var haptics: Bool { didSet { save(haptics, Key.haptics) } }
    var notificationSounds: Bool { didSet { save(notificationSounds, Key.notificationSounds) } }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }

    private enum Key {
        static let keepDisplayOn = "general.keepDisplayOn"
        static let defaultMinutes = "general.defaultMinutes"
        static let clickToggles = "general.clickToggles"
        static let startOnLaunch = "general.startOnLaunch"
        static let notifications = "general.notifications"
        static let welcomeDone = "general.welcomeDone"
        static let lidHold = "lid.hold"
        static let lowPowerInBag = "lid.lowPowerInBag"
        static let agentMode = "agents.enabled"
        static let graceMinutes = "agents.graceMinutes"
        static let customAgents = "agents.custom"
        static let claudeHooks = "agents.claudeHooks"
        static let stallWatchdog = "agents.stallWatchdog"
        static let showWaitingCount = "yourTurn.showCount"
        static let wakeScreenWhenWaiting = "yourTurn.wakeScreen"
        static let quietHoursStart = "yourTurn.quietStart"
        static let quietHoursEnd = "yourTurn.quietEnd"
        static let remindAfterMinutes = "yourTurn.remindAfter"
        static let batteryGuard = "safety.battery"
        static let batteryPercent = "safety.batteryPercent"
        static let heatGuard = "safety.heat"
        static let bundleWhileAway = "away.bundle"
        static let receiptMinAwayMinutes = "away.minMinutes"
        static let showProjectNames = "away.projectNames"
        static let historyDays = "away.historyDays"
        static let sounds = "feel.sounds"
        static let soundVolume = "feel.volume"
        static let haptics = "feel.haptics"
        static let notificationSounds = "feel.notificationSounds"
    }

    private static let registered: [String: Any] = [
        Key.keepDisplayOn: true,
        Key.defaultMinutes: 0,
        Key.clickToggles: false,
        Key.startOnLaunch: false,
        Key.notifications: true,
        Key.welcomeDone: false,
        Key.lidHold: true,
        Key.lowPowerInBag: true,
        Key.agentMode: true,
        Key.graceMinutes: 3,
        Key.claudeHooks: false,
        Key.stallWatchdog: true,
        Key.showWaitingCount: true,
        Key.wakeScreenWhenWaiting: true,
        Key.quietHoursStart: 22,
        Key.quietHoursEnd: 7,
        Key.remindAfterMinutes: 5,
        Key.batteryGuard: true,
        Key.batteryPercent: 20,
        Key.heatGuard: true,
        Key.bundleWhileAway: true,
        Key.receiptMinAwayMinutes: 20,
        Key.showProjectNames: true,
        Key.historyDays: 30,
        Key.sounds: true,
        Key.soundVolume: 0.3,
        Key.haptics: true,
        Key.notificationSounds: true,
    ]
}
