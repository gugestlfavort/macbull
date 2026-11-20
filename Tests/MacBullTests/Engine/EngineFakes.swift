import Foundation
@testable import MacBull

/// Fakes for every protocol the engine talks to, namespaced so other modules' test files cannot clash.
enum EngineFakes {
    @MainActor
    final class Power: PowerAssertions {
        private(set) var calls: [(system: Bool, display: Bool)] = []
        var last: (system: Bool, display: Bool)? { calls.last }

        func set(preventSystemSleep: Bool, preventDisplaySleep: Bool) {
            calls.append((preventSystemSleep, preventDisplaySleep))
        }
    }

    struct ApplyCall: Equatable {
        var holdWanted: Bool
        var closedInBag: Bool
        var onBattery: Bool
        var lowPowerWanted: Bool
    }

    @MainActor
    final class Lid: LidControlling {
        var setup: LidSetup = .ready
        var isHeld = false
        var lastError: String?
        private(set) var applyCalls: [ApplyCall] = []
        private(set) var events: [String] = []
        var last: ApplyCall? { applyCalls.last }

        func refreshSetup() { events.append("refresh") }
        func restoreAtLaunch() { events.append("restore") }
        /// What the real controller does while the privileged call runs: it changes `setup` and `lastError`.
        var duringInstall: (() -> Void)?
        var duringUninstall: (() -> Void)?

        func install() async -> LidSetupResult {
            duringInstall?()
            return .success
        }

        func uninstall() async -> LidSetupResult {
            duringUninstall?()
            return .cancelled
        }

        func apply(holdWanted: Bool, closedInBag: Bool, onBattery: Bool, lowPowerWanted: Bool) {
            applyCalls.append(ApplyCall(holdWanted: holdWanted, closedInBag: closedInBag, onBattery: onBattery, lowPowerWanted: lowPowerWanted))
            isHeld = holdWanted
        }

        func sleepNow() { events.append("sleepNow") }
        func cleanUpForQuit(systemPoweringOff: Bool) { events.append("cleanUp(\(systemPoweringOff))") }
    }

    @MainActor
    final class System: SystemMonitoring {
        var hasLid = true
        var lidClosed = false
        var hasExternalDisplay = false
        private var storedPercent: Int? = 80
        private var storedOnBattery = false
        private(set) var batteryPercentReads = 0
        private(set) var onBatteryReads = 0
        var batteryPercent: Int? {
            get {
                batteryPercentReads += 1
                return storedPercent
            }
            set { storedPercent = newValue }
        }
        var onBattery: Bool {
            get {
                onBatteryReads += 1
                return storedOnBattery
            }
            set { storedOnBattery = newValue }
        }
        var lowPowerModeOn = false
        var thermal: ProcessInfo.ThermalState = .nominal
        var secondsSinceInput: TimeInterval = 0
        var isAway = false
        var onEvent: (@MainActor (SystemEvent) -> Void)?
        private(set) var wakeScreenCalls = 0
        private(set) var started = false

        func resetReadCounts() {
            batteryPercentReads = 0
            onBatteryReads = 0
        }

        func start(keepAwakeActive: @escaping @MainActor () -> Bool) { started = true }
        func wakeScreen() { wakeScreenCalls += 1 }
        func send(_ event: SystemEvent) { onEvent?(event) }
    }

    @MainActor
    final class Agents: AgentWatching {
        var hooksError: String?
        var onResult: (@MainActor (AgentScanResult) -> Void)?
        private(set) var configured: [(enabled: Bool, custom: [String], hooks: Bool, stall: Bool)] = []
        private(set) var stopped = false
        var frontResult = true
        private(set) var frontRequests: [String] = []

        /// What the real watcher does when configured: hooks are installed, or fail with a message.
        var hooksErrorAfterConfigure: String??

        func configure(enabled: Bool, customAgents: [String], claudeHooks: Bool, stallWatchdog: Bool) {
            configured.append((enabled, customAgents, claudeHooks, stallWatchdog))
            if let outcome = hooksErrorAfterConfigure { hooksError = outcome }
        }

