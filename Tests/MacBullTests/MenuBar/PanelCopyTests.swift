import AppKit
import Foundation
import Testing
@testable import MacBull

private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

struct PanelFormatTests {
    @Test func durationsRoundDownToWholeMinutes() {
        #expect(PanelFormat.duration(0) == "<1 min")
        #expect(PanelFormat.duration(59) == "<1 min")
        #expect(PanelFormat.duration(60) == "1 min")
        #expect(PanelFormat.duration(6 * 60 + 40) == "6 min")
        #expect(PanelFormat.duration(3600) == "1 h")
        #expect(PanelFormat.duration(3600 + 5 * 60) == "1 h 5 min")
        #expect(PanelFormat.duration(7 * 3600 + 12 * 60) == "7 h 12 min")
        #expect(PanelFormat.duration(-30) == "<1 min")
    }

    @Test func waitTimeReadsLikeASentence() {
        #expect(PanelFormat.waiting(since: noon.addingTimeInterval(-6 * 60), now: noon) == "waiting 6 min")
        #expect(PanelFormat.waiting(since: noon.addingTimeInterval(-10), now: noon) == "waiting <1 min")
        #expect(PanelFormat.waiting(since: noon.addingTimeInterval(-75 * 60), now: noon) == "waiting 1 h 15 min")
    }

    @Test func stallTimeCountsFromTheLastSignOfLife() {
        #expect(PanelFormat.stalled(lastSignOfLife: noon.addingTimeInterval(-12 * 60), now: noon) == "no activity for 12 min")
    }

    @Test func countdownIsMinutesUnderAnHourAndHoursAfter() {
        #expect(PanelFormat.countdown(remaining: 5) == "0:05")
        #expect(PanelFormat.countdown(remaining: 59.2) == "1:00", "seconds round up")
        #expect(PanelFormat.countdown(remaining: 15 * 60) == "15:00")
        #expect(PanelFormat.countdown(remaining: 3599) == "59:59")
        #expect(PanelFormat.countdown(remaining: 3600) == "1:00:00")
        #expect(PanelFormat.countdown(remaining: 95 * 60) == "1:35:00")
        #expect(PanelFormat.countdown(remaining: -4) == "0:00")
    }

    @Test func listsReadNaturally() {
        #expect(PanelFormat.naturalList([]) == "")
        #expect(PanelFormat.naturalList(["Codex"]) == "Codex")
        #expect(PanelFormat.naturalList(["Codex", "Aider"]) == "Codex and Aider")
        #expect(PanelFormat.naturalList(["Claude Code", "Codex", "Aider"]) == "Claude Code, Codex and Aider")
    }
}

struct HeroCopyTests {
    private func facts(
        drag: PourStop? = nil, manual: ManualSession? = nil, agentHold: Bool = false, paused: Bool = false,
        agentMode: Bool = true, working: [String] = [], background: Bool = false
    ) -> HeroFacts {
        HeroFacts(drag: drag, manual: manual, agentHold: agentHold, paused: paused, agentMode: agentMode,
                  workingAgents: working, hasBackgroundRun: background, now: noon)
    }

    private func timed(_ seconds: TimeInterval) -> ManualSession {
        ManualSession(minutes: 60, startedAt: noon, endsAt: noon.addingTimeInterval(seconds))
    }

    private let untilOff = ManualSession(minutes: 0, startedAt: noon, endsAt: nil)

    @Test func titleTable() {
        #expect(HeroCopy.title(facts(drag: .h2)) == .text("2h"))
        #expect(HeroCopy.title(facts(drag: .untilOff)) == .infinity)
        #expect(HeroCopy.title(facts(drag: .off)) == .text("Off"))
        #expect(HeroCopy.title(facts(manual: timed(95 * 60))) == .text("1:35:00"))
        #expect(HeroCopy.title(facts(manual: timed(125))) == .text("2:05"))
        #expect(HeroCopy.title(facts(manual: untilOff)) == .infinity)
        #expect(HeroCopy.title(facts(agentHold: true)) == .text("Charged"))
        #expect(HeroCopy.title(facts()) == .text("Off"))
    }

    @Test func dragBeatsEverythingInTheTitle() {
        #expect(HeroCopy.title(facts(drag: .m15, manual: untilOff, agentHold: true)) == .text("15m"))
        #expect(HeroCopy.sentence(facts(drag: .m15, manual: untilOff)) == "Let go to set the time")
    }

