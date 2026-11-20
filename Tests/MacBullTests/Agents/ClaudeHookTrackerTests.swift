import Foundation
import Testing
@testable import MacBull

struct ClaudeHookTrackerTests {
    private static let start = Date(timeIntervalSince1970: 100_000)

    private static func entry(_ pid: pid_t, _ parent: pid_t, _ name: String, started: Double = 1000) -> ProcessTable.Entry {
        ProcessTable.Entry(pid: pid, parent: parent, name: name, startTime: started, cpuSeconds: 0)
    }

    private static func table(_ entries: [ProcessTable.Entry]) -> ProcessTable {
        ProcessTable(entries: Dictionary(uniqueKeysWithValues: entries.map { ($0.pid, $0) }), children: [:])
    }

    private static func event(
        _ session: String, _ name: String, parent: pid_t, at seconds: TimeInterval = 0, cwd: String? = nil,
        type: String? = nil, permissionInMessage: Bool = false
    ) -> ClaudeHookEvent {
        ClaudeHookEvent(sessionID: session, name: name, cwd: cwd, notificationType: type,
                        mentionsPermission: permissionInMessage, parentPID: parent, date: start.addingTimeInterval(seconds))
    }

    private static let claude = entry(100, 50, "claude")
    private static let shell = entry(200, 100, "sh")
    private static let otherClaude = entry(300, 50, "claude")
    private static let world = table([claude, shell, otherClaude, entry(50, 1, "zsh")])

    /// A tracker that has seen `events` and tied them to the processes in `world`.
    private static func tracker(_ events: [ClaudeHookEvent]) -> ClaudeHookTracker {
        var tracker = ClaudeHookTracker()
        tracker.ingest(events)
        tracker.resolve(table: world, sessions: [claude, otherClaude], directories: [:], now: start)
        return tracker
    }

    private static func state(_ tracker: ClaudeHookTracker, after seconds: TimeInterval,
                              process: ProcessTable.Entry = claude) -> HookVerdict.State? {
        tracker.verdict(for: ProcessKey(process), now: start.addingTimeInterval(seconds))?.state
    }

    // MARK: Your Turn mapping

    @Test(arguments: ["UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStop"])
    func workingEvents(name: String) {
        let tracker = Self.tracker([Self.event("A", name, parent: 100)])
        #expect(Self.state(tracker, after: 1) == .working)
    }

    @Test func stopIsTurnDone() {
        let tracker = Self.tracker([Self.event("A", "PreToolUse", parent: 100), Self.event("A", "Stop", parent: 100, at: 1)])
        #expect(Self.state(tracker, after: 2) == .turnDone)
    }

    @Test func sessionEndIsEnded() {
        let tracker = Self.tracker([Self.event("A", "PreToolUse", parent: 100), Self.event("A", "SessionEnd", parent: 100, at: 1)])
        #expect(Self.state(tracker, after: 2) == .ended)
    }

    @Test func permissionPromptNotificationWaitsForYou() {
        let tracker = Self.tracker([Self.event("A", "Notification", parent: 100, type: "permission_prompt")])
        #expect(Self.state(tracker, after: 1) == .waitingForYou)
    }

    @Test(arguments: ["idle_prompt", "auth_success", "elicitation_dialog"])
    func otherNotificationTypesAreTurnDone(type: String) {
        let tracker = Self.tracker([Self.event("A", "Notification", parent: 100, type: type, permissionInMessage: true)])
        #expect(Self.state(tracker, after: 1) == .turnDone)
    }

    @Test func missingTypeFallsBackToTheMessageMentioningPermission() {
        let waits = Self.tracker([Self.event("A", "Notification", parent: 100, permissionInMessage: true)])
        #expect(Self.state(waits, after: 1) == .waitingForYou)
        let done = Self.tracker([Self.event("A", "Notification", parent: 100)])
        #expect(Self.state(done, after: 1) == .turnDone)
    }

    @Test func waitingEndsWhenTheSessionWorksAgain() {
        let tracker = Self.tracker([
            Self.event("A", "Notification", parent: 100, type: "permission_prompt"),
            Self.event("A", "PostToolUse", parent: 100, at: 30),
        ])
        #expect(Self.state(tracker, after: 31) == .working)
    }

    @Test func waitingAndTurnDoneAreExactWhateverTheirAge() {
        let waiting = Self.tracker([Self.event("A", "Notification", parent: 100, type: "permission_prompt")])
        #expect(Self.state(waiting, after: 3 * 60 * 60) == .waitingForYou)
        let done = Self.tracker([Self.event("A", "Stop", parent: 100)])
        #expect(Self.state(done, after: 3 * 60 * 60) == .turnDone)
    }

    @Test func verdictCarriesTheDecidingEventTime() throws {
        let tracker = Self.tracker([
            Self.event("A", "PreToolUse", parent: 100, cwd: "/work/app"),
            Self.event("A", "Notification", parent: 100, at: 42, type: "permission_prompt"),
        ])
        let verdict = try #require(tracker.verdict(for: ProcessKey(Self.claude), now: Self.start.addingTimeInterval(50)))
        #expect(verdict.changedAt == Self.start.addingTimeInterval(42))
        #expect(verdict.lastEvent == Self.start.addingTimeInterval(42))
        #expect(verdict.sessionID == "A")
        #expect(verdict.cwd == "/work/app")
    }

    // MARK: Ported tracker behaviour

