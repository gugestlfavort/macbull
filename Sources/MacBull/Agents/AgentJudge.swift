import Foundation

/// Decides, for each scan, what every agent session is doing. Pure: the previous state it keeps, the
/// snapshot, the log facts, the hook verdicts and `now` go in; an `AgentScanResult` comes out.
/// Covers the working/idle rules, the Your Turn mapping and the Stall Watchdog.
struct AgentJudge {
    // MARK: Thresholds

    /// The tree is busy at this share of one core.
    static let busyCPUShare = 0.10
    /// More CPU than this in one interval is a sign of life (a run hung on the network ticks at about 0.03 s).
    static let signOfLifeCPUSeconds = 0.3
    /// A shell below the session younger than this is a running tool call; older ones are left-over servers.
    static let toolCallMaxAge: TimeInterval = 30 * 60
    /// Descendants that start this soon after the session are helpers (MCP servers and the like).
    static let helperStartWindow: TimeInterval = 60
    /// A log write counts for this long.
    static let logWindow: TimeInterval = 90
    /// A one-shot run without a sign of life for this long stops counting.
    static let oneShotStaleAfter: TimeInterval = 20 * 60
    /// With the Stall Watchdog on: no sign of life for this long and a working session is stalled.
    static let stallAfter: TimeInterval = 10 * 60
    static let elapsedRange: ClosedRange<TimeInterval> = 1...60

    private static let helperNameParts = [
        "google chrome", "chromium", "chrome-headless-shell", "chrome", "electron",
        "language-server", "tsserver", "sourcekit-lsp", "rust-analyzer", "gopls",
    ]

    struct Input {
        var now: Date
        var snapshot: ProcessSnapshot
        /// The previous scan; nil on the first one, which only takes a CPU baseline and never reports work.
        var previous: ProcessSnapshot?
        var definitions: [AgentDefinition]
        var logs: LogFacts
        var verdicts: [ProcessKey: HookVerdict]
        var stallWatchdog: Bool
        var ownPID: pid_t
        var toolEvents: Int
    }

    private struct Memory {
        var activity: SessionActivity
        var since: Date
        var lastSignOfLife: Date
    }

    private enum LogWrite {
        case none
        case counting
        /// The project folder does not exist yet, so any write by the agent counts, except to keep a one-shot run alive.
        case fallback
    }

    private struct Judgement {
        var activity: SessionActivity
        /// Counts for keep-awake.
        var counts: Bool
        /// When the activity began, if the evidence says; nil means "now".
        var began: Date?
    }

    private var memory: [ProcessKey: Memory] = [:]

    mutating func judge(_ input: Input) -> AgentScanResult {
        let matcher = AgentMatcher(definitions: input.definitions)
        let recognition = AgentRecognizer.recognise(table: input.snapshot.table, matcher: matcher, ownPID: input.ownPID)
        var judged: [(process: RecognisedProcess, session: AgentSession, counts: Bool)] = []
        var next: [ProcessKey: Memory] = [:]
        for process in recognition.sessions {
            let key = ProcessKey(process.entry)
            let verdict = input.verdicts[key]
            let signOfLife = signOfLife(for: process, key: key, verdict: verdict, recognition: recognition, input: input)
            let judgement = judgement(for: process, verdict: verdict, signOfLife: signOfLife, input: input)
            let remembered = memory[key]
            let since = remembered?.activity == judgement.activity
                ? (remembered?.since ?? input.now)
                : min(judgement.began ?? input.now, input.now)
            next[key] = Memory(activity: judgement.activity, since: since, lastSignOfLife: signOfLife.time)
            let session = AgentSession(
                id: verdict?.sessionID ?? Self.fallbackID(process.entry),
                agent: process.agent.name,
                folder: Self.folder(verdict?.cwd ?? input.snapshot.directories[process.entry.pid]),
                activity: judgement.activity, since: since, lastSignOfLife: signOfLife.time,
                isExact: verdict != nil, pid: process.entry.pid
            )
            judged.append((process, session, judgement.counts))
        }
        memory = next
        return Self.result(judged, definitions: input.definitions, toolEvents: input.toolEvents)
    }

    static func fallbackID(_ entry: ProcessTable.Entry) -> String {
        "\(entry.pid)-\(Int(entry.startTime))"
    }