    @Test func sentenceTable() {
        #expect(HeroCopy.sentence(facts(manual: untilOff)) == "Awake until you say stop")
        #expect(HeroCopy.sentence(facts(manual: timed(600))) == "Then your Mac sleeps like normal")
        #expect(HeroCopy.sentence(facts(manual: timed(600), working: ["Codex"])) == "Codex is working too")
        #expect(HeroCopy.sentence(facts(manual: untilOff, working: ["Claude Code", "Codex"])) == "Claude Code and Codex are working too")
        #expect(HeroCopy.sentence(facts(agentHold: true, working: ["Aider"])) == "Aider is working, staying up until done")
        #expect(HeroCopy.sentence(facts(agentHold: true, working: ["Aider", "Codex"])) == "Aider and Codex are working, staying up until done")
        #expect(HeroCopy.sentence(facts(agentHold: true, working: ["Codex"], background: true)) == "A background run is going, staying up until it is done")
        #expect(HeroCopy.sentence(facts(agentHold: true)) == "Agents just finished, letting go in a few minutes")
        #expect(HeroCopy.sentence(facts(paused: true)) == "Paused until your agents finish")
        #expect(HeroCopy.sentence(facts()) == "Sleeps like normal and wakes up by itself when an agent starts working")
        #expect(HeroCopy.sentence(facts(agentMode: false)) == "Sleeps like normal. Drag up on the can to add time.")
    }

    @Test func levelTable() {
        #expect(HeroCopy.level(facts(drag: .h1)) == 3.0 / 8)
        #expect(HeroCopy.level(facts(manual: untilOff)) == 1)
        #expect(HeroCopy.level(facts(manual: timed(3600))) == 3.0 / 8)
        #expect(HeroCopy.level(facts(manual: timed(-5))) == 0)
        #expect(HeroCopy.level(facts(agentHold: true)) == 1)
        #expect(HeroCopy.level(facts()) == 0)
    }

    @Test func spokenValueCarriesTitleAndSentence() {
        #expect(HeroCopy.spokenValue(facts(manual: untilOff)) == "until you turn it off. Awake until you say stop")
    }
}

struct ModesCopyTests {
    private func agent(_ name: String, sessions: Int = 1, working: Bool = false, runs: Int = 0, custom: Bool = false,
                       waiting: Int = 0, stalled: Int = 0) -> AgentSummary {
        AgentSummary(name: name, sessions: sessions, isWorking: working, backgroundRuns: runs, isCustom: custom,
                     waitingForYou: waiting, stalled: stalled)
    }

    private func facts(
        mode: Bool = true, agents: [AgentSummary] = [], awake: Bool = false, cutoff: SafetyStop? = nil,
        paused: Bool = false, hold: Bool = false, lid: Bool = false
    ) -> ModesCopy.AgentsFacts {
        ModesCopy.AgentsFacts(agentMode: mode, agents: agents, isAwake: awake, cutoff: cutoff, paused: paused,
                              agentHold: hold, lidEffectivelyOn: lid)
    }