        func bringToFront(sessionID: String) -> Bool {
            frontRequests.append(sessionID)
            return frontResult
        }

        func stop() { stopped = true }
        func deliver(_ result: AgentScanResult) { onResult?(result) }
    }

    @MainActor
    final class Journal: EventJournaling {
        private(set) var events: [JournalEvent] = []
        var previous: (lastEventAt: Date, cleanQuit: Bool)?
        var nextReceipt: Receipt?
        private(set) var saved: [Receipt] = []
        private(set) var prunes: [(keepDays: Int, now: Date)] = []
        private(set) var erased = false
        /// How many events had been recorded each time `flush` was called.
        private(set) var flushedAfter: [Int] = []
        private(set) var receiptWindows: [(from: Date, to: Date)] = []

        var kinds: [JournalEventKind] { events.map(\.kind) }

        func record(_ kind: JournalEventKind, at: Date) { events.append(JournalEvent(at: at, kind: kind)) }

        func receipt(from: Date, to: Date) -> Receipt {
            receiptWindows.append((from, to))
            var built = nextReceipt ?? Receipt(
                id: UUID(), awayFrom: from, awayTo: to, lines: [], batteryStart: nil, batteryEnd: nil,
                pluggedIn: false, peakThermal: 0, sleptAt: [], safetyStop: nil, notRunningSince: nil
            )
            built.awayFrom = from
            built.awayTo = to
            return built
        }

        func savedReceipts() -> [Receipt] { saved }
        func save(_ receipt: Receipt) { saved.insert(receipt, at: 0) }
        func nutrition(_ range: StatsRange, now: Date) -> NutritionStats { .empty }
        func previousRun() -> (lastEventAt: Date, cleanQuit: Bool)? { previous }
        func prune(keepDays: Int, now: Date) { prunes.append((keepDays, now)) }
        func eraseAll() { erased = true }
        func flush() { flushedAfter.append(events.count) }
    }

    @MainActor
    final class Notifier: Notifying {
        var onActivate: (@MainActor () -> Void)?
        private(set) var posted: [AppNotification] = []
        private(set) var withdrawn: [String] = []
        private(set) var authorizationRequests = 0

        func requestAuthorization() { authorizationRequests += 1 }
        func post(_ notification: AppNotification) { posted.append(notification) }
        func withdraw(identifier: String) { withdrawn.append(identifier) }
    }

    @MainActor
    final class LoginItem: LoginItemControlling {
        var current: LoginItemStatus = .disabled

        func status() -> LoginItemStatus { current }

        func setEnabled(_ enabled: Bool) -> LoginItemStatus {
            current = enabled ? .enabled : .disabled
            return current
        }
    }

    @MainActor
    final class Task: ScheduledTask {
        let interval: TimeInterval
        let repeats: Bool
        let action: @MainActor () -> Void
        private(set) var cancelled = false

        init(interval: TimeInterval, repeats: Bool, action: @escaping @MainActor () -> Void) {
            self.interval = interval
            self.repeats = repeats
            self.action = action
        }

        func cancel() { cancelled = true }
    }

    @MainActor
    final class Scheduler: Scheduling {
        private(set) var tasks: [Task] = []

        var live: [Task] { tasks.filter { !$0.cancelled } }
        var ticks: [Task] { live.filter(\.repeats) }
        var oneShots: [Task] { live.filter { !$0.repeats } }

        func every(_ interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
            let task = Task(interval: interval, repeats: true, action: action)
            tasks.append(task)
            return task
        }

        func after(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
            let task = Task(interval: delay, repeats: false, action: action)
            tasks.append(task)
            return task
        }

        func fireTicks() { ticks.forEach { $0.action() } }
        func fireOneShots() { oneShots.forEach { $0.action() } }
    }

    @MainActor
    final class Panel: PanelPresenting {
        var isPanelShown = false
        private(set) var showCalls = 0

        func showPanel() {
            showCalls += 1
            isPanelShown = true
        }

        func closePanel() { isPanelShown = false }
    }

