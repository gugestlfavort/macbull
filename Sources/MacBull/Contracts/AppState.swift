import Foundation
import Observation

/// Everything the UI shows. Only the engine writes it; views read it.
@MainActor
@Observable
final class AppState {
    var manual: ManualSession?
    var agentHold = false
    var agentHoldSince: Date?
    /// Turned off (or cut off) while agents worked: not held again until they are quiet for the grace period.
    var paused = false
    /// Last safety stop; shown only while not awake.
    var cutoff: SafetyStop?

    var lidSetup: LidSetup = .notSetUp
    /// disablesleep is on because of MacBull.
    var lidHeld = false
    /// Lid shut and no external display.
    var closedInBag = false
    var lidError: String?

    var onBattery = false
    var batteryPercent: Int?
    var thermal: ProcessInfo.ThermalState = .nominal

    var agents: [AgentSummary] = []
    var sessions: [AgentSession] = []
    /// Increments once per Claude Code tool call (Live Carbonation bubbles).
    var toolPulses = 0
    var hooksError: String?

    /// The user is away from the Mac (locked, display asleep, lid shut or idle).
    var isAway = false
    /// Shown at the top of the panel until dismissed.
    var latestReceipt: Receipt?
    /// Most recent first, at most 10.
    var receipts: [Receipt] = []

    var quitting = false

    var isAwake: Bool { manual != nil || agentHold }

    var waitingCount: Int {
        sessions.filter { $0.activity == .waitingForYou }.count
    }

    var menuIconBase: MenuIconBase {
        if !isAwake { return cutoff == nil ? .off : .cutoff }
        return manual != nil ? .on : .agents
    }
}
