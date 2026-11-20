import Foundation

// Pure rules behind the panel: the pour stops, level and pour tables, the hero title and sentence,
// the modes box lines, wait-time formatting, Live Carbonation and the easter egg rule.
// Nothing here touches AppKit or SwiftUI, so every rule has a unit test.

// MARK: - Pour stops

/// The nine places the liquid can be set, from the bottom of the screen to the top.
enum PourStop: Int, CaseIterable, Sendable {
    case off, m15, m30, h1, h2, h3, h5, h8, untilOff

    /// nil means off. 0 means until turned off (the `ManualSession` convention). Otherwise minutes.
    var minutes: Int? {
        switch self {
        case .off: nil
        case .m15: 15
        case .m30: 30
        case .h1: 60
        case .h2: 120
        case .h3: 180
        case .h5: 300
        case .h8: 480
        case .untilOff: 0
        }
    }

    /// The big title while dragging, and the label on the liquid.
    var label: String {
        switch self {
        case .off: "Off"
        case .m15: "15m"
        case .m30: "30m"
        case .h1: "1h"
        case .h2: "2h"
        case .h3: "3h"
        case .h5: "5h"
        case .h8: "8h"
        case .untilOff: "\u{221E}"
        }
    }

    var spokenName: String {
        switch self {
        case .off: "off"
        case .m15: "15 minutes"
        case .m30: "30 minutes"
        case .h1: "1 hour"
        case .h2: "2 hours"
        case .h3: "3 hours"
        case .h5: "5 hours"
        case .h8: "8 hours"
        case .untilOff: "until you turn it off"
        }
    }
}

enum PourRules {
    /// Minimum drag distance before the pour starts.
    static let dragMinimum: CGFloat = 10
    /// The part of the scene's height that maps onto the stops: 8% from the top to 92%.
    static let rangeTop: CGFloat = 0.08
    static let rangeBottom: CGFloat = 0.92
    /// Steps between the lowest and the highest stop.
    static let steps = Double(PourStop.allCases.count - 1)
    /// The numeric stops, in minutes, at indices 0...7 of the scale (the ninth is until-off).
    private static let numericStops: [Double] = [0, 15, 30, 60, 120, 180, 300, 480]

    /// The nearest stop for a pointer height, top is fullest.
    static func stop(atY y: CGFloat, height: CGFloat) -> PourStop {
        guard height > 0 else { return .off }
        let span = (rangeBottom - rangeTop) * height
        let fromTop = min(max((y - rangeTop * height) / span, 0), 1)
        let position = 1 - Double(fromTop)
        let index = Int((position * steps).rounded())
        return PourStop(rawValue: min(max(index, 0), PourStop.allCases.count - 1)) ?? .off
    }

    static func level(for stop: PourStop) -> Double {
        Double(stop.rawValue) / steps
    }

    /// Remaining minutes on the same scale, interpolated between neighbouring numeric stops.
    static func level(forRemainingMinutes minutes: Double) -> Double {
        let topNumeric = Double(numericStops.count - 1) / steps
        guard minutes > 0 else { return 0 }
        guard let upper = numericStops.firstIndex(where: { $0 >= minutes }), upper > 0 else { return topNumeric }
        let lower = numericStops[upper - 1]
        let fraction = (minutes - lower) / (numericStops[upper] - lower)
        return (Double(upper - 1) + fraction) / steps
    }

    /// How far the can tips while dragging: 0.1 at off, 0.2 when the level goes down, otherwise more the higher it is.
    static func pour(stop: PourStop, previous: PourStop?) -> Double {
        if stop == .off { return 0.1 }
        if let previous, stop.rawValue < previous.rawValue { return 0.2 }
        return 0.35 + 0.65 * Double(stop.rawValue) / steps
    }

    /// Where an accessibility increment starts from: off when not running, the stop matching a running duration.
    static func currentStop(manual: ManualSession?) -> PourStop {
        guard let manual else { return .off }
        return PourStop.allCases.first { $0 != .off && $0.minutes == manual.minutes } ?? .off
    }

    static func stepped(_ stop: PourStop, by delta: Int) -> PourStop {
        let index = min(max(stop.rawValue + delta, 0), PourStop.allCases.count - 1)
        return PourStop(rawValue: index) ?? stop
    }
}