    @Test func agentsDetailFollowsTheFirstMatch() {
        #expect(ModesCopy.agentsDetail(facts(mode: false, agents: [agent("Codex")])).hasPrefix("Off."))
        #expect(ModesCopy.agentsDetail(facts()).hasPrefix("None open."))
        #expect(ModesCopy.agentsDetail(facts(agents: [agent("Codex")], cutoff: .heat)) == "Stopped because your Mac got warm")
        #expect(ModesCopy.agentsDetail(facts(agents: [agent("Codex")], cutoff: .battery)) == "Stopped because the battery is low")
        #expect(ModesCopy.agentsDetail(facts(agents: [agent("Codex", working: true)], paused: true)) == "Paused by you until they finish")
        #expect(ModesCopy.agentsDetail(facts(agents: [agent("Codex", working: true, runs: 1)], awake: true, hold: true))
                == "A background run is going, staying up until done")
        #expect(ModesCopy.agentsDetail(facts(agents: [agent("Codex", working: true, runs: 2)], awake: true, hold: true, lid: true))
                == "2 background runs are going, staying up until done, lid closed too")
        #expect(ModesCopy.agentsDetail(facts(agents: [agent("Claude Code", working: true), agent("Aider", working: true)], awake: true, hold: true))
                == "Claude Code and Aider working, staying up")
        #expect(ModesCopy.agentsDetail(facts(agents: [agent("Codex")], awake: true, hold: true)) == "Just finished, letting go in a few minutes")
        #expect(ModesCopy.agentsDetail(facts(agents: [agent("Codex")])) == "One session open but idle, so your Mac can sleep")
        #expect(ModesCopy.agentsDetail(facts(agents: [agent("Codex", sessions: 2), agent("Aider")])) == "3 open, all idle, so your Mac can sleep")
    }

    @Test func userAddedAgentsNeverCountAsBackgroundRuns() {
        let custom = agent("my-bot", working: true, runs: 1, custom: true)
        #expect(ModesCopy.agentsDetail(facts(agents: [custom], awake: true, hold: true)) == "my-bot working, staying up")
    }

    @Test func lidDetailTable() {
        #expect(ModesCopy.lidDetail(setup: .notSetUp, lidHold: true, isAwake: true) == "Needs your password once")
        #expect(ModesCopy.lidDetail(setup: .ready, lidHold: false, isAwake: true) == "Closing the lid puts the Mac to sleep")
        #expect(ModesCopy.lidDetail(setup: .ready, lidHold: true, isAwake: true) == "Close the lid and the work keeps going")
        #expect(ModesCopy.lidDetail(setup: .ready, lidHold: true, isAwake: false).hasPrefix("While MacBull is on"))
    }

    @Test func lidIsEffectivelyOnOnlyWhenSetUpAndSwitchedOn() {
        #expect(ModesCopy.lidEffectivelyOn(setup: .ready, lidHold: true))
        #expect(!ModesCopy.lidEffectivelyOn(setup: .ready, lidHold: false))
        #expect(!ModesCopy.lidEffectivelyOn(setup: .notSetUp, lidHold: true))
    }

    @Test func statusWordsPerAgent() {
        #expect(ModesCopy.status(of: agent("a", custom: true)) == .running)
        #expect(ModesCopy.status(of: agent("a", runs: 1)) == .backgroundRun)
        #expect(ModesCopy.status(of: agent("a", working: true)) == .working)
        #expect(ModesCopy.status(of: agent("a", waiting: 1)) == .waiting)
        #expect(ModesCopy.status(of: agent("a", stalled: 1)) == .stalled)
        #expect(ModesCopy.status(of: agent("a")) == .idle)
        #expect(ModesCopy.AgentStatus.allWords == ["Running", "Background run", "Working", "Waiting for you", "Stuck", "Idle"])
    }

    @Test func foldersAreListedOnlyForHookSessions() {
        let claude = agent("Claude Code", sessions: 3)
        func session(_ id: String, folder: String?, exact: Bool, activity: SessionActivity = .working) -> AgentSession {
            AgentSession(id: id, agent: "Claude Code", folder: folder, activity: activity, since: noon, lastSignOfLife: noon, isExact: exact, pid: 1)
        }
        let sessions = [
            session("a", folder: "api", exact: true), session("b", folder: nil, exact: true),
            session("c", folder: "web", exact: false), session("d", folder: "old", exact: true, activity: .ended),
        ]
        #expect(ModesCopy.detailedSessions(of: claude, in: sessions).map(\.id) == ["a"])
    }
}

extension ModesCopy.AgentStatus {
    static var allWords: [String] {
        [Self.running, .backgroundRun, .working, .waiting, .stalled, .idle].map(\.word)
    }
}

struct YourTurnRowTests {
    private func session(_ id: String, _ activity: SessionActivity, since: TimeInterval, life: TimeInterval = 0, pid: Int32? = 1) -> AgentSession {
        AgentSession(id: id, agent: "Claude Code", folder: id, activity: activity, since: noon.addingTimeInterval(-since),
                     lastSignOfLife: noon.addingTimeInterval(-life), isExact: true, pid: pid)
    }

    @Test func waitingFirstLongestWaitFirstThenStalled() {
        let rows = YourTurnRows.rows(from: [
            session("working", .working, since: 5),
            session("stalledNew", .stalled, since: 700, life: 700),
            session("waitNew", .waitingForYou, since: 60),
            session("stalledOld", .stalled, since: 2000, life: 2000),
            session("waitOld", .waitingForYou, since: 600),
            session("done", .turnDone, since: 1),
        ])
        #expect(rows.map(\.id) == ["waitOld", "waitNew", "stalledOld", "stalledNew"])
    }

    @Test func noRowsWhenNobodyWaits() {
        #expect(YourTurnRows.rows(from: [session("a", .working, since: 1), session("b", .idle, since: 1)]).isEmpty)
    }

