import AppKit
import Foundation

/// A session that waits for the user: one episode from first waiting to working, ended or gone.
struct TurnEpisode: Equatable {
    var since: Date
    var reminded = false
}

/// What the engine remembers between evaluations. Not shown to the UI.
struct EngineMemory {
    var started = false
    /// The interval the housekeeping tick runs at now.
    var tickSeconds = EngineTiming.tickSeconds
    var evaluating = false
    var reevaluate = false
    var quitRan = false
    /// When the system announced a logout, restart or shutdown. Only a recent one counts (see `isPoweringOff`).
    var powerOffAnnouncedAt: Date?

    /// Latest scan said an agent works.
    var agentsWorking = false
    /// Time of the scan that last saw an agent working (the grace period counts from it).
    var lastWorkingSeen: Date?
    /// Why the Mac stops being awake, set where the cause is known; read at the transition.
    var pendingEndReason: String?
    var journalAwake = false
    var armedEnd: Date?

    var lastBattery: (percent: Int, onAC: Bool)?
    var lastThermalLevel: Int?
    var lastPrune: Date?

    var awayStartedAt: Date?
    /// The journal's last event before this launch was not a clean quit.
    var crashedSince: Date?

    var knownSessions: [String: AgentSession] = [:]
    var turnEpisodes: [String: TurnEpisode] = [:]
    var stalledNotified: Set<String> = []

    var throttle = NotificationThrottle()
    var notificationsWereOn = false
    var lastStatusLine: String?
    var pendingURLs: [URL] = []
}

extension EngineMemory {
    /// A power-off notice is also sent when the user cancels a logout, so it only counts while the quit that
    /// follows a real one can still be to come. Waking or the user coming back clears it sooner.
    func isPoweringOff(at t: Date) -> Bool {
        guard let announced = powerOffAnnouncedAt else { return false }
        return t.timeIntervalSince(announced) < EngineTiming.powerOffNoticeSeconds
    }
}

/// The app model: owns every rule of keep-awake, agent hold, safety, notifications and receipts.
/// Services report facts and execute commands; this class decides.
@MainActor
final class AppModel: AppActions {
    let state: AppState
    let settings: Settings
    let power: any PowerAssertions
    let lid: any LidControlling
    let system: any SystemMonitoring
    let agents: any AgentWatching
    let journal: any EventJournaling
    let notifier: any Notifying
    let loginItem: any LoginItemControlling
    let scheduler: any Scheduling
    let now: @MainActor () -> Date
    let calendar: Calendar
    let terminate: @MainActor () -> Void

    /// Set after init, before `start()`.
    var panel: (any PanelPresenting)?
    var windows: (any WindowPresenting)?
    /// Called when the status line text changes (state change or tick). For the menu bar item.
    var onStatusLineChange: (@MainActor (String) -> Void)?

    var memory = EngineMemory()
    var tickTask: (any ScheduledTask)?
    var endTask: (any ScheduledTask)?

    init(
        state: AppState,
        settings: Settings,
        power: any PowerAssertions,
        lid: any LidControlling,
        system: any SystemMonitoring,
        agents: any AgentWatching,
        journal: any EventJournaling,
        notifier: any Notifying = UserNotificationsNotifier(),
        loginItem: any LoginItemControlling = SMAppLoginItem(),
        scheduler: any Scheduling = TimerScheduler(),
        now: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .current,
        terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        self.state = state
        self.settings = settings
        self.power = power
        self.lid = lid
        self.system = system
        self.agents = agents
        self.journal = journal
        self.notifier = notifier
        self.loginItem = loginItem
        self.scheduler = scheduler
        self.now = now
        self.calendar = calendar
        self.terminate = terminate
    }

    /// The tooltip, accessibility description and label text for the menu bar item.
    var statusLine: String {
        StatusLine.text(state: state, now: now())
    }

    // MARK: - Launch

    /// Call once, after `panel` and `windows` are set.
    func start() {
        guard !memory.started else { return }
        memory.started = true
        // First thing: undo anything a crashed run left behind.
        lid.restoreAtLaunch()
        lid.refreshSetup()

        let launchedAt = now()
        let previous = journal.previousRun()
        journal.record(.appLaunched, at: launchedAt)
        if let previous, !previous.cleanQuit { memory.crashedSince = previous.lastEventAt }
        state.receipts = Array(journal.savedReceipts().prefix(EngineTiming.maxSavedReceipts))
        // After the receipts are read: the prune runs on the journal queue and a read waits behind it.
        journal.prune(keepDays: settings.historyDays, now: launchedAt)
        memory.lastPrune = launchedAt

        connectServices()
        memory.notificationsWereOn = settings.notifications
        tickTask = scheduler.every(EngineTiming.tickSeconds) { [weak self] in self?.evaluate() }

        state.isAway = system.isAway
        if state.isAway { beginAway(at: launchedAt) }

        if settings.startOnLaunch {
            turnOn(minutes: nil)
        } else {
            evaluate()
        }
        if !settings.welcomeDone { windows?.openWelcome(.hello) }
        Log.engine.info("Started: lid \(String(describing: self.state.lidSetup), privacy: .public), agent mode \(self.settings.agentMode, privacy: .public)")
        let queued = memory.pendingURLs
        memory.pendingURLs = []
        handle(urls: queued)
    }

