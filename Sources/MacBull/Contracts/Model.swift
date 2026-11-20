import Foundation

// Value types shared by every module. Keep them plain and Sendable.

enum SafetyStop: String, Codable, Sendable {
    case heat
    case battery
}

/// Lid-closed permission, as detected on this Mac.
enum LidSetup: Equatable, Sendable {
    case noLid
    case notSetUp
    case ready
}

enum LidSetupResult: Equatable, Sendable {
    case success
    case cancelled
    case failed(String)
}

/// A manual keep-awake session the user started.
struct ManualSession: Equatable, Sendable {
    /// Selected duration in minutes; 0 means until turned off.
    var minutes: Int
    var startedAt: Date
    /// nil for until turned off.
    var endsAt: Date?
}

/// What one agent session is doing, as far as MacBull can tell.
enum SessionActivity: String, Codable, Sendable {
    /// Busy, by hook verdict or by the heuristics.
    case working
    /// A one-shot run (`claude -p`, `codex exec`) that is still alive and counting.
    case backgroundRun
    /// A user-added agent: counts while it runs.
    case running
    /// Blocked on the human: a permission prompt or a question (Claude Code hooks only).
    case waitingForYou
    /// Finished its turn and waits for the next prompt (hooks only).
    case turnDone
    /// Open but not working (heuristics, or hooks idle).
    case idle
    /// Claims to work but shows no sign of life for a while (Stall Watchdog).
    case stalled
    case ended
}

/// One agent session (one top-level process, or one Claude Code session id tied to it).
struct AgentSession: Identifiable, Equatable, Sendable {
    /// Stable for the session's life: the Claude session id when known, else "<pid>-<start time>".
    var id: String
    /// Display name of the agent, for example "Claude Code".
    var agent: String
    /// Last path component of the working directory, when known. Never a full path.
    var folder: String?
    var activity: SessionActivity
    /// When the current activity began.
    var since: Date
    var lastSignOfLife: Date
    /// True when the activity comes from Claude Code hooks rather than heuristics.
    var isExact: Bool
    var pid: Int32?
}

/// One row per agent kind that has at least one session.
struct AgentSummary: Identifiable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var sessions: Int
    /// The agent counts as working for keep-awake purposes.
    var isWorking: Bool
    /// One-shot runs counting right now (not user-added agents).
    var backgroundRuns: Int
    var isCustom: Bool
    var waitingForYou: Int
    var stalled: Int
}

/// Result of one agent scan (every 10 s while agent mode is on).
struct AgentScanResult: Equatable, Sendable {
    /// Catalogue order, custom agents last.
    var agents: [AgentSummary]
    var sessions: [AgentSession]
    /// Any agent counts as working (drives the agent hold).
    var anyWorking: Bool
    /// Claude Code PostToolUse events read since the previous scan (bubbles in the scene).
    var toolEvents: Int
}

/// The four base looks of the menu bar can.
enum MenuIconBase: Equatable, Sendable {
    case off
    case on
    case agents
    case cutoff
}

enum SettingsTab: String, CaseIterable, Sendable {
    case general
    case lid
    case agents
    case safety
    case away
    case about
}

enum WelcomeStep: String, CaseIterable, Sendable {
    case hello
    case login
    case lid
    case agents
    case done
}

enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case disabled
    case needsApproval
    case failed(String)
}

// MARK: - Journal, receipts, stats

/// Something worth remembering for receipts and stats. Never holds prompts, tool input or full paths.
enum JournalEventKind: Codable, Equatable, Sendable {
    case appLaunched
    case appQuit
    /// reason: "manual" or "agents".
    case awakeStarted(reason: String)
    /// reason: "user", "timer", "cutoff", "agentsDone", "quit", "sleepNow".
    case awakeEnded(reason: String)
    case sessionChanged(id: String, agent: String, folder: String?, activity: SessionActivity)
    case macSlept
    case macWoke
    case battery(percent: Int, onAC: Bool)
    /// 0 nominal, 1 fair, 2 serious, 3 critical.
    case thermal(level: Int)
    case safetyStop(SafetyStop)
    case awayStarted
    case awayEnded
}

