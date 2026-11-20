import Foundation
import Testing
@testable import MacBull

struct AgentJudgeTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// The agents started an hour before the first scan.
    private static let sessionStart = t0.timeIntervalSince1970 - 3600

    private typealias Entry = ProcessTable.Entry

    private static func entry(
        _ pid: pid_t, _ parent: pid_t, _ name: String, cpu: Double = 0, started: Double = sessionStart,
        path: String? = nil, args: [String] = []
    ) -> Entry {
        Entry(pid: pid, parent: parent, name: name, startTime: started, cpuSeconds: cpu, path: path, arguments: args.isEmpty ? [name] : args)
    }

    private static func claude(cpu: Double = 0, args: [String] = ["claude"]) -> Entry {
        entry(100, 50, "claude", cpu: cpu, path: "/usr/local/bin/claude", args: args)
    }

    private static let terminal = entry(50, 1, "zsh")

    /// Runs the judge scan after scan, like the engine does.
    private struct Harness {
        var judge = AgentJudge()
        var previous: ProcessSnapshot?
        var logs = LogFacts()
        var verdicts: [ProcessKey: HookVerdict] = [:]
        var stall = true
        var directories: [pid_t: String] = [:]
        var custom: [String] = []
        var toolEvents = 0

        mutating func scan(_ entries: [Entry], at seconds: TimeInterval) -> AgentScanResult {
            let now = AgentJudgeTests.t0.addingTimeInterval(seconds)
            let snapshot = ProcessSnapshot(takenAt: now, table: ProcessTable(entries), directories: directories)
            let result = judge.judge(AgentJudge.Input(
                now: now, snapshot: snapshot, previous: previous,
                definitions: AgentCatalogue.builtIn + CustomAgentNames.definitions(for: custom),
                logs: logs, verdicts: verdicts, stallWatchdog: stall, ownPID: 1, toolEvents: toolEvents
            ))
            previous = snapshot
            return result
        }

        /// Baseline scan at 0 s, then the entries again at 10 s.
        mutating func settle(_ first: [Entry], _ second: [Entry]) -> AgentScanResult {
            _ = scan(first, at: 0)
            return scan(second, at: 10)
        }
    }

    private static func session(_ result: AgentScanResult, _ agent: String = "Claude Code") -> AgentSession? {
        result.sessions.first { $0.agent == agent }
    }

    // MARK: Baseline

    @Test func theFirstScanNeverReportsWork() {
        var harness = Harness()
        let result = harness.scan([Self.terminal, Self.claude(cpu: 500), Self.entry(101, 100, "zsh")], at: 0)
        #expect(!result.anyWorking)
        #expect(Self.session(result)?.activity == .idle)
        #expect(result.agents.map(\.name) == ["Claude Code"])
        #expect(result.agents.first?.sessions == 1)
    }

    @Test func theFirstScanShowsSessionsAndEvenCustomAgentsAsIdle() {
        var harness = Harness()
        harness.custom = ["my_agent"]
        let result = harness.scan([Self.terminal, Self.entry(300, 50, "python3", args: ["python3", "my_agent.py"])], at: 0)
        #expect(!result.anyWorking)
        #expect(result.agents.map(\.name) == ["my_agent"])
    }

    // MARK: CPU, busy, shell

    @Test func busyWhenTheTreeUsesAtLeastTenPercentOfACore() {
        var harness = Harness()
        let result = harness.settle([Self.terminal, Self.claude(cpu: 10)], [Self.terminal, Self.claude(cpu: 11)])
        #expect(Self.session(result)?.activity == .working)
        #expect(result.anyWorking)
        #expect(result.agents.first?.isWorking == true)
    }

    @Test func belowTenPercentIsIdleEvenWithASignOfLife() throws {
        var harness = Harness()
        let result = harness.settle([Self.terminal, Self.claude(cpu: 10)], [Self.terminal, Self.claude(cpu: 10.5)])
        let session = try #require(Self.session(result))
        #expect(session.activity == .idle)
        #expect(!result.anyWorking)
        // 0.5 CPU seconds is over the 0.3 sign-of-life line.
        #expect(session.lastSignOfLife == Self.t0.addingTimeInterval(10))
    }

    @Test func aQuietSessionIsIdle() throws {
        var harness = Harness()
        let result = harness.settle([Self.terminal, Self.claude(cpu: 10)], [Self.terminal, Self.claude(cpu: 10.03)])
        #expect(Self.session(result)?.activity == .idle)
        #expect(!result.anyWorking)
    }

    @Test func elapsedTimeIsClampedBetweenOneAndSixtySeconds() {
        var slow = Harness()
        _ = slow.scan([Self.terminal, Self.claude(cpu: 0)], at: 0)
        // 600 s later but clamped to 60 s: 7 CPU seconds is 11.7%.
        #expect(Self.session(slow.scan([Self.terminal, Self.claude(cpu: 7)], at: 600))?.activity == .working)
        var fast = Harness()
        _ = fast.scan([Self.terminal, Self.claude(cpu: 0)], at: 0)
        // 0.1 s later but clamped to 1 s: 0.2 CPU seconds is 20%.
        #expect(Self.session(fast.scan([Self.terminal, Self.claude(cpu: 0.2)], at: 0.1))?.activity == .working)
    }

    @Test func aShellBelowTheSessionIsARunningToolCall() {
        var harness = Harness()
        let tool = Self.entry(101, 100, "zsh", started: Self.t0.timeIntervalSince1970 - 120)
        let result = harness.settle([Self.terminal, Self.claude()], [Self.terminal, Self.claude(), tool])
        #expect(Self.session(result)?.activity == .working)
    }

    @Test func aShellOlderThanThirtyMinutesIsALeftOverServer() {
        var harness = Harness()
        let old = Self.entry(101, 100, "zsh", started: Self.t0.timeIntervalSince1970 - 31 * 60)
        let result = harness.settle([Self.terminal, Self.claude(), old], [Self.terminal, Self.claude(), old])
        #expect(Self.session(result)?.activity == .idle)
    }

    @Test func aToolThatIsNotAShellIsNotAToolCallByItself() {
        var harness = Harness()
        let child = Self.entry(101, 100, "make", started: Self.t0.timeIntervalSince1970 - 120)
        let result = harness.settle([Self.terminal, Self.claude(), child], [Self.terminal, Self.claude(), child])
        #expect(Self.session(result)?.activity == .idle)
    }

    @Test func cpuOfNonHelperChildrenCounts() {
        var harness = Harness()
        let late = Self.t0.timeIntervalSince1970 - 600
        let result = harness.settle(
            [Self.terminal, Self.claude(), Self.entry(101, 100, "cargo", cpu: 0, started: late)],
            [Self.terminal, Self.claude(), Self.entry(101, 100, "cargo", cpu: 9, started: late)]
        )
        #expect(Self.session(result)?.activity == .working)
    }

    @Test func aProcessFirstSeenAfterTheLastScanCountsAllOfItsCpu() {
        var harness = Harness()
        _ = harness.scan([Self.terminal, Self.claude()], at: 0)
        let spawned = Self.entry(101, 100, "swiftc", cpu: 5, started: Self.t0.timeIntervalSince1970 + 4)
        #expect(Self.session(harness.scan([Self.terminal, Self.claude(), spawned], at: 10))?.activity == .working)
    }

    @Test func anOlderProcessSeenForTheFirstTimeCountsNothing() {
        var harness = Harness()
        _ = harness.scan([Self.terminal, Self.claude()], at: 0)
        let old = Self.entry(101, 100, "swiftc", cpu: 500, started: Self.t0.timeIntervalSince1970 - 600)
        #expect(Self.session(harness.scan([Self.terminal, Self.claude(), old], at: 10))?.activity == .idle)
    }

    // MARK: Helpers

    @Test func helpersStartedWithTheSessionAreSkippedWithTheirSubtree() {
        var harness = Harness()
        let mcp = { (cpu: Double) in Self.entry(101, 100, "node", cpu: cpu, started: Self.sessionStart + 5) }
        let nested = { (cpu: Double) in Self.entry(102, 101, "node", cpu: cpu, started: Self.sessionStart + 400) }
        let result = harness.settle(
            [Self.terminal, Self.claude(), mcp(0), nested(0)],
            [Self.terminal, Self.claude(), mcp(50), nested(50)]
        )
        #expect(Self.session(result)?.activity == .idle)
        #expect(!result.anyWorking)
    }

    @Test(arguments: ["Google Chrome Helper", "Chromium", "chrome-headless-shell", "Electron", "typescript-language-server",
                      "tsserver", "sourcekit-lsp", "rust-analyzer", "gopls"])
    func namedHelpersAreSkippedWhenevertheyStarted(name: String) {
        var harness = Harness()
        let late = Self.t0.timeIntervalSince1970 - 600
        let result = harness.settle(
            [Self.terminal, Self.claude(), Self.entry(101, 100, name, cpu: 0, started: late)],
            [Self.terminal, Self.claude(), Self.entry(101, 100, name, cpu: 50, started: late)]
        )
        #expect(Self.session(result)?.activity == .idle)
    }

    @Test func aShellStartedWithTheSessionIsNeverAHelper() {
        var harness = Harness()
        let shell = { (cpu: Double) in Self.entry(101, 100, "zsh", cpu: cpu, started: Self.sessionStart + 2) }
        let result = harness.settle([Self.terminal, Self.claude(), shell(0)], [Self.terminal, Self.claude(), shell(20)])
        #expect(Self.session(result)?.activity == .working)
    }

    @Test func theAgentsOwnChildProcessIsNotASeparateSessionAndItsCpuCounts() {
        var harness = Harness()
        let real = { (cpu: Double) in
            Self.entry(101, 100, "claude", cpu: cpu, started: Self.sessionStart + 1, path: "/x/claude", args: ["claude"])
        }
        let result = harness.settle([Self.terminal, Self.claude(), real(0)], [Self.terminal, Self.claude(), real(30)])
        #expect(result.sessions.count == 1)
        #expect(result.agents.first?.sessions == 1)
        #expect(Self.session(result)?.activity == .working)
    }

    // MARK: Services, sessions, ordering

    @Test func serviceRunsAreNotSessions() {
        var harness = Harness()
        let service = Self.entry(200, 50, "claude", cpu: 0, path: "/usr/local/bin/claude", args: ["claude", "mcp", "serve"])
        let result = harness.settle([Self.terminal, service], [Self.terminal, Self.entry(200, 50, "claude", cpu: 90, path: "/usr/local/bin/claude", args: ["claude", "mcp", "serve"])])
        #expect(result.sessions.isEmpty)
        #expect(result.agents.isEmpty)
        #expect(!result.anyWorking)
    }

    @Test func ourOwnProcessIsNeverMatched() {
        var harness = Harness()
        let now = Self.t0
        let snapshot = ProcessSnapshot(takenAt: now, table: ProcessTable([Self.claude()]))
        let result = harness.judge.judge(AgentJudge.Input(
            now: now, snapshot: snapshot, previous: nil, definitions: AgentCatalogue.builtIn, logs: LogFacts(),
            verdicts: [:], stallWatchdog: true, ownPID: 100, toolEvents: 0
        ))
        #expect(result.sessions.isEmpty)
    }

    @Test func summariesFollowTheCatalogueWithCustomAgentsLast() {
        var harness = Harness()
        harness.custom = ["my_agent"]
        let entries = [
            Self.terminal,
            Self.entry(400, 50, "python3", args: ["python3", "my_agent.py"]),
            Self.entry(300, 50, "aider", path: "/x/aider", args: ["aider"]),
            Self.entry(200, 50, "codex", path: "/x/codex", args: ["codex"]),
            Self.claude(),
            Self.entry(101, 50, "claude", path: "/x/claude", args: ["claude"]),
        ]
        let result = harness.settle(entries, entries)
        #expect(result.agents.map(\.name) == ["Claude Code", "Codex", "Aider", "my_agent"])
        #expect(result.agents.map(\.sessions) == [2, 1, 1, 1])
        #expect(result.agents.map(\.isCustom) == [false, false, false, true])
    }

    @Test func sessionIDsAreStableAndFolderIsOnlyTheLastComponent() throws {
        var harness = Harness()
        harness.directories = [100: "/Users/sam/secret-project/app"]
        let first = harness.settle([Self.terminal, Self.claude()], [Self.terminal, Self.claude()])
        let second = harness.scan([Self.terminal, Self.claude()], at: 20)
        let a = try #require(Self.session(first))
        let b = try #require(Self.session(second))
        #expect(a.id == "100-\(Int(Self.sessionStart))")
        #expect(a.id == b.id)
        #expect(a.folder == "app")
        #expect(a.pid == 100)
        #expect(!a.isExact)
    }

    // MARK: Log writes

    private static let projectFolder = "-work-app"

    private func logHarness(write: TimeInterval?, folderExists: Bool = true, directory: String? = "/work/app") -> Harness {
        var harness = Harness()
        harness.directories = directory.map { [100: $0] } ?? [:]
        harness.logs.projectFolders = folderExists ? ["claude": [Self.projectFolder]] : ["claude": []]
        if let write {
            let time = Self.t0.addingTimeInterval(10 - write)
            harness.logs.lastWriteByAgent["claude"] = time
            harness.logs.lastWriteByProject[LogFacts.projectKey(agentID: "claude", folder: Self.projectFolder)] = time
        }
        return harness
    }

    @Test func aWriteInTheSessionsProjectFolderWithinNinetySecondsCounts() {
        var harness = logHarness(write: 30)
        let result = harness.settle([Self.terminal, Self.claude()], [Self.terminal, Self.claude()])
        #expect(Self.session(result)?.activity == .working)
    }

    @Test func aWriteOlderThanNinetySecondsDoesNot() {
        var harness = logHarness(write: 100)
        let result = harness.settle([Self.terminal, Self.claude()], [Self.terminal, Self.claude()])
        #expect(Self.session(result)?.activity == .idle)
    }

    @Test func aWriteInAnotherProjectFolderDoesNotCount() {
        var harness = logHarness(write: nil)
        harness.logs.lastWriteByAgent["claude"] = Self.t0.addingTimeInterval(5)
        harness.logs.lastWriteByProject[LogFacts.projectKey(agentID: "claude", folder: "-other")] = Self.t0.addingTimeInterval(5)
        let result = harness.settle([Self.terminal, Self.claude()], [Self.terminal, Self.claude()])
        #expect(Self.session(result)?.activity == .idle)
    }

    @Test func withoutAProjectFolderYetAnyWriteByTheAgentCounts() {
        var harness = logHarness(write: 20, folderExists: false)
        harness.logs.lastWriteByProject = [:]
        let result = harness.settle([Self.terminal, Self.claude()], [Self.terminal, Self.claude()])
        #expect(Self.session(result)?.activity == .working)
    }

    @Test func aFallbackWriteNeverKeepsAOneShotRunAlive() {
        var harness = logHarness(write: 20, folderExists: false)
        harness.logs.lastWriteByProject = [:]
        harness.stall = false
        let args = ["claude", "-p", "build it"]
        _ = harness.scan([Self.terminal, Self.claude(args: args)], at: 0)
        _ = harness.scan([Self.terminal, Self.claude(args: args)], at: 10)
        // Alive for 25 minutes with fresh fallback writes each time, but never a sign of life.
        harness.logs.lastWriteByAgent["claude"] = Self.t0.addingTimeInterval(25 * 60 - 5)
        let result = harness.scan([Self.terminal, Self.claude(args: args)], at: 25 * 60)
        #expect(Self.session(result)?.activity == .idle)
    }

    @Test func aCountingWriteKeepsAOneShotRunAlive() {
        var harness = logHarness(write: nil)
        harness.stall = false
        let args = ["claude", "-p", "build it"]
        _ = harness.scan([Self.terminal, Self.claude(args: args)], at: 0)
        _ = harness.scan([Self.terminal, Self.claude(args: args)], at: 10)
        harness.logs.lastWriteByProject[LogFacts.projectKey(agentID: "claude", folder: Self.projectFolder)] = Self.t0.addingTimeInterval(25 * 60 - 5)
        harness.logs.projectFolders = ["claude": [Self.projectFolder]]
        harness.directories = [100: "/work/app"]
        let result = harness.scan([Self.terminal, Self.claude(args: args)], at: 25 * 60)
        #expect(Self.session(result)?.activity == .backgroundRun)
    }

    @Test func agentsWithoutPerProjectFoldersCountAnyWriteForAllTheirSessions() {
        var harness = Harness()
        harness.logs.lastWriteByAgent["codex"] = Self.t0.addingTimeInterval(5)
        let codex = { Self.entry(200, 50, "codex", path: "/x/codex", args: ["codex"]) }
        let result = harness.settle([Self.terminal, codex()], [Self.terminal, codex()])
        #expect(Self.session(result, "Codex")?.activity == .working)
    }

    @Test func agentsWithNoLogFolderIgnoreLogFacts() {
        var harness = Harness()
        harness.logs.lastWriteByAgent["aider"] = Self.t0.addingTimeInterval(5)
        let aider = { Self.entry(200, 50, "aider", path: "/x/aider", args: ["aider"]) }
        let result = harness.settle([Self.terminal, aider()], [Self.terminal, aider()])
        #expect(Self.session(result, "Aider")?.activity == .idle)
    }

    // MARK: One-shot runs and the Stall Watchdog

    private func oneShot(stall: Bool) -> Harness {
        var harness = Harness()
        harness.stall = stall
        let entries = [Self.terminal, Self.claude(args: ["claude", "-p", "refactor"])]
        _ = harness.scan(entries, at: 0)
        _ = harness.scan(entries, at: 10)
        return harness
    }

    private func quietOneShot(_ harness: inout Harness, after silence: TimeInterval) -> AgentSession? {
        // The last sign of life was the first scan (0 s): first seen counts as alive.
        Self.session(harness.scan([Self.terminal, Self.claude(args: ["claude", "-p", "refactor"])], at: silence))
    }

    @Test func aOneShotRunWorksWhileAliveWithoutAnyCpu() {
        var harness = oneShot(stall: false)
        let result = harness.scan([Self.terminal, Self.claude(args: ["claude", "-p", "x"])], at: 60)
        #expect(Self.session(result)?.activity == .backgroundRun)
        #expect(result.anyWorking)
        #expect(result.agents.first?.backgroundRuns == 1)
    }

    @Test func withoutTheWatchdogAOneShotRunGoesStaleAtTwentyMinutes() {
        var harness = oneShot(stall: false)
        #expect(quietOneShot(&harness, after: 20 * 60 - 1)?.activity == .backgroundRun)
        let stale = quietOneShot(&harness, after: 20 * 60)
        #expect(stale?.activity == .idle)
    }

    @Test func theWatchdogFlagsAStallAtTenMinutesAndItStillCountsUntilTwenty() throws {
        var harness = oneShot(stall: true)
        #expect(quietOneShot(&harness, after: 10 * 60 - 1)?.activity == .backgroundRun)
        let stalled = try #require(quietOneShot(&harness, after: 10 * 60))
        #expect(stalled.activity == .stalled)
        #expect(stalled.since == Self.t0.addingTimeInterval(10 * 60))
        var counting = oneShot(stall: true)
        let result = counting.scan([Self.terminal, Self.claude(args: ["claude", "-p", "refactor"])], at: 20 * 60 - 1)
        #expect(result.anyWorking)
        #expect(result.agents.first?.stalled == 1)
        #expect(result.agents.first?.backgroundRuns == 0)
    }

    @Test func aStalledRunStopsCountingAtTwentyMinutesButStaysFlagged() {
        var harness = oneShot(stall: true)
        let result = harness.scan([Self.terminal, Self.claude(args: ["claude", "-p", "refactor"])], at: 20 * 60)
        #expect(Self.session(result)?.activity == .stalled)
        #expect(!result.anyWorking)
        #expect(result.agents.first?.isWorking == false)
        #expect(result.agents.first?.stalled == 1)
    }

    @Test func anySignOfLifeBringsAStalledRunBackToWorking() {
        var harness = oneShot(stall: true)
        let quiet = [Self.terminal, Self.claude(args: ["claude", "-p", "refactor"])]
        #expect(Self.session(harness.scan(quiet, at: 12 * 60))?.activity == .stalled)
        let busy = [Self.terminal, Self.claude(cpu: 20, args: ["claude", "-p", "refactor"])]
        let result = harness.scan(busy, at: 12 * 60 + 10)
        #expect(Self.session(result)?.activity == .backgroundRun)
        #expect(result.anyWorking)
    }

    @Test func theWatchdogDoesNotTouchAnInteractiveSessionThatIsJustQuiet() {
        var harness = Harness()
        let entries = [Self.terminal, Self.claude()]
        _ = harness.scan(entries, at: 0)
        #expect(Self.session(harness.scan(entries, at: 30 * 60))?.activity == .idle)
    }

    @Test func aCustomAgentCountsForAsLongAsItRuns() {
        var harness = Harness()
        harness.custom = ["my_agent.py"]
        let agent = Self.entry(400, 50, "python3", args: ["python3", "my_agent.py"])
        _ = harness.scan([Self.terminal, agent], at: 0)
        let result = harness.scan([Self.terminal, agent], at: 3 * 3600)
        #expect(Self.session(result, "my_agent.py")?.activity == .running)
        #expect(result.anyWorking)
        #expect(result.agents.first?.backgroundRuns == 0)
        #expect(result.agents.first?.isCustom == true)
    }

    // MARK: Hook verdicts (exact) and Your Turn

    private func verdict(_ state: HookVerdict.State, id: String = "sess-1", at seconds: TimeInterval = 5, cwd: String? = "/Users/sam/api") -> HookVerdict {
        let time = Self.t0.addingTimeInterval(seconds)
        return HookVerdict(state: state, sessionID: id, lastEvent: time, changedAt: time, cwd: cwd)
    }

    private static let claudeKey = ProcessKey(pid: 100, startTime: sessionStart)

    @Test func aWorkingVerdictBeatsASilentProcess() throws {
        var harness = Harness()
        harness.verdicts = [Self.claudeKey: verdict(.working)]
        let result = harness.settle([Self.terminal, Self.claude()], [Self.terminal, Self.claude()])
        let session = try #require(Self.session(result))
        #expect(session.activity == .working)
        #expect(session.isExact)
        #expect(session.id == "sess-1")
        #expect(session.folder == "api")
        #expect(result.anyWorking)
    }

    @Test func aTurnDoneVerdictBeatsABusyProcess() {
        var harness = Harness()
        harness.verdicts = [Self.claudeKey: verdict(.turnDone)]
        let result = harness.settle([Self.terminal, Self.claude(cpu: 0)], [Self.terminal, Self.claude(cpu: 50), Self.entry(101, 100, "zsh", started: Self.t0.timeIntervalSince1970 - 5)])
        #expect(Self.session(result)?.activity == .turnDone)
        #expect(!result.anyWorking)
    }

    @Test func withoutAVerdictTheGuessingRulesDecide() {
        var harness = Harness()
        let result = harness.settle([Self.terminal, Self.claude(cpu: 0)], [Self.terminal, Self.claude(cpu: 50)])
        #expect(Self.session(result)?.activity == .working)
        #expect(Self.session(result)?.isExact == false)
    }

    @Test func waitingForYouDoesNotCountAndIsSummarised() throws {
        var harness = Harness()
        harness.verdicts = [Self.claudeKey: verdict(.waitingForYou, at: -7)]
        let result = harness.settle([Self.terminal, Self.claude()], [Self.terminal, Self.claude()])
        let session = try #require(Self.session(result))
        #expect(session.activity == .waitingForYou)
        #expect(session.since == Self.t0.addingTimeInterval(-7))
        #expect(!result.anyWorking)
        #expect(result.agents.first?.waitingForYou == 1)
        #expect(result.agents.first?.isWorking == false)
    }

    @Test func endedVerdictShowsEndedAndDoesNotCount() {
        var harness = Harness()
        harness.verdicts = [Self.claudeKey: verdict(.ended)]
        let result = harness.settle([Self.terminal, Self.claude()], [Self.terminal, Self.claude()])
        #expect(Self.session(result)?.activity == .ended)
        #expect(!result.anyWorking)
    }

    @Test func sinceIsWhenTheActivityLastChanged() throws {
        var harness = Harness()
        harness.verdicts = [Self.claudeKey: verdict(.working, at: 3)]
        _ = harness.scan([Self.terminal, Self.claude()], at: 0)
        let working = try #require(Self.session(harness.scan([Self.terminal, Self.claude()], at: 10)))
        #expect(working.since == Self.t0.addingTimeInterval(3))
        // More events, same activity: since stays.
        harness.verdicts = [Self.claudeKey: verdict(.working, at: 18)]
        #expect(Self.session(harness.scan([Self.terminal, Self.claude()], at: 20))?.since == Self.t0.addingTimeInterval(3))
        // Waits for the user: a new activity, since is the event time.
        harness.verdicts = [Self.claudeKey: verdict(.waitingForYou, at: 25)]
        let waiting = try #require(Self.session(harness.scan([Self.terminal, Self.claude()], at: 30)))
        #expect(waiting.since == Self.t0.addingTimeInterval(25))
        // And a heuristic session with no event: since is the scan that saw the change.
        harness.verdicts = [:]
        let guessed = try #require(Self.session(harness.scan([Self.terminal, Self.claude()], at: 40)))
        #expect(guessed.activity == .idle)
        #expect(guessed.since == Self.t0.addingTimeInterval(40))
    }

    @Test func aWorkingVerdictOnAOneShotRunCountsAsABackgroundRun() {
        var harness = Harness()
        harness.verdicts = [Self.claudeKey: verdict(.working)]
        let entries = [Self.terminal, Self.claude(args: ["claude", "-p", "x"])]
        let result = harness.settle(entries, entries)
        #expect(Self.session(result)?.activity == .backgroundRun)
        #expect(result.agents.first?.backgroundRuns == 1)
    }

    @Test func aHookEventIsASignOfLifeForTheWatchdog() throws {
        var harness = Harness()
        let entries = [Self.terminal, Self.claude(args: ["claude", "-p", "x"])]
        _ = harness.scan(entries, at: 0)
        _ = harness.scan(entries, at: 10)
        // Nothing for 12 minutes: stalled.
        #expect(Self.session(harness.scan(entries, at: 12 * 60))?.activity == .stalled)
        // A fresh hook event is a sign of life.
        harness.verdicts = [Self.claudeKey: verdict(.working, at: 12 * 60 + 5)]
        let result = harness.scan(entries, at: 12 * 60 + 10)
        let session = try #require(Self.session(result))
        #expect(session.activity == .backgroundRun)
        #expect(session.lastSignOfLife == Self.t0.addingTimeInterval(12 * 60 + 5))
    }

    @Test func toolEventsAreReportedAsGiven() {
        var harness = Harness()
        harness.toolEvents = 4
        #expect(harness.scan([Self.terminal], at: 0).toolEvents == 4)
    }
}