// MARK: - Quick picks

struct QuickPick: Identifiable, Equatable, Sendable {
    let minutes: Int
    let label: String
    let spokenName: String
    var id: Int { minutes }

    /// 15m, 30m, 1h, 2h, 5h and until turned off (0).
    static let all: [QuickPick] = [
        QuickPick(minutes: 15, label: "15m", spokenName: "15 minutes"),
        QuickPick(minutes: 30, label: "30m", spokenName: "30 minutes"),
        QuickPick(minutes: 60, label: "1h", spokenName: "1 hour"),
        QuickPick(minutes: 120, label: "2h", spokenName: "2 hours"),
        QuickPick(minutes: 300, label: "5h", spokenName: "5 hours"),
        QuickPick(minutes: 0, label: "\u{221E}", spokenName: "Until turned off"),
    ]
}

// MARK: - Formatting

enum PanelFormat {
    /// "<1 min", "6 min", "1 h", "7 h 12 min".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int(seconds / 60), 0)
        if minutes < 1 { return "<1 min" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        if rest == 0 { return "\(hours) h" }
        return "\(hours) h \(rest) min"
    }

    /// "waiting 6 min".
    static func waiting(since: Date, now: Date) -> String {
        "waiting \(duration(now.timeIntervalSince(since)))"
    }

    /// "no activity for 12 min".
    static func stalled(lastSignOfLife: Date, now: Date) -> String {
        "no activity for \(duration(now.timeIntervalSince(lastSignOfLife)))"
    }