struct JournalEvent: Codable, Equatable, Sendable {
    var at: Date
    var kind: JournalEventKind
}

enum ReceiptOutcome: Codable, Equatable, Sendable {
    case finished(at: Date, afterSeconds: TimeInterval)
    case waitingForYou(since: Date)
    case stillWorking
    case stalled(since: Date)
    case ended(at: Date)
}

struct ReceiptLine: Codable, Equatable, Sendable {
    var agent: String
    var folder: String?
    var outcome: ReceiptOutcome
    /// Finished working runs of this session in the window. 0 in receipts saved before this field existed.
    var turns: Int
    /// Total working time of those runs. 0 in receipts saved before this field existed.
    var workSeconds: TimeInterval

    init(agent: String, folder: String?, outcome: ReceiptOutcome, turns: Int = 0, workSeconds: TimeInterval = 0) {
        self.agent = agent
        self.folder = folder
        self.outcome = outcome
        self.turns = turns
        self.workSeconds = workSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case agent, folder, outcome, turns, workSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agent = try container.decode(String.self, forKey: .agent)
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        outcome = try container.decode(ReceiptOutcome.self, forKey: .outcome)
        turns = try container.decodeIfPresent(Int.self, forKey: .turns) ?? 0
        workSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .workSeconds) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agent, forKey: .agent)
        try container.encodeIfPresent(folder, forKey: .folder)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(turns, forKey: .turns)
        try container.encode(workSeconds, forKey: .workSeconds)
    }
}

/// "While you were away": one summary for one away window.
struct Receipt: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var awayFrom: Date
    var awayTo: Date
    var lines: [ReceiptLine]
    var batteryStart: Int?
    var batteryEnd: Int?
    var pluggedIn: Bool
    /// 0 nominal ... 3 critical.
    var peakThermal: Int
    var sleptAt: [Date]
    var safetyStop: SafetyStop?
    /// Set when MacBull was not running for part of the window (crash or power loss).
    var notRunningSince: Date?

    /// True when something worth telling happened.
    var isWorthShowing: Bool {
        !lines.isEmpty || safetyStop != nil || notRunningSince != nil
    }
}

enum StatsRange: String, CaseIterable, Sendable {
    case today
    case week
    case allTime
}

struct AgentShare: Equatable, Sendable {
    var agent: String
    /// 0...1 of agent-time.
    var share: Double
}

/// The Nutrition Facts label.
struct NutritionStats: Equatable, Sendable {
    var cansOpened: Int
    var awakeSeconds: TimeInterval
    /// Parallel agents add up.
    var agentSeconds: TimeInterval
    var longestRunSeconds: TimeInterval
    var sessionsFinished: Int
    var waitedForYouSeconds: TimeInterval
    var waitedForYouMedianSeconds: TimeInterval
    /// Percentage points of battery used while away.
    var batterySpentAway: Int
    var safetyStops: Int
    var agentMix: [AgentShare]
    /// Finished sessions today (the row of empties).
    var emptiesToday: Int

    static let empty = NutritionStats(
        cansOpened: 0, awakeSeconds: 0, agentSeconds: 0, longestRunSeconds: 0, sessionsFinished: 0,
        waitedForYouSeconds: 0, waitedForYouMedianSeconds: 0, batterySpentAway: 0, safetyStops: 0,
        agentMix: [], emptiesToday: 0
    )
}

// MARK: - Sound and feel

enum SoundCue: String, CaseIterable, Sendable {
    /// Keep-awake turned on from the panel.
    case crack
    /// Turned off from the panel.
    case clink
    /// Safety stop while the panel is open.
    case crumple
    /// Easter egg: the laptop foams over.
    case burp
}

/// Notification sound files in the app bundle's Resources/Sounds folder.
enum NotificationSound {
    static let agentsDone = "macbull-ping.caf"
    static let safetyStop = "macbull-crumple.caf"
    static let waitingForYou = "macbull-knock.caf"
}