    @Test func aSessionWithoutAProcessIsNotClickable() {
        #expect(YourTurnRows.isClickable(session("a", .waitingForYou, since: 1, pid: 42)))
        #expect(!YourTurnRows.isClickable(session("a", .waitingForYou, since: 1, pid: nil)))
    }
}

struct LiveCarbonationTests {
    private func amber(
        thermal: ProcessInfo.ThermalState = .nominal, onBattery: Bool = false, percent: Int? = 80,
        guardOn: Bool = true, limit: Int = 20
    ) -> Bool {
        LiveCarbonation.isAmber(thermal: thermal, onBattery: onBattery, batteryPercent: percent, batteryGuard: guardOn, batteryLimit: limit)
    }

    @Test func coolAndPluggedInStaysLime() {
        #expect(!amber())
        #expect(!amber(thermal: .fair))
    }

    @Test func seriousHeatOrWorseTurnsAmber() {
        #expect(amber(thermal: .serious))
        #expect(amber(thermal: .critical))
    }

    @Test func batteryWithinTenPointsOfTheLimitTurnsAmber() {
        #expect(!amber(onBattery: true, percent: 31))
        #expect(amber(onBattery: true, percent: 30))
        #expect(amber(onBattery: true, percent: 12))
        #expect(amber(onBattery: true, percent: 40, limit: 30))
        #expect(!amber(onBattery: true, percent: 41, limit: 30))
    }

    @Test func pluggedInOrNoReadingOrNoGuardNeverTurnsAmberFromTheBattery() {
        #expect(!amber(onBattery: false, percent: 5))
        #expect(!amber(onBattery: true, percent: nil))
        #expect(!amber(onBattery: true, percent: 5, guardOn: false))
    }

    @Test func moreWorkingSessionsMoreBubbles() {
        let counts = (0...6).map { LiveCarbonation.bubbleCount(workingSessions: $0) }
        #expect(counts == [6, 6, 9, 12, 12, 12, 12])
        #expect(counts.allSatisfy { $0 <= LiveCarbonation.maxBubbles })
    }

    @Test func onlyWorkingKindsCountAsWorkingSessions() {
        func session(_ activity: SessionActivity) -> AgentSession {
            AgentSession(id: "\(activity)", agent: "A", folder: nil, activity: activity, since: noon, lastSignOfLife: noon, isExact: false, pid: nil)
        }
        let sessions = [.working, .backgroundRun, .running, .idle, .waitingForYou, .turnDone, .stalled, .ended].map(session)
        #expect(LiveCarbonation.workingSessions(sessions) == 3)
    }

    @Test func oneExtraBubblePerToolCall() {
        #expect(LiveCarbonation.pulsesAdded(from: 4, to: 5) == 1)
        #expect(LiveCarbonation.pulsesAdded(from: 4, to: 7) == 3)
        #expect(LiveCarbonation.pulsesAdded(from: 4, to: 4) == 0)
        #expect(LiveCarbonation.pulsesAdded(from: 9, to: 2) == 0)
        #expect(LiveCarbonation.pulsesAdded(from: 0, to: 500) == LiveCarbonation.maxPulses)
    }
}

struct FoamRuleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func date(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour)) ?? .distantPast
    }

    @Test func firstTimeEverFoams() {
        #expect(FoamRule.isAllowed(lastFoam: nil, now: date(19, hour: 12), reduceMotion: false, calendar: calendar))
    }

    @Test func onlyOncePerCalendarDay() {
        #expect(!FoamRule.isAllowed(lastFoam: date(19, hour: 9), now: date(19, hour: 23), reduceMotion: false, calendar: calendar))
        #expect(FoamRule.isAllowed(lastFoam: date(19, hour: 23), now: date(20, hour: 0), reduceMotion: false, calendar: calendar))
        #expect(FoamRule.isAllowed(lastFoam: date(10, hour: 12), now: date(19, hour: 12), reduceMotion: false, calendar: calendar))
    }

    @Test func neverWithReduceMotion() {
        #expect(!FoamRule.isAllowed(lastFoam: nil, now: date(19, hour: 12), reduceMotion: true, calendar: calendar))
    }

    @Test func holdIsTwoSeconds() {
        #expect(FoamRule.holdSeconds == 2)
    }

    @Test func theDateIsKeptUnderTheAgreedKey() throws {
        let defaults = try #require(UserDefaults(suiteName: "macbull.foam.\(UUID().uuidString)"))
        let store = FoamStore(defaults: defaults)
        #expect(store.lastFoam == nil)
        store.record(date(19, hour: 12))
        #expect(store.lastFoam == date(19, hour: 12))
        #expect(defaults.object(forKey: "feel.lastFoam") as? Date == date(19, hour: 12))
    }
}