    @Test func laterEventWinsAndEarlyOnesAreForgotten() {
        let tracker = Self.tracker([
            Self.event("A", "UserPromptSubmit", parent: 100),
            Self.event("A", "Stop", parent: 100, at: 10),
            Self.event("A", "PreToolUse", parent: 100, at: 20),
        ])
        #expect(Self.state(tracker, after: 21) == .working)
    }

    @Test func workingGoesStaleAfterFiveMinutesAndFallsBackToNil() {
        let tracker = Self.tracker([Self.event("A", "PreToolUse", parent: 100)])
        let limit = ClaudeHookTracker.workingStaleAfter
        #expect(limit == 5 * 60)
        #expect(Self.state(tracker, after: limit - 1) == .working)
        #expect(Self.state(tracker, after: limit + 1) == nil)
        #expect(Self.state(tracker, after: 40 * 60) == nil)
    }

    @Test func processWithoutHookStateIsNil() {
        let tracker = Self.tracker([Self.event("A", "Stop", parent: 100)])
        #expect(Self.state(tracker, after: 1, process: Self.otherClaude) == nil)
    }

    @Test func sessionsAreTrackedPerProcess() {
        let tracker = Self.tracker([
            Self.event("A", "PreToolUse", parent: 100),
            Self.event("B", "Stop", parent: 300),
        ])
        #expect(Self.state(tracker, after: 1) == .working)
        #expect(Self.state(tracker, after: 1, process: Self.otherClaude) == .turnDone)
        let all = tracker.verdicts(now: Self.start.addingTimeInterval(1))
        #expect(all[ProcessKey(Self.claude)]?.state == .working)
        #expect(all[ProcessKey(Self.otherClaude)]?.state == .turnDone)
    }

    @Test func twoSessionIdsInOneProcessWorkingBeatsQuiet() {
        let tracker = Self.tracker([
            Self.event("A", "Stop", parent: 100, at: 5),
            Self.event("B", "PreToolUse", parent: 100, at: 1),
        ])
        #expect(Self.state(tracker, after: 6) == .working)
    }

    @Test func hookRunThroughAShellMapsToTheClaudeAbove() {
        let tracker = Self.tracker([Self.event("A", "UserPromptSubmit", parent: 200)])
        #expect(tracker.records["A"]?.process == ProcessKey(Self.claude))
        #expect(Self.state(tracker, after: 1) == .working)
    }

    @Test func deadProcessIsDropped() {
        var tracker = Self.tracker([Self.event("A", "PreToolUse", parent: 100), Self.event("B", "Stop", parent: 300)])
        let remaining = Self.table([Self.otherClaude, Self.entry(50, 1, "zsh")])
        tracker.resolve(table: remaining, sessions: [Self.otherClaude], directories: [:], now: Self.start.addingTimeInterval(5))
        #expect(tracker.records["A"] == nil)
        #expect(tracker.records["B"] != nil)
    }

    @Test func reusedPidWithANewStartTimeIsNotTheOldSession() {
        var tracker = Self.tracker([Self.event("A", "PreToolUse", parent: 100)])
        let reused = Self.entry(100, 50, "claude", started: 9000)
        tracker.resolve(table: Self.table([reused]), sessions: [reused], directories: [:], now: Self.start.addingTimeInterval(5))
        #expect(tracker.verdict(for: ProcessKey(Self.claude), now: Self.start.addingTimeInterval(5)) == nil)
    }

    @Test func eventWithNoFindableProcessIsDroppedAfterGrace() {
        var tracker = ClaudeHookTracker()
        tracker.ingest([Self.event("A", "PreToolUse", parent: 777)])
        tracker.resolve(table: Self.world, sessions: [Self.claude], directories: [:], now: Self.start.addingTimeInterval(30))
        #expect(tracker.records["A"] != nil)
        tracker.resolve(table: Self.world, sessions: [Self.claude], directories: [:],
                        now: Self.start.addingTimeInterval(ClaudeHookTracker.unresolvedGrace + 1))
        #expect(tracker.records["A"] == nil)
    }

    @Test func deadHookShellFallsBackToTheOnlySessionInThatDirectory() {
        var tracker = ClaudeHookTracker()
        tracker.ingest([Self.event("A", "PreToolUse", parent: 777, cwd: "/work/app")])
        tracker.resolve(table: Self.world, sessions: [Self.claude, Self.otherClaude],
                        directories: [100: "/work/app", 300: "/other"], now: Self.start)
        #expect(Self.state(tracker, after: 1) == .working)
    }

    @Test func twoSessionsInTheSameDirectoryAreNotGuessed() {
        var tracker = ClaudeHookTracker()
        tracker.ingest([Self.event("A", "PreToolUse", parent: 777, cwd: "/work/app")])
        tracker.resolve(table: Self.world, sessions: [Self.claude, Self.otherClaude],
                        directories: [100: "/work/app", 300: "/work/app"], now: Self.start)
        #expect(tracker.records["A"]?.process == nil)
    }

    @Test func unknownEventsAndEndOfAnUnknownSessionAreIgnored() {
        var tracker = ClaudeHookTracker()
        tracker.ingest([Self.event("A", "PreCompact", parent: 100), Self.event("B", "SessionEnd", parent: 100)])
        #expect(tracker.records.isEmpty)
    }

    @Test func laterEventsKeepTheOldCwdWhenTheyHaveNone() {
        var tracker = ClaudeHookTracker()
        tracker.ingest([Self.event("A", "PreToolUse", parent: 100, cwd: "/a"), Self.event("A", "Stop", parent: 100, at: 1)])
        #expect(tracker.records["A"]?.cwd == "/a")
    }
}
