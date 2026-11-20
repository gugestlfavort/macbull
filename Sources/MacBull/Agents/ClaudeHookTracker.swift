import Foundation

/// What a hook verdict says about one Claude Code session.
struct HookVerdict: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case working
        case waitingForYou
        case turnDone
        case ended
    }

    var state: State
    /// The Claude session id this verdict mostly speaks for.
    var sessionID: String
    /// The newest hook event among the records tied to the process (a sign of life).
    var lastEvent: Date
    /// When the event that decided the state arrived.
    var changedAt: Date
    /// Working directory the hook reported, when it did. Used for the folder name only.
    var cwd: String?
}

/// What Claude Code sessions report through their hooks, per session id. A session is tied to the
/// Claude process that runs it, so the judge can use the exact state for that process instead of
/// guessing from CPU and logs.
struct ClaudeHookTracker {
    typealias State = HookVerdict.State

    struct Record {
        var parentPID: pid_t
        var state: State
        var lastEvent: Date
        var cwd: String?
        /// The Claude process, once found.
        var process: ProcessKey?
    }

    /// "Working" with no event for this long can't be trusted: Esc sends no Stop, and one long tool call
    /// (a build) sends nothing between its start and end. The judge's own checks decide instead.
    static let workingStaleAfter: TimeInterval = 5 * 60
    /// An event whose process can't be found is dropped after this long.
    static let unresolvedGrace: TimeInterval = 2 * 60

    private(set) var records: [String: Record] = [:]

    /// What each event says about the session. SubagentStop is
    /// Claude carrying on after a helper finished.
    static func state(after event: ClaudeHookEvent) -> State? {
        switch event.name {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStop":
            return .working
        case "Stop":
            return .turnDone
        case "Notification":
            return isPermissionRequest(event) ? .waitingForYou : .turnDone
        case "SessionEnd":
            return .ended
        default:
            return nil
        }
    }

    private static func isPermissionRequest(_ event: ClaudeHookEvent) -> Bool {
        if let type = event.notificationType, !type.isEmpty { return type == "permission_prompt" }
        return event.mentionsPermission
    }

    /// Events must be oldest first.
    mutating func ingest(_ events: [ClaudeHookEvent]) {
        for event in events {
            guard let state = Self.state(after: event) else { continue }
            if var record = records[event.sessionID] {
                record.parentPID = event.parentPID
                record.state = state
                record.lastEvent = event.date
                record.cwd = event.cwd ?? record.cwd
                records[event.sessionID] = record
            } else if state != .ended {
                records[event.sessionID] = Record(
                    parentPID: event.parentPID, state: state, lastEvent: event.date, cwd: event.cwd, process: nil
                )
            }
        }
    }

    /// Ties each session to its Claude process and drops those whose process is gone.
    /// `sessions` are the Claude sessions found in `table`; `directories` their working directories,
    /// used only when the process that ran the hook has already exited.
    mutating func resolve(table: ProcessTable, sessions: [ProcessTable.Entry], directories: [pid_t: String], now: Date) {
        let sessionPIDs = Set(sessions.map(\.pid))
        for (id, var record) in records {
            if let pid = Self.nearestSession(from: record.parentPID, in: table, among: sessionPIDs),
               let entry = table.entries[pid] {
                record.process = ProcessKey(entry)
            } else if record.process == nil, let cwd = record.cwd {
                let sameDirectory = sessions.filter { directories[$0.pid] == cwd }
                if sameDirectory.count == 1 { record.process = ProcessKey(sameDirectory[0]) }
            }
            if let process = record.process {
                guard table.entries[process.pid].map(ProcessKey.init) == process else {
                    records[id] = nil
                    continue
                }
            } else if now.timeIntervalSince(record.lastEvent) > Self.unresolvedGrace {
                records[id] = nil
                continue
            }
            records[id] = record
        }
    }

    /// The nearest process at or above `pid` that is a Claude session: the hook may run through a shell.
    private static func nearestSession(from pid: pid_t, in table: ProcessTable, among sessions: Set<pid_t>) -> pid_t? {
        var current = pid
        for _ in 0..<64 {
            if sessions.contains(current) { return current }
            guard let entry = table.entries[current], entry.parent > 1 else { return nil }
            current = entry.parent
        }
        return nil
    }

    /// The verdict for every process that has hook records. A process whose last word was "working"
    /// more than `workingStaleAfter` ago has no verdict: the judge then guesses. A recent "working" and
    /// any quiet state are exact, whatever the age of the quiet one.
    func verdicts(now: Date) -> [ProcessKey: HookVerdict] {
        var byProcess: [ProcessKey: [(id: String, record: Record)]] = [:]
        for (id, record) in records {
            guard let process = record.process else { continue }
            byProcess[process, default: []].append((id, record))
        }
        return byProcess.compactMapValues { Self.verdict(of: $0, now: now) }
    }

    func verdict(for process: ProcessKey, now: Date) -> HookVerdict? {
        let mine = records.compactMap { $0.value.process == process ? (id: $0.key, record: $0.value) : nil }
        return Self.verdict(of: mine, now: now)
    }

    private static func verdict(of mine: [(id: String, record: Record)], now: Date) -> HookVerdict? {
        guard let newest = mine.max(by: { newer($1, than: $0) }) else { return nil }
        let working = mine.filter { $0.record.state == .working }
        if let freshest = working.filter({ now.timeIntervalSince($0.record.lastEvent) < workingStaleAfter })
            .max(by: { newer($1, than: $0) }) {
            return HookVerdict(state: .working, sessionID: freshest.id, lastEvent: newest.record.lastEvent,
                               changedAt: freshest.record.lastEvent, cwd: freshest.record.cwd ?? newest.record.cwd)
        }
        if !working.isEmpty { return nil }
        let live = mine.filter { $0.record.state != .ended }
        let decider = live.max(by: { newer($1, than: $0) }) ?? newest
        return HookVerdict(state: decider.record.state, sessionID: decider.id, lastEvent: newest.record.lastEvent,
                           changedAt: decider.record.lastEvent, cwd: decider.record.cwd ?? newest.record.cwd)
    }

    /// Newest event first; the session id breaks ties so the choice never depends on dictionary order.
    private static func newer(_ lhs: (id: String, record: Record), than rhs: (id: String, record: Record)) -> Bool {
        (lhs.record.lastEvent, lhs.id) > (rhs.record.lastEvent, rhs.id)
    }
}