struct ReceiptFormatTests {
    private func receipt(lines: [ReceiptLine] = [], stop: SafetyStop? = nil, slept: Int = 0, peak: Int = 0,
                         battery: (Int, Int)? = nil, plugged: Bool = false, notRunning: Date? = nil) -> Receipt {
        Receipt(id: UUID(), awayFrom: noon, awayTo: noon.addingTimeInterval(7 * 3600 + 12 * 60), lines: lines,
                batteryStart: battery?.0, batteryEnd: battery?.1, pluggedIn: plugged, peakThermal: peak,
                sleptAt: (0..<slept).map { noon.addingTimeInterval(Double($0) * 60) }, safetyStop: stop, notRunningSince: notRunning)
    }

    @Test func awayDuration() {
        #expect(ReceiptFormat.away(receipt()) == "7 h 12 min")
    }

    @Test func summaryCountsOutcomes() {
        let lines = [
            ReceiptLine(agent: "A", folder: nil, outcome: .finished(at: noon, afterSeconds: 60)),
            ReceiptLine(agent: "B", folder: nil, outcome: .finished(at: noon, afterSeconds: 60)),
            ReceiptLine(agent: "C", folder: nil, outcome: .waitingForYou(since: noon)),
            ReceiptLine(agent: "D", folder: nil, outcome: .stalled(since: noon)),
        ]
        #expect(ReceiptFormat.summary(receipt(lines: lines)) == "2 turns done in 2 projects, 1 waiting for you, 1 stuck")
        #expect(ReceiptFormat.summary(receipt(stop: .heat)) == "safety stop")
        #expect(ReceiptFormat.summary(receipt()) == "quiet")
    }

    // MARK: Grouping

    private func finished(_ agent: String, _ folder: String?, turns: Int, work: TimeInterval, at hour: Int = 7) -> ReceiptLine {
        ReceiptLine(agent: agent, folder: folder, outcome: .finished(at: noon.addingTimeInterval(Double(hour) * 60), afterSeconds: 60),
                    turns: turns, workSeconds: work)
    }

    @Test func groupsByAgentAndFolderAndNilFolderIsTheAgentAlone() {
        let lines = [
            finished("Claude Code", "brain", turns: 2, work: 600),
            finished("Claude Code", "brain", turns: 3, work: 1_200),
            finished("Codex", "brain", turns: 1, work: 300),
            finished("Codex", nil, turns: 1, work: 300),
            finished("Codex", nil, turns: 2, work: 300),
        ]
        let groups = ReceiptFormat.groups(lines)
        #expect(groups.count == 3)
        #expect(groups.map(\.title) == ["Claude Code / brain", "Codex", "Codex / brain"])
        #expect(groups[0].turns == 5)
        #expect(groups[0].workSeconds == 1_800)
        #expect(groups[1].folder == nil)
        #expect(groups[1].turns == 3)
    }

    @Test func orderPutsWaitingStuckWorkingFirstThenFinishedByWorkTime() {
        let lines = [
            finished("A", "short", turns: 1, work: 600),
            finished("A", "long", turns: 1, work: 7_200),
            ReceiptLine(agent: "A", folder: "working", outcome: .stillWorking),
            ReceiptLine(agent: "A", folder: "stuck", outcome: .stalled(since: noon)),
            ReceiptLine(agent: "A", folder: "waiting", outcome: .waitingForYou(since: noon)),
        ]
        #expect(ReceiptFormat.groups(lines).map(\.title) == ["A / waiting", "A / stuck", "A / working", "A / long", "A / short"])
    }

    @Test func aWaitingSessionMakesTheWholeGroupWaitingSinceTheEarliest() {
        let lines = [
            finished("A", "web", turns: 7, work: 3_600),
            ReceiptLine(agent: "A", folder: "web", outcome: .waitingForYou(since: noon.addingTimeInterval(600))),
            ReceiptLine(agent: "A", folder: "web", outcome: .waitingForYou(since: noon.addingTimeInterval(60))),
        ]
        let groups = ReceiptFormat.groups(lines)
        #expect(groups.count == 1)
        #expect(groups[0].state == .waiting)
        #expect(groups[0].moment == noon.addingTimeInterval(60))
        #expect(groups[0].turns == 7)
        #expect(ReceiptFormat.detail(.group(groups[0])) == "waiting for you since \(PanelFormat.clock(noon.addingTimeInterval(60)))")
    }

