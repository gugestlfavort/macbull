import Foundation

/// The off-main-thread half of the watcher: reads the process table, drains hook events, asks the log
/// monitor what was written, and lets the judge decide. It owns every piece of state that has to survive
/// from one scan to the next, including hook records (events are deleted from disk when read, so they
/// are kept even when the scan that read them is later thrown away).
actor AgentScanEngine {
    struct Config: Equatable, Sendable {
        var customAgents: [String]
        var claudeHooks: Bool
        var stallWatchdog: Bool
    }

    private let ownPID: pid_t
    private let hookPaths: ClaudeHooks.Paths
    private let logs: LogActivityMonitor
    private var scanner = ProcessScanner()
    private var tracker = ClaudeHookTracker()
    private var judge = AgentJudge()
    private var previous: ProcessSnapshot?

    init(home: URL, ownPID: pid_t) {
        self.ownPID = ownPID
        hookPaths = ClaudeHooks.Paths(home: home)
        logs = LogActivityMonitor(home: home, agents: AgentCatalogue.builtIn)
    }

    func scan(config: Config, now: Date) -> AgentScanResult {
        let definitions = AgentCatalogue.builtIn + CustomAgentNames.definitions(for: config.customAgents)
        let matcher = AgentMatcher(definitions: definitions)
        let logFacts = logs.refresh(now: now)
        let snapshot = scanner.scan(matcher: matcher, now: now)

        let toolEvents = readHookEvents(config: config)
        let recognition = AgentRecognizer.recognise(table: snapshot.table, matcher: matcher, ownPID: ownPID)
        if config.claudeHooks {
            tracker.resolve(
                table: snapshot.table, sessions: recognition.sessions(ofAgent: AgentCatalogue.claudeID),
                directories: snapshot.directories, now: now
            )
        }
        let verdicts = config.claudeHooks ? tracker.verdicts(now: now) : [:]

        let result = judge.judge(AgentJudge.Input(
            now: now, snapshot: snapshot, previous: previous, definitions: definitions, logs: logFacts,
            verdicts: verdicts, stallWatchdog: config.stallWatchdog, ownPID: ownPID, toolEvents: toolEvents
        ))
        previous = snapshot
        return result
    }

    /// Hook events read since the last scan go into the tracker; returns how many were tool calls.
    private func readHookEvents(config: Config) -> Int {
        guard config.claudeHooks else {
            tracker = ClaudeHookTracker()
            return 0
        }
        let events = ClaudeHookEvents.drain(folder: hookPaths.events)
        tracker.ingest(events)
        return events.filter { $0.name == "PostToolUse" }.count
    }

    func shutdown() {
        logs.stop()
    }
}
