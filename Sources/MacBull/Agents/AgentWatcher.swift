import Foundation
import OSLog

/// Main-actor glue: owns the scan loop, the Claude Code hooks switch and bring-to-front. The scanning
/// itself happens in `AgentScanEngine`, off the main thread.
@MainActor
final class AgentWatcher: AgentWatching {
    /// Scan interval.
    static let scanInterval: Duration = .seconds(10)
    static let scanTolerance: Duration = .seconds(1)

    private(set) var hooksError: String?
    var onResult: (@MainActor (AgentScanResult) -> Void)?

    private let home: URL
    private let interval: Duration
    private let tolerance: Duration
    private let clock: @Sendable () -> Date
    private let ownPID: pid_t

    private var enabled = false
    private var config = AgentScanEngine.Config(customAgents: [], claudeHooks: false, stallWatchdog: false)
    private var appliedHooks: Bool?
    private var engine: AgentScanEngine?
    private var loop: Task<Void, Never>?
    /// Bumped on every start and stop; a scan that finishes under an older number is thrown away.
    private var generation = 0
    private var scanInFlight = false
    private var lastResult: AgentScanResult?
    private var wasWorking = false

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        interval: Duration = AgentWatcher.scanInterval,
        tolerance: Duration = AgentWatcher.scanTolerance,
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.home = home
        self.interval = interval
        self.tolerance = tolerance
        self.ownPID = ownPID
        self.clock = clock
    }

    // MARK: AgentWatching

    func configure(enabled: Bool, customAgents: [String], claudeHooks: Bool, stallWatchdog: Bool) {
        config = AgentScanEngine.Config(
            customAgents: CustomAgentNames.cleaned(customAgents), claudeHooks: claudeHooks, stallWatchdog: stallWatchdog
        )
        applyHooks(claudeHooks)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        guard enabled || engine != nil else { return }
        enabled = false
        generation += 1
        loop?.cancel()
        loop = nil
        scanInFlight = false
        lastResult = nil
        wasWorking = false
        if let engine {
            Task { await engine.shutdown() }
        }
        engine = nil
    }

    func bringToFront(sessionID: String) -> Bool {
        guard let pid = lastResult?.sessions.first(where: { $0.id == sessionID })?.pid else { return false }
        return HostApp.bringToFront(sessionPID: pid)
    }

    // MARK: Hooks

    /// Installs or removes the hooks when the setting changes, and once at the first call when it is on
    /// (self-healing). An error is kept for Settings; the setting itself is left as the user set it.
    private func applyHooks(_ wanted: Bool) {
        guard appliedHooks != wanted else { return }
        let isFirstCall = appliedHooks == nil
        appliedHooks = wanted
        guard wanted || !isFirstCall else { return }
        let paths = ClaudeHooks.Paths(home: home)
        do {
            if wanted {
                try ClaudeHooks.install(paths: paths)
                Log.agents.info("Claude Code hooks installed")
            } else {
                try ClaudeHooks.uninstall(paths: paths)
                Log.agents.info("Claude Code hooks removed")
            }
            hooksError = nil
        } catch {
            hooksError = error.localizedDescription
            Log.agents.error("Claude Code hooks: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Scanning

    private func start() {
        guard !enabled else { return }
        enabled = true
        generation += 1
        engine = AgentScanEngine(home: home, ownPID: ownPID)
        let interval = interval
        let tolerance = tolerance
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                do {
                    try await Task.sleep(for: interval, tolerance: tolerance)
                } catch {
                    return
                }
            }
        }
    }

    private func tick() {
        guard enabled, !scanInFlight, let engine else { return }
        scanInFlight = true
        let started = generation
        let config = config
        let now = clock()
        Task { [weak self] in
            let result = await engine.scan(config: config, now: now)
            self?.finish(result, generation: started)
        }
    }

    private func finish(_ result: AgentScanResult, generation started: Int) {
        guard started == generation else { return }
        scanInFlight = false
        guard enabled else { return }
        lastResult = result
        logTransition(result)
        onResult?(result)
    }

    private func logTransition(_ result: AgentScanResult) {
        guard result.anyWorking != wasWorking else { return }
        wasWorking = result.anyWorking
        let running = result.agents.map { "\($0.name) x\($0.sessions)" }.joined(separator: ", ")
        Log.agents.info("Agents \(result.anyWorking ? "working" : "not working", privacy: .public): \(running, privacy: .public)")
    }
}