    @Test func quickGroupsFoldIntoOneRowAtTheEnd() {
        let lines = [
            finished("A", "big", turns: 9, work: 6_720),
            finished("A", "q1", turns: 2, work: 119),
            finished("A", "q2", turns: 3, work: 30),
            finished("A", "edge", turns: 1, work: ReceiptFormat.quickRunSeconds),
            ReceiptLine(agent: "A", folder: "waiting", outcome: .waitingForYou(since: noon)),
        ]
        let rows = ReceiptFormat.rows(lines)
        #expect(rows.map(ReceiptFormat.title) == ["A / waiting", "A / big", "A / edge", "+ 5 quick runs in 2 projects"])
        #expect(ReceiptFormat.detail(rows[3]) == nil)
    }

    @Test func aSingleQuickGroupKeepsItsName() {
        let rows = ReceiptFormat.rows([finished("A", "big", turns: 2, work: 3_600), finished("A", "q1", turns: 1, work: 20)])
        #expect(rows.map(ReceiptFormat.title) == ["A / big", "A / q1"])
    }

    @Test func foldedRowPluralisation() {
        #expect(ReceiptFormat.title(.quick(runs: 1, projects: 1)) == "+ 1 quick run in 1 project")
        #expect(ReceiptFormat.title(.quick(runs: 6, projects: 4)) == "+ 6 quick runs in 4 projects")
    }

    @Test func endedOnlyGroupIsNeverFolded() {
        let lines = [
            ReceiptLine(agent: "A", folder: "gone", outcome: .ended(at: noon)),
            finished("A", "q1", turns: 1, work: 20),
            finished("A", "q2", turns: 1, work: 20),
        ]
        let rows = ReceiptFormat.rows(lines)
        #expect(rows.map(ReceiptFormat.title) == ["A / gone", "+ 2 quick runs in 2 projects"])
        #expect(ReceiptFormat.detail(rows[0]) == "ended \(PanelFormat.clock(noon))")
    }

    @Test func capAndShowAllCount() {
        let rows = (0..<7).map { ReceiptFormat.Row.quick(runs: $0, projects: 1) }
        let collapsed = ReceiptFormat.visible(rows, expanded: false)
        #expect(collapsed.rows.count == 4)
        #expect(collapsed.hidden == 3)
        #expect(ReceiptFormat.visible(rows, expanded: true).rows.count == 7)
        #expect(ReceiptFormat.visible(rows, expanded: true).hidden == 0)
        #expect(ReceiptFormat.visible(Array(rows.prefix(4)), expanded: false).hidden == 0)
        #expect(ReceiptFormat.showAllTitle(total: 7) == "Show all (7)")
        #expect(ReceiptFormat.showLessTitle == "Show less")
    }

    @Test func detailWording() {
        func detail(_ line: ReceiptLine) -> String? { ReceiptFormat.detail(ReceiptFormat.rows([line])[0]) }
        let clock = PanelFormat.clock(noon.addingTimeInterval(7 * 60))
        #expect(detail(finished("A", "x", turns: 9, work: 112 * 60)) == "9 turns, 1 h 52 min of work, last \(clock)")
        #expect(detail(finished("A", "x", turns: 1, work: 5 * 60)) == "1 turn, 5 min of work, last \(clock)")
        #expect(detail(finished("A", "x", turns: 1, work: 20)) == "1 turn, under a minute, last \(clock)")
        #expect(detail(ReceiptLine(agent: "A", folder: nil, outcome: .stalled(since: noon))) == "stuck since \(PanelFormat.clock(noon))")
        #expect(detail(ReceiptLine(agent: "A", folder: nil, outcome: .stillWorking)) == "still working")
    }

