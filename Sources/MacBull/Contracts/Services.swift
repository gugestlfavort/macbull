import Foundation

// The seams between modules. Each module implements its protocol; the engine only talks to these.

/// What the user (UI, URL commands) can ask for. Implemented by the engine.
@MainActor
protocol AppActions: AnyObject {
    /// nil uses the default duration; 0 means until turned off.
    func turnOn(minutes: Int?)
    func turnOff()
    func toggle()
    func sleepNow()
    func installLid() async -> LidSetupResult
    func removeLid() async -> LidSetupResult
    /// Bring the terminal or app hosting this session to the front. Returns false when it cannot.
    func bringToFront(sessionID: String) -> Bool
    func showPanel()
    func openSettings(_ tab: SettingsTab)
    func openWelcome(_ step: WelcomeStep)
    func dismissReceipt()
    func nutrition(_ range: StatsRange) -> NutritionStats
    func eraseHistory()
    func loginItemStatus() -> LoginItemStatus
    func setLoginItem(_ enabled: Bool) -> LoginItemStatus
    func quit()
}

/// IOKit power assertions. Implemented in Power.
@MainActor
protocol PowerAssertions: AnyObject {
    func set(preventSystemSleep: Bool, preventDisplaySleep: Bool)
}

/// Lid-closed mode: sudoers rule, boot-reset daemon, flags, watchdog, pmset. Implemented in Power.
@MainActor
protocol LidControlling: AnyObject {
    var setup: LidSetup { get }
    /// disablesleep currently on because of MacBull.
    var isHeld: Bool { get }
    var lastError: String? { get }
    /// Re-read setup validity (launch, after install/remove, after a failed enable).
    func refreshSetup()
    /// Undo flags left by a crash. Called first thing at launch.
    func restoreAtLaunch()
    func install() async -> LidSetupResult
    func uninstall() async -> LidSetupResult
    /// Bring pmset in line with what is wanted. Idempotent; handles flags, watchdog, retries,
    /// display-off on entering the bag, Low Power Mode and sleeping a bagged Mac on release.
    func apply(holdWanted: Bool, closedInBag: Bool, onBattery: Bool, lowPowerWanted: Bool)
    /// pmset sleepnow.
    func sleepNow()
    /// Undo everything at quit. Puts a bagged Mac to sleep unless the system is powering off.
    func cleanUpForQuit(systemPoweringOff: Bool)
}

enum SystemEvent: Equatable, Sendable {
    case willSleep
    case didWake
    case thermalChanged
    case powerSourceChanged
    case displaysChanged
    case lidChanged
    case awayStarted
    case awayEnded
    /// Logout, restart or shutdown in progress.
    case powerOff
}

/// Battery, heat, lid, displays, presence. Implemented in Power.
@MainActor
protocol SystemMonitoring: AnyObject {
    var hasLid: Bool { get }
    var lidClosed: Bool { get }
    var hasExternalDisplay: Bool { get }
    var batteryPercent: Int? { get }
    var onBattery: Bool { get }
    var lowPowerModeOn: Bool { get }
    var thermal: ProcessInfo.ThermalState { get }
    var secondsSinceInput: TimeInterval { get }
    var isAway: Bool { get }
    var onEvent: (@MainActor (SystemEvent) -> Void)? { get set }
    /// `keepAwakeActive` lets the idle rule apply only while MacBull holds the Mac awake.
    func start(keepAwakeActive: @escaping @MainActor () -> Bool)
    /// Light a sleeping display once (user activity assertion).
    func wakeScreen()
}

/// Finds agents and judges them. Implemented in Agents.
@MainActor
protocol AgentWatching: AnyObject {
    var hooksError: String? { get }
    var onResult: (@MainActor (AgentScanResult) -> Void)? { get set }
    /// Start, stop or reconfigure. Safe to call on every evaluation; only changes take effect.
    func configure(enabled: Bool, customAgents: [String], claudeHooks: Bool, stallWatchdog: Bool)
    func bringToFront(sessionID: String) -> Bool
    func stop()
}

/// Local event journal, receipts and stats. Implemented in Journal.
@MainActor
protocol EventJournaling: AnyObject {
    func record(_ kind: JournalEventKind, at: Date)
    /// Builds the receipt for an away window from the journal.
    func receipt(from: Date, to: Date) -> Receipt
    /// Saved receipts, most recent first (at most 10).
    func savedReceipts() -> [Receipt]
    func save(_ receipt: Receipt)
    func nutrition(_ range: StatsRange, now: Date) -> NutritionStats
    /// Time of the last event before this launch and whether it was a clean quit.
    func previousRun() -> (lastEventAt: Date, cleanQuit: Bool)?
    func prune(keepDays: Int, now: Date)
    func eraseAll()
    /// Returns once every queued write is on disk. Called at quit, so the last events are not lost.
    func flush()
}

/// Panel and menu bar item. Implemented in UI/MenuBar.
@MainActor
protocol PanelPresenting: AnyObject {
    var isPanelShown: Bool { get }
    func showPanel()
    func closePanel()
}

/// Settings and Welcome windows. Implemented in UI/Windows.
@MainActor
protocol WindowPresenting: AnyObject {
    func openSettings(_ tab: SettingsTab)
    func openWelcome(_ step: WelcomeStep)
}

/// Sounds and haptics while the panel is open. Implemented in UI/Feedback.
@MainActor
protocol FeedbackPlaying: AnyObject {
    func play(_ cue: SoundCue)
    /// Fizz loop while pouring; the level (0...1) sets the volume; nil stops it.
    func setFizz(_ level: Double?)
    /// Trackpad detent; `strong` for the until-off stop.
    func detent(strong: Bool)
}

/// What the UI gets: read state and settings, call actions, play feedback.
@MainActor
final class AppEnvironment {
    let state: AppState
    let settings: Settings
    let actions: AppActions
    let feedback: FeedbackPlaying

    init(state: AppState, settings: Settings, actions: AppActions, feedback: FeedbackPlaying) {
        self.state = state
        self.settings = settings
        self.actions = actions
        self.feedback = feedback
    }
}