    /// Last path component of the working directory, never the whole path.
    static func folder(_ directory: String?) -> String? {
        guard let directory, !directory.isEmpty else { return nil }
        let name = ProcessNames.lastComponent(directory)
        // The root folder has no name of its own.
        if name.isEmpty { return directory }
        return name
    }

    // MARK: Per session

    private func judgement(
        for process: RecognisedProcess, verdict: HookVerdict?, signOfLife: (time: Date, busy: Bool, log: LogWrite),
        input: Input
    ) -> Judgement {
        let isBaseline = input.previous == nil
        if process.agent.isCustom {
            return isBaseline ? Judgement(activity: .idle, counts: false) : Judgement(activity: .running, counts: true)
        }
        if let verdict {
            return fromVerdict(verdict, oneShot: process.kind == .oneShot, signOfLife: signOfLife.time, input: input)
        }
        if isBaseline { return Judgement(activity: .idle, counts: false) }
        if process.kind == .oneShot {
            return oneShotJudgement(signOfLife: signOfLife.time, input: input)
        }
        let working = signOfLife.busy || signOfLife.log != .none
        return Judgement(activity: working ? .working : .idle, counts: working)
    }

    private func fromVerdict(_ verdict: HookVerdict, oneShot: Bool, signOfLife: Date, input: Input) -> Judgement {
        switch verdict.state {
        case .waitingForYou:
            return Judgement(activity: .waitingForYou, counts: false, began: verdict.changedAt)
        case .turnDone:
            return Judgement(activity: .turnDone, counts: false, began: verdict.changedAt)
        case .ended:
            return Judgement(activity: .ended, counts: false, began: verdict.changedAt)
        case .working:
            if input.previous == nil { return Judgement(activity: .idle, counts: false) }
            let base = Judgement(activity: oneShot ? .backgroundRun : .working, counts: true, began: verdict.changedAt)
            return stalled(base, signOfLife: signOfLife, input: input)
        }
    }

    /// A one-shot run works while it is alive and its last sign of life is under 20 minutes old.
    private func oneShotJudgement(signOfLife: Date, input: Input) -> Judgement {
        let silence = input.now.timeIntervalSince(signOfLife)
        guard silence < Self.oneShotStaleAfter else {
            // The Stall Watchdog keeps showing it; either way it no longer counts.
            return input.stallWatchdog
                ? Judgement(activity: .stalled, counts: false, began: signOfLife.addingTimeInterval(Self.stallAfter))
                : Judgement(activity: .idle, counts: false)
        }
        return stalled(Judgement(activity: .backgroundRun, counts: true), signOfLife: signOfLife, input: input)
    }

    /// Stall Watchdog: working but silent for 10 minutes. Stalled still counts until 20 minutes of silence.
    private func stalled(_ judgement: Judgement, signOfLife: Date, input: Input) -> Judgement {
        guard input.stallWatchdog else { return judgement }
        let silence = input.now.timeIntervalSince(signOfLife)
        guard silence >= Self.stallAfter else { return judgement }
        return Judgement(
            activity: .stalled, counts: silence < Self.oneShotStaleAfter,
            began: signOfLife.addingTimeInterval(Self.stallAfter)
        )
    }

    // MARK: Sign of life

    private func signOfLife(
        for process: RecognisedProcess, key: ProcessKey, verdict: HookVerdict?, recognition: Recognition, input: Input
    ) -> (time: Date, busy: Bool, log: LogWrite) {
        let remembered = memory[key]?.lastSignOfLife
        guard let previous = input.previous else { return (input.now, false, .none) }
        let tree = Self.tree(of: process, recognition: recognition, table: input.snapshot.table)
        let cpu = tree.members.reduce(0) { $0 + Self.cpuDelta($1, since: previous) }
        let elapsed = min(max(input.now.timeIntervalSince(previous.takenAt), Self.elapsedRange.lowerBound), Self.elapsedRange.upperBound)
        let hasToolCall = tree.descendants.contains {
            ProcessNames.isShell($0.name) && input.now.timeIntervalSince1970 - $0.startTime < Self.toolCallMaxAge
        }
        let busy = cpu / elapsed >= Self.busyCPUShare || hasToolCall
        let log = logWrite(for: process, input: input)
        let oneShot = process.kind == .oneShot
        let logIsAlive = log == .counting || (log == .fallback && !oneShot)
        let alive = busy || cpu > Self.signOfLifeCPUSeconds || logIsAlive
        var time = input.now
        if !alive, let remembered { time = remembered }
        if let event = verdict?.lastEvent, event > time { time = min(event, input.now) }
        return (time, busy, log)
    }