    /// `M:SS` under an hour, `H:MM:SS` from an hour. Seconds are rounded up.
    static func countdown(remaining: TimeInterval) -> String {
        let total = max(Int(remaining.rounded(.up)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let paddedSeconds = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        if hours == 0 { return "\(minutes):\(paddedSeconds)" }
        let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        return "\(hours):\(paddedMinutes):\(paddedSeconds)"
    }

    /// "Claude Code", "Claude Code and Codex", "Claude Code, Codex and Aider".
    static func naturalList(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

// MARK: - Hero

enum HeroTitle: Equatable {
    case text(String)
    case infinity

    var spoken: String {
        switch self {
        case .text(let text): text
        case .infinity: "until you turn it off"
        }
    }
}

/// Everything the hero decides from. Built from `AppState` and `Settings`, tested without them.
struct HeroFacts: Equatable {
    var drag: PourStop?
    var manual: ManualSession?
    var agentHold: Bool
    var paused: Bool
    var agentMode: Bool
    /// Names of the agents that count as working right now.
    var workingAgents: [String]
    /// A one-shot run (not a user-added agent) is going.
    var hasBackgroundRun: Bool
    var now: Date

    @MainActor
    static func make(state: AppState, settings: Settings, drag: PourStop?, now: Date) -> HeroFacts {
        HeroFacts(
            drag: drag,
            manual: state.manual,
            agentHold: state.agentHold,
            paused: state.paused,
            agentMode: settings.agentMode,
            workingAgents: state.agents.filter(\.isWorking).map(\.name),
            hasBackgroundRun: state.agents.contains { !$0.isCustom && $0.backgroundRuns > 0 },
            now: now
        )
    }
}

enum HeroCopy {
    static func title(_ facts: HeroFacts) -> HeroTitle {
        if let drag = facts.drag {
            return drag == .untilOff ? .infinity : .text(drag.label)
        }
        if let manual = facts.manual {
            guard let endsAt = manual.endsAt else { return .infinity }
            return .text(PanelFormat.countdown(remaining: endsAt.timeIntervalSince(facts.now)))
        }
        if facts.agentHold { return .text("Charged") }
        return .text("Off")
    }

    static func sentence(_ facts: HeroFacts) -> String {
        if facts.drag != nil { return "Let go to set the time" }
        if let manual = facts.manual {
            return manualSentence(facts, manual: manual)
        }
        if facts.agentHold {
            return agentSentence(facts)
        }
        if facts.paused { return "Paused until your agents finish" }
        if facts.agentMode { return "Sleeps like normal and wakes up by itself when an agent starts working" }
        return "Sleeps like normal. Drag up on the can to add time."
    }

    private static func manualSentence(_ facts: HeroFacts, manual: ManualSession) -> String {
        if !facts.workingAgents.isEmpty {
            let verb = facts.workingAgents.count == 1 ? "is" : "are"
            return "\(PanelFormat.naturalList(facts.workingAgents)) \(verb) working too"
        }
        return manual.endsAt == nil ? "Awake until you say stop" : "Then your Mac sleeps like normal"
    }

    private static func agentSentence(_ facts: HeroFacts) -> String {
        if facts.hasBackgroundRun { return "A background run is going, staying up until it is done" }
        if facts.workingAgents.isEmpty { return "Agents just finished, letting go in a few minutes" }
        let verb = facts.workingAgents.count == 1 ? "is" : "are"
        return "\(PanelFormat.naturalList(facts.workingAgents)) \(verb) working, staying up until done"
    }

    /// Level of the liquid, 0 empty to 1 full.
    static func level(_ facts: HeroFacts) -> Double {
        if let drag = facts.drag { return PourRules.level(for: drag) }
        if let manual = facts.manual {
            guard let endsAt = manual.endsAt else { return 1 }
            return PourRules.level(forRemainingMinutes: endsAt.timeIntervalSince(facts.now) / 60)
        }
        return facts.agentHold ? 1 : 0
    }

    static func spokenValue(_ facts: HeroFacts) -> String {
        "\(title(facts).spoken). \(sentence(facts))"
    }
}

// MARK: - Modes box

enum ModesCopy {
    /// Whether the lid mode is effectively on: set up and the setting is on.
    static func lidEffectivelyOn(setup: LidSetup, lidHold: Bool) -> Bool {
        setup == .ready && lidHold
    }

    static func lidDetail(setup: LidSetup, lidHold: Bool, isAwake: Bool) -> String {
        if setup == .notSetUp { return "Needs your password once" }
        if !lidHold { return "Closing the lid puts the Mac to sleep" }
        return isAwake
            ? "Close the lid and the work keeps going"
            : "While MacBull is on, closing the lid will not stop the work"
    }

    struct AgentsFacts: Equatable {
        var agentMode: Bool
        var agents: [AgentSummary]
        var isAwake: Bool
        var cutoff: SafetyStop?
        var paused: Bool
        var agentHold: Bool
        var lidEffectivelyOn: Bool
    }

    static func agentsDetail(_ facts: AgentsFacts) -> String {
        if !facts.agentMode { return "Off. Agents will not keep your Mac awake." }
        if facts.agents.isEmpty { return "None open. Your Mac stays up by itself once one starts working." }
        if !facts.isAwake, let cutoff = facts.cutoff {
            return cutoff == .heat ? "Stopped because your Mac got warm" : "Stopped because the battery is low"
        }
        if facts.paused { return "Paused by you until they finish" }
        let lidPart = facts.lidEffectivelyOn ? ", lid closed too" : ""
        let runs = facts.agents.filter { !$0.isCustom }.reduce(0) { $0 + $1.backgroundRuns }
        if runs > 0 {
            let lead = runs == 1 ? "A background run is going" : "\(runs) background runs are going"
            return lead + ", staying up until done" + lidPart
        }
        let working = facts.agents.filter(\.isWorking).map(\.name)
        if !working.isEmpty {
            return "\(PanelFormat.naturalList(working)) working, staying up" + lidPart
        }
        if facts.agentHold { return "Just finished, letting go in a few minutes" }
        let open = facts.agents.reduce(0) { $0 + $1.sessions }
        return open == 1
            ? "One session open but idle, so your Mac can sleep"
            : "\(open) open, all idle, so your Mac can sleep"
    }

    enum AgentStatus: Equatable {
        case running, backgroundRun, working, waiting, stalled, idle

        var word: String {
            switch self {
            case .running: "Running"
            case .backgroundRun: "Background run"
            case .working: "Working"
            case .waiting: "Waiting for you"
            case .stalled: "Stuck"
            case .idle: "Idle"
            }
        }
    }

    static func status(of agent: AgentSummary) -> AgentStatus {
        if agent.isCustom { return .running }
        if agent.waitingForYou > 0 { return .waiting }
        if agent.backgroundRuns > 0 { return .backgroundRun }
        if agent.isWorking { return .working }
        if agent.stalled > 0 { return .stalled }
        return .idle
    }

    /// The word shown next to one session under its agent.
    static func word(for activity: SessionActivity) -> String {
        switch activity {
        case .working: "Working"
        case .backgroundRun: "Background run"
        case .running: "Running"
        case .waitingForYou: "Waiting for you"
        case .turnDone: "Done"
        case .idle: "Idle"
        case .stalled: "Stuck"
        case .ended: "Ended"
        }
    }

    /// Claude Code sessions that hooks report with a folder: the ones listed under their agent.
    static func detailedSessions(of agent: AgentSummary, in sessions: [AgentSession]) -> [AgentSession] {
        sessions.filter { $0.agent == agent.name && $0.isExact && $0.folder != nil && $0.activity != .ended }
    }
}

// MARK: - Your Turn

enum YourTurnRows {
    /// Waiting sessions first, longest wait first, then stalled ones, longest stall first.
    static func rows(from sessions: [AgentSession]) -> [AgentSession] {
        let waiting = sessions.filter { $0.activity == .waitingForYou }.sorted { $0.since < $1.since }
        let stalled = sessions.filter { $0.activity == .stalled }.sorted { $0.lastSignOfLife < $1.lastSignOfLife }
        return waiting + stalled
    }

    /// Only a session with a process can be walked up to its window.
    static func isClickable(_ session: AgentSession) -> Bool {
        session.pid != nil
    }
}

// MARK: - Live Carbonation

enum LiveCarbonation {
    /// The liquid turns amber when the Mac runs hot (serious or worse) or the battery is within this many
    /// points of the limit.
    static let batteryMargin = 10
    static let maxBubbles = 12
    static let maxPulses = 8

    static func isAmber(
        thermal: ProcessInfo.ThermalState,
        onBattery: Bool,
        batteryPercent: Int?,
        batteryGuard: Bool,
        batteryLimit: Int
    ) -> Bool {
        if thermal == .serious || thermal == .critical { return true }
        guard onBattery, batteryGuard, let batteryPercent else { return false }
        return batteryPercent <= batteryLimit + batteryMargin
    }

    /// More working sessions, more bubbles. Always a few, so a single agent already fizzes.
    static func bubbleCount(workingSessions: Int) -> Int {
        min(3 + 3 * max(workingSessions, 1), maxBubbles)
    }

    static func workingSessions(_ sessions: [AgentSession]) -> Int {
        sessions.filter { [.working, .backgroundRun, .running].contains($0.activity) }.count
    }

    /// New tool-call bubbles for a change of the pulse counter.
    static func pulsesAdded(from old: Int, to new: Int) -> Int {
        min(max(new - old, 0), maxPulses)
    }
}

// MARK: - Easter egg

enum FoamRule {
    static let defaultsKey = "feel.lastFoam"
    /// How long to hold at until-off before the laptop foams over.
    static let holdSeconds = 2.0

    /// At most once a calendar day, and never with Reduce Motion.
    static func isAllowed(lastFoam: Date?, now: Date, reduceMotion: Bool, calendar: Calendar = .current) -> Bool {
        if reduceMotion { return false }
        guard let lastFoam else { return true }
        return !calendar.isDate(lastFoam, inSameDayAs: now)
    }
}

struct FoamStore {
    var defaults: UserDefaults = .standard

    var lastFoam: Date? {
        defaults.object(forKey: FoamRule.defaultsKey) as? Date
    }

    func record(_ date: Date) {
        defaults.set(date, forKey: FoamRule.defaultsKey)
    }
}

// MARK: - Receipts

enum ReceiptFormat {
    static func away(_ receipt: Receipt) -> String {
        PanelFormat.duration(receipt.awayTo.timeIntervalSince(receipt.awayFrom))
    }

    // MARK: Groups

    /// Finished groups with less work than this fold into one "quick runs" row.
    static let quickRunSeconds: TimeInterval = 120
    /// Rows shown before "Show all".
    static let collapsedRowLimit = 4
    /// Height of the scrolling list once expanded.
    static let expandedMaxHeight: CGFloat = 220

    enum GroupState: Int, Equatable, Sendable {
        case waiting, stuck, working, finished
    }

    /// All sessions of one agent in one folder (a nil folder groups as the agent alone).
    struct Group: Equatable, Sendable {
        var agent: String
        var folder: String?
        var state: GroupState
        /// Waiting or stuck: when the longest-waiting session started. Finished: the latest finish or end.
        var moment: Date?
        var turns: Int
        var workSeconds: TimeInterval
        /// Only ended sessions, no finished turn.
        var onlyEnded: Bool

        var title: String { folder.map { "\(agent) / \($0)" } ?? agent }
    }

    enum Row: Equatable, Sendable {
        case group(Group)
        /// "+ 6 quick runs in 4 projects".
        case quick(runs: Int, projects: Int)
    }

    /// Turns of a line. A finished line saved before turns were counted is one turn.
    static func turns(_ line: ReceiptLine) -> Int {
        if line.turns > 0 { return line.turns }
        if case .finished = line.outcome { return 1 }
        return 0
    }

    static func workSeconds(_ line: ReceiptLine) -> TimeInterval {
        if line.workSeconds > 0 { return line.workSeconds }
        if line.turns == 0, case .finished(_, let afterSeconds) = line.outcome { return afterSeconds }
        return line.workSeconds
    }

    private struct GroupKey: Hashable {
        var agent: String
        var folder: String?
    }

    private static func state(of outcome: ReceiptOutcome) -> GroupState {
        switch outcome {
        case .waitingForYou: .waiting
        case .stalled: .stuck
        case .stillWorking: .working
        case .finished, .ended: .finished
        }
    }

    /// One group per agent and folder: waiting, stuck, still working first, then finished by work time.
    static func groups(_ lines: [ReceiptLine]) -> [Group] {
        var order: [GroupKey] = []
        var byKey: [GroupKey: Group] = [:]
        for line in lines {
            let key = GroupKey(agent: line.agent, folder: line.folder)
            if byKey[key] == nil { order.append(key) }
            var group = byKey[key] ?? Group(
                agent: line.agent, folder: line.folder, state: .finished, moment: nil, turns: 0, workSeconds: 0, onlyEnded: true)
            merge(line, into: &group)
            byKey[key] = group
        }
        return order.compactMap { byKey[$0] }.sorted(by: groupOrder)
    }

    private static func merge(_ line: ReceiptLine, into group: inout Group) {
        group.turns += turns(line)
        group.workSeconds += workSeconds(line)
        if turns(line) > 0 { group.onlyEnded = false }
        let lineState = state(of: line.outcome)
        let lineMoment = moment(of: line.outcome)
        if lineState.rawValue < group.state.rawValue {
            group.state = lineState
            group.moment = lineMoment
        } else if lineState == group.state {
            group.moment = combine(group.moment, lineMoment, state: lineState)
        }
    }

    /// Waiting and stuck keep the earliest start; finished keeps the latest finish.
    private static func combine(_ current: Date?, _ new: Date?, state: GroupState) -> Date? {
        guard let current else { return new }
        guard let new else { return current }
        return state == .finished ? max(current, new) : min(current, new)
    }

    private static func moment(of outcome: ReceiptOutcome) -> Date? {
        switch outcome {
        case .finished(let at, _): at
        case .waitingForYou(let since): since
        case .stalled(let since): since
        case .ended(let at): at
        case .stillWorking: nil
        }
    }

    private static func groupOrder(_ lhs: Group, _ rhs: Group) -> Bool {
        if lhs.state != rhs.state { return lhs.state.rawValue < rhs.state.rawValue }
        if lhs.state == .finished, lhs.workSeconds != rhs.workSeconds { return lhs.workSeconds > rhs.workSeconds }
        if let left = lhs.moment, let right = rhs.moment, left != right {
            return lhs.state == .finished ? left > right : left < right
        }
        return lhs.title < rhs.title
    }

    private static func isQuick(_ group: Group) -> Bool {
        group.state == .finished && !group.onlyEnded && group.workSeconds < quickRunSeconds
    }

    /// The groups as rows. Two or more quick finished groups fold into one row at the end.
    static func rows(_ lines: [ReceiptLine]) -> [Row] {
        let all = groups(lines)
        let quick = all.filter(isQuick)
        guard quick.count >= 2 else { return all.map(Row.group) }
        let kept = all.filter { !isQuick($0) }.map(Row.group)
        return kept + [.quick(runs: quick.reduce(0) { $0 + $1.turns }, projects: quick.count)]
    }

    /// The rows to draw and how many are hidden.
    static func visible(_ rows: [Row], expanded: Bool) -> (rows: [Row], hidden: Int) {
        if expanded || rows.count <= collapsedRowLimit { return (rows, 0) }
        return (Array(rows.prefix(collapsedRowLimit)), rows.count - collapsedRowLimit)
    }

    static func showAllTitle(total: Int) -> String { "Show all (\(total))" }

    static let showLessTitle = "Show less"

    static func plural(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    static func title(_ row: Row) -> String {
        switch row {
        case .group(let group): group.title
        case .quick(let runs, let projects): "+ \(plural(runs, "quick run")) in \(plural(projects, "project"))"
        }
    }

    /// The second line of a row: "9 turns, 1 h 52 min of work, last 07:24" or "waiting for you since 06:58".
    static func detail(_ row: Row) -> String? {
        guard case .group(let group) = row else { return nil }
        let since = group.moment.map { PanelFormat.clock($0) }
        switch group.state {
        case .waiting: return since.map { "waiting for you since \($0)" } ?? "waiting for you"
        case .stuck: return since.map { "stuck since \($0)" } ?? "stuck"
        case .working: return "still working"
        case .finished:
            if group.onlyEnded { return since.map { "ended \($0)" } ?? "ended" }
            let work = group.workSeconds < 60 ? "under a minute" : "\(PanelFormat.duration(group.workSeconds)) of work"
            let last = since.map { ", last \($0)" } ?? ""
            return "\(plural(group.turns, "turn")), \(work)\(last)"
        }
    }

    // MARK: Summary

    /// "23 turns done in 7 projects", "1 waiting for you", "1 still working", "1 stuck", "1 ended".
    static func countParts(_ lines: [ReceiptLine]) -> [String] {
        var waiting = 0, working = 0, stalled = 0, endedOnly = 0
        for line in lines {
            switch line.outcome {
            case .waitingForYou: waiting += 1
            case .stillWorking: working += 1
            case .stalled: stalled += 1
            case .ended: if turns(line) == 0 { endedOnly += 1 }
            case .finished: break
            }
        }
        let totalTurns = lines.reduce(0) { $0 + turns($1) }
        let projects = Set(lines.filter { turns($0) > 0 }.map { GroupKey(agent: $0.agent, folder: $0.folder) }).count
        var parts: [String] = []
        if totalTurns > 0 { parts.append("\(plural(totalTurns, "turn")) done in \(plural(projects, "project"))") }
        if waiting > 0 { parts.append("\(waiting) waiting for you") }
        if working > 0 { parts.append("\(working) still working") }
        if stalled > 0 { parts.append("\(stalled) stuck") }
        if endedOnly > 0 { parts.append("\(endedOnly) ended") }
        return parts
    }

    /// "23 turns done in 7 projects, 1 waiting for you".
    static func summary(_ receipt: Receipt) -> String {
        var parts = countParts(receipt.lines)
        if receipt.safetyStop != nil { parts.append("safety stop") }
        return parts.isEmpty ? "quiet" : parts.joined(separator: ", ")
    }

    static func thermalName(_ level: Int) -> String? {
        switch level {
        case ...0: nil
        case 1: "warm"
        case 2: "hot"
        default: "very hot"
        }
    }

    static func batteryLine(_ receipt: Receipt) -> String? {
        guard let start = receipt.batteryStart, let end = receipt.batteryEnd else { return nil }
        return "Battery \(start)% to \(end)%" + (receipt.pluggedIn ? ", plugged in" : "")
    }

    static func safetyLine(_ stop: SafetyStop) -> String {
        stop == .heat ? "Safety stop: the Mac got too warm" : "Safety stop: the battery got low"
    }

    static func sleptLine(_ count: Int) -> String? {
        switch count {
        case ...0: nil
        case 1: "Mac slept once"
        default: "Mac slept \(count) times"
        }
    }

    /// Extra lines under the sessions: battery, heat, sleeps, safety stop, a gap in the record.
    static func notes(_ receipt: Receipt) -> [String] {
        var notes: [String] = []
        if let line = batteryLine(receipt) { notes.append(line) }
        if let name = thermalName(receipt.peakThermal) { notes.append("Peak heat: \(name)") }
        if let line = sleptLine(receipt.sleptAt.count) { notes.append(line) }
        if let stop = receipt.safetyStop { notes.append(safetyLine(stop)) }
        if let since = receipt.notRunningSince { notes.append("MacBull was not running since \(PanelFormat.clock(since))") }
        return notes
    }
}

// MARK: - Nutrition label

struct NutritionRow: Equatable {
    var label: String
    var value: String
    var note: String?
}

enum NutritionFormat {
    static let maxEmpties = 12

    static func rangeName(_ range: StatsRange) -> String {
        switch range {
        case .today: "Today"
        case .week: "Week"
        case .allTime: "All time"
        }
    }

    static func rangePhrase(_ range: StatsRange) -> String {
        switch range {
        case .today: "today"
        case .week: "this week"
        case .allTime: "all time"
        }
    }

    static func isEmpty(_ stats: NutritionStats) -> Bool {
        stats.cansOpened == 0 && stats.awakeSeconds == 0 && stats.agentSeconds == 0
            && stats.sessionsFinished == 0 && stats.safetyStops == 0
    }

    static func agentHours(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600
        let rounded = (hours * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded)) h" }
        return "\(rounded) h"
    }

    static func rows(_ stats: NutritionStats) -> [NutritionRow] {
        let waited = stats.waitedForYouSeconds > 0
            ? NutritionRow(label: "Waited for you", value: PanelFormat.duration(stats.waitedForYouSeconds),
                           note: "median \(PanelFormat.duration(stats.waitedForYouMedianSeconds))")
            : NutritionRow(label: "Waited for you", value: "0 min", note: nil)
        return [
            NutritionRow(label: "Cans opened", value: "\(stats.cansOpened)", note: nil),
            NutritionRow(label: "Awake time", value: PanelFormat.duration(stats.awakeSeconds), note: nil),
            NutritionRow(label: "Agent-hours", value: agentHours(stats.agentSeconds), note: nil),
            NutritionRow(label: "Longest run", value: PanelFormat.duration(stats.longestRunSeconds), note: nil),
            NutritionRow(label: "Sessions finished", value: "\(stats.sessionsFinished)", note: nil),
            waited,
            NutritionRow(label: "Battery spent away", value: "\(stats.batterySpentAway)%", note: nil),
            NutritionRow(label: "Safety stops", value: "\(stats.safetyStops)", note: nil),
        ]
    }

    /// "Claude Code 62%, Codex 30%, Aider 8%, lime, bubbles".
    static func ingredients(_ mix: [AgentShare]) -> String {
        let agents = mix.map { "\($0.agent) \(Int(($0.share * 100).rounded()))%" }
        return (agents + ["lime", "bubbles"]).joined(separator: ", ")
    }

    /// How many empties are drawn and how many more there are.
    static func empties(_ finishedToday: Int) -> (drawn: Int, more: Int) {
        let count = max(finishedToday, 0)
        return (min(count, maxEmpties), max(count - maxEmpties, 0))
    }

    /// The label as plain text, for "Copy as text".
    static func text(_ stats: NutritionStats, range: StatsRange) -> String {
        var lines = ["Nutrition Facts, \(rangePhrase(range))", "MacBull", String(repeating: "-", count: 28)]
        for row in rows(stats) {
            let note = row.note.map { " (\($0))" } ?? ""
            lines.append("\(row.label): \(row.value)\(note)")
        }
        lines.append(String(repeating: "-", count: 28))
        lines.append("Ingredients: \(ingredients(stats.agentMix))")
        let empties = empties(stats.emptiesToday)
        if empties.drawn > 0 {
            lines.append("Empties today: \(stats.emptiesToday)")
        }
        return lines.joined(separator: "\n")
    }
}
