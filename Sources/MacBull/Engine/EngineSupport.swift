import Foundation

/// Every timing the engine uses, in one place.
enum EngineTiming {
    /// Housekeeping tick while something needs watching: awake (the manual end time, the idle rule, the
    /// countdown in the tooltip), away, or a session waiting for the user (reminders).
    static let tickSeconds: TimeInterval = 5
    /// Housekeeping tick when none of that holds. Facts that matter then (a power source, a scan, a wake, a
    /// notification, the manual end timer) start their own evaluation; this only catches slow, time-based ones.
    static let idleTickSeconds: TimeInterval = 30
    /// A hold shorter than this is a blip (an agent restarting), not work worth reporting.
    static let minimumHoldForDoneNoticeSeconds: TimeInterval = 120
    /// One notification per kind in this window, so a Mac that flaps around a limit does not spam.
    static let notificationThrottleSeconds: TimeInterval = 300
    /// "The user is at the Mac" means input within this window (Your Turn reminders).
    static let userAtMacWindowSeconds: TimeInterval = 120
    /// History is pruned at launch and then once a day.
    static let pruneIntervalSeconds: TimeInterval = 86_400
    /// A logout, restart or shutdown notice is trusted this long. It also arrives when a logout is cancelled.
    static let powerOffNoticeSeconds: TimeInterval = 60
    static let secondsPerMinute: TimeInterval = 60
    static let maxSavedReceipts = 10
    /// A safety net against two parts of the system feeding each other events.
    static let maxEvaluationPasses = 3
}

extension ProcessInfo.ThermalState {
    /// 0 nominal, 1 fair, 2 serious, 3 critical (the journal's scale).
    var level: Int {
        switch self {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        @unknown default: 3
        }
    }
}

/// What the safety guards look at.
struct SafetyInput: Equatable {
    var batteryGuard: Bool
    var batteryThresholdPercent: Int
    var heatGuard: Bool
    var onBattery: Bool
    var batteryPercent: Int?
    var thermal: ProcessInfo.ThermalState
    /// The lid hold is, or would be, active: set up and the setting is on.
    var lidHoldPossible: Bool
    var closedInBag: Bool
}

enum SafetyRules {
    static func batteryIsLow(_ input: SafetyInput) -> Bool {
        guard input.batteryGuard, input.onBattery, let percent = input.batteryPercent else { return false }
        return percent <= input.batteryThresholdPercent
    }

    static func isTooHot(_ input: SafetyInput) -> Bool {
        guard input.heatGuard else { return false }
        switch input.thermal {
        case .serious, .critical:
            return true
        case .fair:
            // A closed Mac in a bag cannot shed heat, so it gives up at the first warm level.
            return input.lidHoldPossible && input.closedInBag
        case .nominal:
            return false
        @unknown default:
            return true
        }
    }

    /// Heat is checked before battery; only one reason is recorded.
    static func stop(for input: SafetyInput) -> SafetyStop? {
        if isTooHot(input) { return .heat }
        if batteryIsLow(input) { return .battery }
        return nil
    }

    /// Whether the note of an earlier stop should still be shown.
    static func noteStillApplies(_ stop: SafetyStop, _ input: SafetyInput) -> Bool {
        switch stop {
        case .battery: batteryIsLow(input)
        case .heat: input.thermal != .nominal
        }
    }
}

/// What to assert and ask of the lid hold, from the facts.
struct PowerPlan: Equatable {
    var preventSystemSleep: Bool
    var preventDisplaySleep: Bool
    var lidHoldWanted: Bool
    var lowPowerWanted: Bool

    struct Facts {
        var isAwake: Bool
        var manualActive: Bool
        var keepDisplayOn: Bool
        var lidReady: Bool
        var lidSetting: Bool
        var lowPowerSetting: Bool
        var closedInBag: Bool
        var onBattery: Bool
        var quitting: Bool
    }

    static func make(_ facts: Facts) -> PowerPlan {
        let lidAllowed = facts.lidReady && facts.lidSetting
        let holdWanted = facts.isAwake && lidAllowed && !facts.quitting
        // Closed in a bag and the lid mode may not hold it: let the Mac sleep normally.
        let system = facts.isAwake && !(facts.closedInBag && !lidAllowed)
        let display = facts.manualActive && facts.keepDisplayOn && !facts.closedInBag
        let lowPower = holdWanted && facts.closedInBag && facts.onBattery && facts.lowPowerSetting
        return PowerPlan(
            preventSystemSleep: system,
            preventDisplaySleep: display,
            lidHoldWanted: holdWanted,
            lowPowerWanted: lowPower
        )
    }
}

enum QuietHours {
    /// Hours are 0-23. Equal values mean no quiet hours; start after end wraps past midnight.
    static func contains(hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        if start < end { return hour >= start && hour < end }
        return hour >= start || hour < end
    }
}

/// One notification per kind per window, measured from the last one actually posted.
struct NotificationThrottle {
    enum Kind: Hashable, Sendable {
        case heat
        case battery
        case agentsDone
    }

    private var lastPosted: [Kind: Date] = [:]

    /// True and recorded when a notification of this kind may go out now.
    mutating func allow(_ kind: Kind, at now: Date, window: TimeInterval = EngineTiming.notificationThrottleSeconds) -> Bool {
        if let last = lastPosted[kind], now.timeIntervalSince(last) < window { return false }
        lastPosted[kind] = now
        return true
    }
}