    /// The session and its descendants, except helpers and their subtrees.
    static func tree(
        of session: RecognisedProcess, recognition: Recognition, table: ProcessTable
    ) -> (members: [ProcessTable.Entry], descendants: [ProcessTable.Entry]) {
        let own = recognition.processIDs(ofAgent: session.agent.id)
        var descendants: [ProcessTable.Entry] = []
        var visited: Set<pid_t> = [session.entry.pid]
        var pending = table.children[session.entry.pid] ?? []
        while let pid = pending.popLast() {
            guard visited.insert(pid).inserted, let entry = table.entries[pid] else { continue }
            if isHelper(entry, of: session.entry, ownProcesses: own) { continue }
            descendants.append(entry)
            pending.append(contentsOf: table.children[pid] ?? [])
        }
        return ([session.entry] + descendants, descendants)
    }

    /// Not a shell, not the agent's own process, and either started with the session or a browser,
    /// Electron app or language server.
    static func isHelper(_ entry: ProcessTable.Entry, of session: ProcessTable.Entry, ownProcesses: Set<pid_t>) -> Bool {
        if ProcessNames.isShell(entry.name) || ownProcesses.contains(entry.pid) { return false }
        if entry.startTime - session.startTime < helperStartWindow { return true }
        let name = entry.name.lowercased()
        return helperNameParts.contains { name.contains($0) }
    }

    /// CPU used since the previous scan. A process first seen after it counts all of its CPU; an older
    /// process seen for the first time counts nothing.
    static func cpuDelta(_ entry: ProcessTable.Entry, since previous: ProcessSnapshot) -> Double {
        if let before = previous.table.entries[entry.pid], ProcessKey(before) == ProcessKey(entry) {
            return max(0, entry.cpuSeconds - before.cpuSeconds)
        }
        return entry.startTime >= previous.takenAt.timeIntervalSince1970 ? entry.cpuSeconds : 0
    }

    private func logWrite(for process: RecognisedProcess, input: Input) -> LogWrite {
        let agent = process.agent
        guard !agent.logFolders.isEmpty else { return .none }
        let facts = input.logs
        guard agent.logsPerProject else {
            return isRecent(facts.lastWriteByAgent[agent.id], now: input.now) ? .counting : .none
        }
        let directory = input.snapshot.directories[process.entry.pid]
        let existing = facts.projectFolders[agent.id] ?? []
        if let directory, let folder = ClaudeProjectFolder.resolve(directory: directory, existing: existing) {
            let key = LogFacts.projectKey(agentID: agent.id, folder: folder)
            return isRecent(facts.lastWriteByProject[key], now: input.now) ? .counting : .none
        }
        return isRecent(facts.lastWriteByAgent[agent.id], now: input.now) ? .fallback : .none
    }

    private func isRecent(_ time: Date?, now: Date) -> Bool {
        guard let time else { return false }
        return now.timeIntervalSince(time) <= Self.logWindow
    }

    // MARK: Result

    private static func result(
        _ judged: [(process: RecognisedProcess, session: AgentSession, counts: Bool)],
        definitions: [AgentDefinition], toolEvents: Int
    ) -> AgentScanResult {
        var summaries: [AgentSummary] = []
        for definition in definitions {
            let mine = judged.filter { $0.process.agent.id == definition.id }
            guard !mine.isEmpty else { continue }
            summaries.append(AgentSummary(
                name: definition.name,
                sessions: mine.count,
                isWorking: mine.contains { $0.counts },
                backgroundRuns: mine.filter { $0.session.activity == .backgroundRun }.count,
                isCustom: definition.isCustom,
                waitingForYou: mine.filter { $0.session.activity == .waitingForYou }.count,
                stalled: mine.filter { $0.session.activity == .stalled }.count
            ))
        }
        return AgentScanResult(
            agents: summaries, sessions: judged.map(\.session), anyWorking: judged.contains { $0.counts },
            toolEvents: toolEvents
        )
    }
}