    private func connectServices() {
        settings.onChange = { [weak self] in self?.settingsChanged() }
        agents.onResult = { [weak self] result in self?.handleScan(result) }
        system.onEvent = { [weak self] event in self?.handleSystemEvent(event) }
        notifier.onActivate = { [weak self] in self?.showPanel() }
        system.start(keepAwakeActive: { [weak self] in self?.state.isAwake ?? false })
    }

    func settingsChanged() {
        let on = settings.notifications
        if on, !memory.notificationsWereOn { notifier.requestAuthorization() }
        memory.notificationsWereOn = on
        evaluate()
    }

    // MARK: - Quit

    func quit() {
        prepareForQuit()
        terminate()
    }

    /// Undo everything. Safe to call more than once: menu, Cmd+Q, signals and termination all end here.
    func prepareForQuit() {
        guard !memory.quitRan else { return }
        memory.quitRan = true
        state.quitting = true
        let t = now()
        tickTask?.cancel()
        endTask?.cancel()
        if memory.journalAwake {
            memory.journalAwake = false
            journal.record(.awakeEnded(reason: "quit"), at: t)
        }
        journal.record(.appQuit, at: t)
        state.manual = nil
        state.agentHold = false
        state.agentHoldSince = nil
        agents.stop()
        power.set(preventSystemSleep: false, preventDisplaySleep: false)
        lid.cleanUpForQuit(systemPoweringOff: memory.isPoweringOff(at: t))
        state.lidHeld = lid.isHeld
        // Last: the writes are queued, and the process is about to exit.
        journal.flush()
        Log.engine.info("Quit: holds released")
    }

    // MARK: - AppActions

    func turnOn(minutes: Int?) {
        let requested = max(minutes ?? settings.defaultMinutes, 0)
        let t = now()
        let end = requested > 0 ? t.addingTimeInterval(Double(requested) * EngineTiming.secondsPerMinute) : nil
        state.manual = ManualSession(minutes: requested, startedAt: t, endsAt: end)
        // A new awake period clears the note of the last stop.
        state.cutoff = nil
        Log.engine.info("Turned on for \(requested, privacy: .public) min (0 means until off)")
        evaluate()
    }

    func turnOff() {
        endEverything(reason: "user")
    }

    func toggle() {
        if state.isAwake {
            turnOff()
        } else {
            turnOn(minutes: nil)
        }
    }

    func sleepNow() {
        endEverything(reason: "sleepNow")
        lid.sleepNow()
    }

    /// The user (or Sleep Now) turns off: the manual session ends, and an agent hold ends into the pause.
    private func endEverything(reason: String) {
        state.manual = nil
        if state.agentHold {
            state.agentHold = false
            state.agentHoldSince = nil
            state.paused = true
        }
        memory.pendingEndReason = reason
        Log.engine.info("Turned off (\(reason, privacy: .public))")
        evaluate()
    }

    func installLid() async -> LidSetupResult {
        let result = await lid.install()
        lid.refreshSetup()
        syncLidState()
        evaluate()
        return result
    }

    func removeLid() async -> LidSetupResult {
        let result = await lid.uninstall()
        lid.refreshSetup()
        syncLidState()
        evaluate()
        return result
    }

    func bringToFront(sessionID: String) -> Bool {
        agents.bringToFront(sessionID: sessionID)
    }

    func showPanel() {
        guard let panel, !panel.isPanelShown else { return }
        panel.showPanel()
    }

    func openSettings(_ tab: SettingsTab) {
        windows?.openSettings(tab)
    }

    func openWelcome(_ step: WelcomeStep) {
        windows?.openWelcome(step)
    }

    func dismissReceipt() {
        state.latestReceipt = nil
    }

    func nutrition(_ range: StatsRange) -> NutritionStats {
        journal.nutrition(range, now: now())
    }

    func eraseHistory() {
        journal.eraseAll()
        state.receipts = []
        state.latestReceipt = nil
    }

    func loginItemStatus() -> LoginItemStatus {
        loginItem.status()
    }

    func setLoginItem(_ enabled: Bool) -> LoginItemStatus {
        loginItem.setEnabled(enabled)
    }

    // MARK: - URL commands

    /// Several URLs delivered together are handled in order. Before `start()` they wait.
    func handle(urls: [URL]) {
        guard memory.started else {
            memory.pendingURLs.append(contentsOf: urls)
            return
        }
        for url in urls {
            guard let command = URLCommand.parse(url) else {
                Log.engine.notice("Unknown URL command ignored: \(url.host ?? "none", privacy: .public)")
                continue
            }
            perform(command)
        }
    }

    func perform(_ command: URLCommand) {
        switch command {
        case .on(let minutes): turnOn(minutes: minutes)
        case .off: turnOff()
        case .toggle: toggle()
        case .panel: showPanel()
        case .settings(let tab): openSettings(tab)
        case .welcome(let step): openWelcome(step)
        }
    }
}