    @MainActor
    final class Windows: WindowPresenting {
        private(set) var settingsTabs: [SettingsTab] = []
        private(set) var welcomeSteps: [WelcomeStep] = []

        func openSettings(_ tab: SettingsTab) { settingsTabs.append(tab) }
        func openWelcome(_ step: WelcomeStep) { welcomeSteps.append(step) }
    }

    /// The injected clock: tests move it by hand, never the wall clock.
    @MainActor
    final class Clock {
        /// 2027-01-15 08:00:00 UTC, midday-ish and far from midnight.
        static let start = Date(timeIntervalSince1970: 1_800_000_000)
        var date = Clock.start

        func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
        func advance(minutes: Double) { advance(minutes * 60) }
    }
}

/// A fully wired model with fakes, plus helpers to build scan results.
@MainActor
struct EngineRig {
    let state = AppState()
    let settings: Settings
    let power = EngineFakes.Power()
    let lid = EngineFakes.Lid()
    let system = EngineFakes.System()
    let agents = EngineFakes.Agents()
    let journal = EngineFakes.Journal()
    let notifier = EngineFakes.Notifier()
    let loginItem = EngineFakes.LoginItem()
    let panel = EngineFakes.Panel()
    let windows = EngineFakes.Windows()
    let scheduler = EngineFakes.Scheduler()
    let clock = EngineFakes.Clock()
    let model: AppModel
    let terminated = TerminateCounter()

    @MainActor
    final class TerminateCounter {
        var count = 0
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    init(started: Bool = true, configure: (Settings) -> Void = { _ in }) {
        let suite = "macbull.engine.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        settings = Settings(defaults: defaults)
        settings.welcomeDone = true
        configure(settings)
        let clock = clock
        let terminated = terminated
        model = AppModel(
            state: state, settings: settings, power: power, lid: lid, system: system, agents: agents,
            journal: journal, notifier: notifier, loginItem: loginItem, scheduler: scheduler,
            now: { clock.date }, calendar: Self.utc, terminate: { terminated.count += 1 }
        )
        model.panel = panel
        model.windows = windows
        if started { model.start() }
    }

    func advance(minutes: Double) {
        clock.advance(minutes: minutes)
    }

    /// Advance and run the 5 s housekeeping tick once.
    func tick(afterMinutes minutes: Double = 0) {
        clock.advance(minutes: minutes)
        scheduler.fireTicks()
    }

    func session(
        _ activity: SessionActivity = .working, id: String = "s1", agent: String = "Claude Code",
        folder: String? = "api", since: Date? = nil
    ) -> AgentSession {
        let began = since ?? clock.date
        return AgentSession(id: id, agent: agent, folder: folder, activity: activity, since: began, lastSignOfLife: began, isExact: true, pid: nil)
    }

    func scan(_ sessions: [AgentSession], working: Bool? = nil, toolEvents: Int = 0) {
        let anyWorking = working ?? sessions.contains { [.working, .backgroundRun, .running].contains($0.activity) }
        let names = Dictionary(grouping: sessions, by: \.agent)
        let summaries = names.keys.sorted().map { name in
            let group = names[name] ?? []
            return AgentSummary(
                name: name, sessions: group.count, isWorking: group.contains { $0.activity == .working },
                backgroundRuns: 0, isCustom: false, waitingForYou: group.filter { $0.activity == .waitingForYou }.count,
                stalled: group.filter { $0.activity == .stalled }.count
            )
        }
        agents.deliver(AgentScanResult(agents: summaries, sessions: sessions, anyWorking: anyWorking, toolEvents: toolEvents))
    }

    func receipt(lines: [ReceiptLine] = [], notRunningSince: Date? = nil, batteryStart: Int? = nil, batteryEnd: Int? = nil) -> Receipt {
        Receipt(
            id: UUID(), awayFrom: clock.date, awayTo: clock.date, lines: lines, batteryStart: batteryStart,
            batteryEnd: batteryEnd, pluggedIn: false, peakThermal: 0, sleptAt: [], safetyStop: nil,
            notRunningSince: notRunningSince
        )
    }
}