    @Test func summaryCountsTurnsAndProjects() {
        let lines = [
            finished("Claude Code", "brain", turns: 10, work: 3_600),
            finished("Claude Code", "web", turns: 7, work: 3_600),
            finished("Claude Code", "mac", turns: 6, work: 3_600),
            ReceiptLine(agent: "Claude Code", folder: "web", outcome: .waitingForYou(since: noon), turns: 0, workSeconds: 0),
            ReceiptLine(agent: "Claude Code", folder: "old", outcome: .stalled(since: noon)),
            ReceiptLine(agent: "Codex", folder: nil, outcome: .stillWorking),
            ReceiptLine(agent: "Codex", folder: "gone", outcome: .ended(at: noon)),
        ]
        #expect(ReceiptFormat.summary(receipt(lines: lines, stop: .heat))
            == "23 turns done in 3 projects, 1 waiting for you, 1 still working, 1 stuck, 1 ended, safety stop")
        #expect(ReceiptFormat.summary(receipt(lines: [finished("A", "x", turns: 1, work: 60)])) == "1 turn done in 1 project")
    }

    @Test func legacyFinishedLineCountsAsOneTurnOfItsDuration() {
        let legacy = ReceiptLine(agent: "A", folder: "x", outcome: .finished(at: noon, afterSeconds: 900))
        #expect(ReceiptFormat.turns(legacy) == 1)
        #expect(ReceiptFormat.workSeconds(legacy) == 900)
        #expect(ReceiptFormat.summary(receipt(lines: [legacy])) == "1 turn done in 1 project")
    }

    @Test func receiptFileWithoutTheNewFieldsStillLoads() throws {
        let json = #"""
        {"agent":"Claude Code","folder":"api","outcome":{"finished":{"at":0,"afterSeconds":600}}}
        """#
        let line = try JSONDecoder().decode(ReceiptLine.self, from: Data(json.utf8))
        #expect(line.turns == 0)
        #expect(line.workSeconds == 0)
        #expect(line.agent == "Claude Code")
        #expect(line.folder == "api")
        let roundTrip = try JSONDecoder().decode(
            ReceiptLine.self,
            from: JSONEncoder().encode(ReceiptLine(agent: "A", folder: nil, outcome: .stillWorking, turns: 4, workSeconds: 90)))
        #expect(roundTrip == ReceiptLine(agent: "A", folder: nil, outcome: .stillWorking, turns: 4, workSeconds: 90))
    }

    @Test func notesListWhatWorthTelling() {
        let notes = ReceiptFormat.notes(receipt(stop: .battery, slept: 2, peak: 2, battery: (84, 61), plugged: false, notRunning: noon))
        #expect(notes.count == 5)
        #expect(notes[0] == "Battery 84% to 61%")
        #expect(notes[1] == "Peak heat: hot")
        #expect(notes[2] == "Mac slept 2 times")
        #expect(notes[3] == "Safety stop: the battery got low")
        #expect(notes[4].hasPrefix("MacBull was not running since"))
        #expect(ReceiptFormat.notes(receipt()).isEmpty)
    }

    @Test func pluggedInIsMentionedWithTheBattery() {
        #expect(ReceiptFormat.batteryLine(receipt(battery: (50, 90), plugged: true)) == "Battery 50% to 90%, plugged in")
        #expect(ReceiptFormat.batteryLine(receipt()) == nil)
    }

    @Test func sleepsAndHeatWording() {
        #expect(ReceiptFormat.sleptLine(0) == nil)
        #expect(ReceiptFormat.sleptLine(1) == "Mac slept once")
        #expect(ReceiptFormat.thermalName(0) == nil)
        #expect(ReceiptFormat.thermalName(1) == "warm")
        #expect(ReceiptFormat.thermalName(3) == "very hot")
    }
}

struct NutritionFormatTests {
    private func stats(finishedToday: Int = 0) -> NutritionStats {
        NutritionStats(
            cansOpened: 7, awakeSeconds: 5 * 3600 + 20 * 60, agentSeconds: 9.5 * 3600, longestRunSeconds: 95 * 60,
            sessionsFinished: 14, waitedForYouSeconds: 38 * 60, waitedForYouMedianSeconds: 4 * 60, batterySpentAway: 23,
            safetyStops: 1,
            agentMix: [AgentShare(agent: "Claude Code", share: 0.62), AgentShare(agent: "Codex", share: 0.3), AgentShare(agent: "Aider", share: 0.08)],
            emptiesToday: finishedToday)
    }

    @Test func rowsFollowTheLabel() {
        let rows = NutritionFormat.rows(stats())
        #expect(rows.map(\.label) == ["Cans opened", "Awake time", "Agent-hours", "Longest run", "Sessions finished",
                                      "Waited for you", "Battery spent away", "Safety stops"])
        #expect(rows.map(\.value) == ["7", "5 h 20 min", "9.5 h", "1 h 35 min", "14", "38 min", "23%", "1"])
        #expect(rows[5].note == "median 4 min")
    }

    @Test func agentHoursDropAPointlessDecimal() {
        #expect(NutritionFormat.agentHours(2 * 3600) == "2 h")
        #expect(NutritionFormat.agentHours(2.04 * 3600) == "2 h")
        #expect(NutritionFormat.agentHours(0) == "0 h")
    }

    @Test func ingredientsListTheMixThenLimeAndBubbles() {
        #expect(NutritionFormat.ingredients(stats().agentMix) == "Claude Code 62%, Codex 30%, Aider 8%, lime, bubbles")
        #expect(NutritionFormat.ingredients([]) == "lime, bubbles")
    }

    @Test func emptiesStopAtTwelveThenCount() {
        #expect(NutritionFormat.empties(0) == (drawn: 0, more: 0))
        #expect(NutritionFormat.empties(5) == (drawn: 5, more: 0))
        #expect(NutritionFormat.empties(12) == (drawn: 12, more: 0))
        #expect(NutritionFormat.empties(14) == (drawn: 12, more: 2))
        #expect(NutritionFormat.empties(-3) == (drawn: 0, more: 0))
    }

    @Test func emptyStatsAreEmpty() {
        #expect(NutritionFormat.isEmpty(.empty))
        #expect(!NutritionFormat.isEmpty(stats()))
    }

    @Test func plainTextCarriesTheRowsAndNoProjectNames() {
        let text = NutritionFormat.text(stats(finishedToday: 14), range: .week)
        #expect(text.contains("Nutrition Facts, this week"))
        #expect(text.contains("Cans opened: 7"))
        #expect(text.contains("Waited for you: 38 min (median 4 min)"))
        #expect(text.contains("Ingredients: Claude Code 62%, Codex 30%, Aider 8%, lime, bubbles"))
        #expect(text.contains("Empties today: 14"))
    }
}

@MainActor
struct StatusClickTests {
    @Test func plainLeftClickTogglesThePanel() {
        #expect(StatusClick.action(isRightButton: false, modifiers: [], clickToggles: false) == .togglePanel)
    }

    @Test func rightAndControlClickToggleThePanel() {
        #expect(StatusClick.action(isRightButton: true, modifiers: [], clickToggles: false) == .togglePanel)
        #expect(StatusClick.action(isRightButton: false, modifiers: .control, clickToggles: false) == .togglePanel)
    }

    @Test func optionClickIsAQuickToggleWithEitherButton() {
        #expect(StatusClick.action(isRightButton: false, modifiers: .option, clickToggles: false) == .quickToggle)
        #expect(StatusClick.action(isRightButton: true, modifiers: .option, clickToggles: false) == .quickToggle)
    }

    @Test func withTheClickShortcutOnLeftClickTogglesAwakeButRightAndControlStillOpenThePanel() {
        #expect(StatusClick.action(isRightButton: false, modifiers: [], clickToggles: true) == .quickToggle)
        #expect(StatusClick.action(isRightButton: true, modifiers: [], clickToggles: true) == .togglePanel)
        #expect(StatusClick.action(isRightButton: false, modifiers: .control, clickToggles: true) == .togglePanel)
        #expect(StatusClick.action(isRightButton: false, modifiers: .option, clickToggles: true) == .quickToggle)
    }
}

struct PanelPlacementTests {
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let size = CGSize(width: 340, height: 500)

    @Test func centredUnderTheItemSixPointsBelow() {
        let item = NSRect(x: 1000, y: 875, width: 24, height: 24)
        let origin = PanelPlacement.origin(anchor: item, size: size, visible: visible)
        #expect(origin.x == CGFloat(842))
        #expect(origin.y + size.height == CGFloat(869))
    }

    @Test func keptEightPointsInsideTheRightEdge() {
        let item = NSRect(x: 1430, y: 875, width: 24, height: 24)
        let origin = PanelPlacement.origin(anchor: item, size: size, visible: visible)
        #expect(origin.x + size.width == CGFloat(1432))
    }

    @Test func keptEightPointsInsideTheLeftEdge() {
        let item = NSRect(x: 2, y: 875, width: 24, height: 24)
        #expect(PanelPlacement.origin(anchor: item, size: size, visible: visible).x == CGFloat(8))
    }

    @Test func tallestPanelLeavesAMarginAtTheBottom() {
        #expect(PanelPlacement.maxHeight(top: 869, visible: visible) == CGFloat(861))
    }
}
