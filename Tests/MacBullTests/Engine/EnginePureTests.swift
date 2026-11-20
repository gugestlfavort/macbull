import Foundation
import Testing
@testable import MacBull

struct EngineURLCommandTests {
    @Test(arguments: [
        ("macbull://on", URLCommand.on(minutes: nil)),
        ("macbull://on?minutes=30", .on(minutes: 30)),
        ("macbull://on?minutes=1", .on(minutes: 1)),
        ("macbull://on?minutes=10080", .on(minutes: 10_080)),
        ("macbull://on?minutes=10081", .on(minutes: 0)),
        ("macbull://on?minutes=0", .on(minutes: 0)),
        ("macbull://on?minutes=-5", .on(minutes: 0)),
        ("macbull://on?minutes=abc", .on(minutes: nil)),
        ("macbull://on?minutes=", .on(minutes: nil)),
        ("macbull://on?minutes=2.5", .on(minutes: nil)),
        ("macbull://off", .off),
        ("macbull://toggle", .toggle),
        ("macbull://panel", .panel),
        ("MACBULL://Toggle", .toggle),
        ("macbull:toggle", .toggle),
    ])
    func parsesCommands(raw: String, expected: URLCommand) throws {
        let url = try #require(URL(string: raw))
        #expect(URLCommand.parse(url) == expected)
    }

    @Test(arguments: [
        ("macbull://settings", SettingsTab.general),
        ("macbull://settings?tab=lid", .lid),
        ("macbull://settings?tab=agents", .agents),
        ("macbull://settings?tab=safety", .safety),
        ("macbull://settings?tab=away", .away),
        ("macbull://settings?tab=about", .about),
        ("macbull://settings?tab=nonsense", .general),
        ("macbull://settings?tab=", .general),
    ])
    func parsesSettingsTabs(raw: String, expected: SettingsTab) throws {
        let url = try #require(URL(string: raw))
        #expect(URLCommand.parse(url) == .settings(expected))
    }

    @Test(arguments: [
        ("macbull://welcome", WelcomeStep.hello),
        ("macbull://welcome?step=login", .login),
        ("macbull://welcome?step=lid", .lid),
        ("macbull://welcome?step=agents", .agents),
        ("macbull://welcome?step=done", .done),
        ("macbull://welcome?step=nope", .hello),
    ])
    func parsesWelcomeSteps(raw: String, expected: WelcomeStep) throws {
        let url = try #require(URL(string: raw))
        #expect(URLCommand.parse(url) == .welcome(expected))
    }

    @Test(arguments: ["macbull://frobnicate", "https://on", "other://on", "macbull://"])
    func ignoresUnknown(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(URLCommand.parse(url) == nil)
    }
}

struct EngineStatusLineTests {
    private let now = EngineRigClock.start

    private func line(
        manual: ManualSession? = nil, hold: Bool = false, agents: [String] = [],
        cutoff: SafetyStop? = nil, paused: Bool = false
    ) -> String {
        StatusLine.text(manual: manual, agentHold: hold, workingAgents: agents, cutoff: cutoff, paused: paused, now: now)
    }

    private func timed(seconds: TimeInterval) -> ManualSession {
        ManualSession(minutes: 60, startedAt: now, endsAt: now.addingTimeInterval(seconds))
    }

    @Test func untimedManual() {
        #expect(line(manual: ManualSession(minutes: 0, startedAt: now, endsAt: nil)) == "Awake until you turn it off")
    }

    @Test(arguments: [
        (1, "1 min"), (59, "1 min"), (60, "1 min"), (61, "2 min"), (1_500, "25 min"),
        (3_540, "59 min"), (3_600, "1 h"), (3_601, "1 h 1 min"), (5_400, "1 h 30 min"), (7_200, "2 h"),
    ] as [(Int, String)])
    func timedManualRoundsUp(seconds: Int, text: String) {
        #expect(line(manual: timed(seconds: TimeInterval(seconds))) == "Awake for \(text) more")
    }

    @Test func pastEndShowsOneMinute() {
        #expect(line(manual: timed(seconds: -30)) == "Awake for 1 min more")
    }

    @Test func manualBeatsAgentHold() {
        #expect(line(manual: timed(seconds: 600), hold: true, agents: ["Codex"]) == "Awake for 10 min more")
    }

    @Test func agentHoldNamesWorkingAgents() {
        #expect(line(hold: true, agents: ["Claude Code"]) == "Awake while Claude Code works")
        #expect(line(hold: true, agents: ["Claude Code", "Codex"]) == "Awake while Claude Code and Codex work")
        #expect(line(hold: true, agents: ["Claude Code", "Codex", "Aider"]) == "Awake while Claude Code, Codex and Aider work")
        #expect(line(hold: true) == "Awake while agents finish up")
    }

    @Test func notAwakeLines() {
        #expect(line(cutoff: .heat) == "Turned off because the Mac got too warm")
        #expect(line(cutoff: .battery) == "Turned off because the battery is low")
        #expect(line(cutoff: .heat, paused: true) == "Turned off because the Mac got too warm")
        #expect(line(paused: true) == "Off until your agents finish")
        #expect(line() == "Off, the Mac sleeps as usual")
    }
}

/// Same fixed instant as the rig clock, without needing the main actor.
enum EngineRigClock {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
}

struct EngineSafetyRulesTests {
    private func input(
        battery: Bool = true, threshold: Int = 20, heat: Bool = true, onBattery: Bool = true, percent: Int? = 50,
        thermal: ProcessInfo.ThermalState = .nominal, lidPossible: Bool = false, bag: Bool = false
    ) -> SafetyInput {
        SafetyInput(
            batteryGuard: battery, batteryThresholdPercent: threshold, heatGuard: heat, onBattery: onBattery,
            batteryPercent: percent, thermal: thermal, lidHoldPossible: lidPossible, closedInBag: bag
        )
    }

    @Test func batteryAtOrBelowThresholdOnBattery() {
        #expect(SafetyRules.stop(for: input(percent: 20)) == .battery)
        #expect(SafetyRules.stop(for: input(percent: 19)) == .battery)
        #expect(SafetyRules.stop(for: input(percent: 21)) == nil)
    }

    @Test func pluggedInNeverTriggersBattery() {
        #expect(SafetyRules.stop(for: input(onBattery: false, percent: 5)) == nil)
    }

    @Test func noBatteryReadingNeverTriggers() {
        #expect(SafetyRules.stop(for: input(percent: nil)) == nil)
    }

    @Test func guardsOffNeverTrigger() {
        #expect(SafetyRules.stop(for: input(battery: false, percent: 1)) == nil)
        #expect(SafetyRules.stop(for: input(heat: false, thermal: .critical)) == nil)
    }

    @Test func seriousAndCriticalAlwaysTriggerHeat() {
        #expect(SafetyRules.stop(for: input(thermal: .serious)) == .heat)
        #expect(SafetyRules.stop(for: input(thermal: .critical)) == .heat)
    }

    @Test func fairTriggersOnlyWhenHeldAndBagged() {
        #expect(SafetyRules.stop(for: input(thermal: .fair)) == nil)
        #expect(SafetyRules.stop(for: input(thermal: .fair, lidPossible: true, bag: false)) == nil)
        #expect(SafetyRules.stop(for: input(thermal: .fair, lidPossible: false, bag: true)) == nil)
        #expect(SafetyRules.stop(for: input(thermal: .fair, lidPossible: true, bag: true)) == .heat)
    }

    @Test func heatIsCheckedBeforeBattery() {
        #expect(SafetyRules.stop(for: input(percent: 5, thermal: .serious)) == .heat)
    }

    @Test func noteGoesWhenItsReasonIsGone() {
        #expect(SafetyRules.noteStillApplies(.battery, input(percent: 10)))
        #expect(!SafetyRules.noteStillApplies(.battery, input(percent: 40)))
        #expect(!SafetyRules.noteStillApplies(.battery, input(onBattery: false, percent: 10)))
        #expect(!SafetyRules.noteStillApplies(.battery, input(battery: false, percent: 10)))
        #expect(SafetyRules.noteStillApplies(.heat, input(thermal: .fair)))
        #expect(!SafetyRules.noteStillApplies(.heat, input(thermal: .nominal)))
    }
}

struct EnginePowerPlanTests {
    private func facts(
        awake: Bool = true, manual: Bool = true, display: Bool = true, ready: Bool = true, lid: Bool = true,
        lowPower: Bool = true, bag: Bool = false, battery: Bool = false, quitting: Bool = false
    ) -> PowerPlan.Facts {
        PowerPlan.Facts(
            isAwake: awake, manualActive: manual, keepDisplayOn: display, lidReady: ready, lidSetting: lid,
            lowPowerSetting: lowPower, closedInBag: bag, onBattery: battery, quitting: quitting
        )
    }

    @Test func manualHoldsSystemAndDisplay() {
        let plan = PowerPlan.make(facts())
        #expect(plan.preventSystemSleep)
        #expect(plan.preventDisplaySleep)
        #expect(plan.lidHoldWanted)
    }

    @Test func notAwakeHoldsNothing() {
        let plan = PowerPlan.make(facts(awake: false, manual: false))
        #expect(!plan.preventSystemSleep)
        #expect(!plan.preventDisplaySleep)
        #expect(!plan.lidHoldWanted)
    }

    @Test func agentHoldNeverKeepsDisplayLit() {
        let plan = PowerPlan.make(facts(manual: false))
        #expect(plan.preventSystemSleep)
        #expect(!plan.preventDisplaySleep)
    }

    @Test func displaySettingOffReleasesDisplay() {
        #expect(!PowerPlan.make(facts(display: false)).preventDisplaySleep)
    }

    @Test func baggedWithLidModeKeepsSystemButNotDisplay() {
        let plan = PowerPlan.make(facts(bag: true))
        #expect(plan.preventSystemSleep)
        #expect(!plan.preventDisplaySleep)
        #expect(plan.lidHoldWanted)
    }

    @Test func baggedWithoutPermissionOrSettingLetsMacSleep() {
        #expect(!PowerPlan.make(facts(ready: false, bag: true)).preventSystemSleep)
        #expect(!PowerPlan.make(facts(lid: false, bag: true)).preventSystemSleep)
    }

    @Test func lidNotAllowedButOpenStillHoldsSystem() {
        let plan = PowerPlan.make(facts(ready: false, bag: false))
        #expect(plan.preventSystemSleep)
        #expect(!plan.lidHoldWanted)
    }

    @Test func lidHoldNotWantedWhileQuitting() {
        #expect(!PowerPlan.make(facts(quitting: true)).lidHoldWanted)
    }

    @Test func lowPowerOnlyWhenHeldBaggedOnBatteryAndSettingOn() {
        #expect(PowerPlan.make(facts(bag: true, battery: true)).lowPowerWanted)
        #expect(!PowerPlan.make(facts(bag: false, battery: true)).lowPowerWanted)
        #expect(!PowerPlan.make(facts(bag: true, battery: false)).lowPowerWanted)
        #expect(!PowerPlan.make(facts(lowPower: false, bag: true, battery: true)).lowPowerWanted)
        #expect(!PowerPlan.make(facts(ready: false, bag: true, battery: true)).lowPowerWanted)
    }
}

struct EngineQuietHoursTests {
    @Test(arguments: [
        (22, 22, 7, true), (23, 22, 7, true), (0, 22, 7, true), (6, 22, 7, true),
        (7, 22, 7, false), (12, 22, 7, false), (21, 22, 7, false),
        (1, 1, 5, true), (4, 1, 5, true), (5, 1, 5, false), (0, 1, 5, false),
        (3, 8, 8, false), (0, 0, 0, false),
    ] as [(Int, Int, Int, Bool)])
    func containsHour(hour: Int, start: Int, end: Int, expected: Bool) {
        #expect(QuietHours.contains(hour: hour, start: start, end: end) == expected)
    }
}

struct EngineNotificationThrottleTests {
    @Test func allowsOncePerKindPerWindow() {
        var throttle = NotificationThrottle()
        let start = EngineRigClock.start
        let first = throttle.allow(.heat, at: start)
        let second = throttle.allow(.heat, at: start.addingTimeInterval(299))
        let otherKind = throttle.allow(.battery, at: start.addingTimeInterval(1))
        let afterWindow = throttle.allow(.heat, at: start.addingTimeInterval(300))
        #expect(first)
        #expect(!second)
        #expect(otherKind)
        #expect(afterWindow)
    }

    @Test func blockedAttemptDoesNotExtendTheWindow() {
        var throttle = NotificationThrottle()
        let start = EngineRigClock.start
        let first = throttle.allow(.agentsDone, at: start)
        let blocked = throttle.allow(.agentsDone, at: start.addingTimeInterval(200))
        let later = throttle.allow(.agentsDone, at: start.addingTimeInterval(301))
        #expect(first)
        #expect(!blocked)
        #expect(later)
    }
}

struct EngineReceiptSummaryTests {
    private func receipt(awaySeconds: TimeInterval, lines: [ReceiptLine] = [], start: Int? = nil, end: Int? = nil,
                         stop: SafetyStop? = nil, notRunning: Date? = nil) -> Receipt {
        let from = EngineRigClock.start
        return Receipt(
            id: UUID(), awayFrom: from, awayTo: from.addingTimeInterval(awaySeconds), lines: lines, batteryStart: start,
            batteryEnd: end, pluggedIn: false, peakThermal: 0, sleptAt: [], safetyStop: stop, notRunningSince: notRunning
        )
    }

    private func line(_ outcome: ReceiptOutcome) -> ReceiptLine {
        ReceiptLine(agent: "Claude Code", folder: "api", outcome: outcome)
    }

    @Test func fullExample() {
        let now = EngineRigClock.start
        let lines = [
            line(.finished(at: now, afterSeconds: 600)), line(.finished(at: now, afterSeconds: 60)),
            line(.waitingForYou(since: now)),
        ]
        let text = ReceiptSummary.text(receipt(awaySeconds: 7 * 3_600 + 12 * 60, lines: lines, start: 84, end: 61))
        #expect(text == "Away 7 h 12 min: 2 turns done in 1 project, 1 waiting for you, battery 84% to 61%")
    }

    @Test func countsTurnsAndDistinctProjects() {
        let now = EngineRigClock.start
        let lines = [
            ReceiptLine(agent: "Claude Code", folder: "brain", outcome: .finished(at: now, afterSeconds: 60), turns: 9, workSeconds: 3_600),
            ReceiptLine(agent: "Claude Code", folder: "brain", outcome: .finished(at: now, afterSeconds: 60), turns: 4, workSeconds: 600),
            ReceiptLine(agent: "Claude Code", folder: "web", outcome: .waitingForYou(since: now), turns: 10, workSeconds: 900),
        ]
        let text = ReceiptSummary.text(receipt(awaySeconds: 3_600, lines: lines))
        #expect(text == "Away 1 h: 23 turns done in 2 projects, 1 waiting for you")
    }

    @Test func minutesOnlyAndOtherOutcomes() {
        let now = EngineRigClock.start
        let lines = [line(.stillWorking), line(.stalled(since: now)), line(.ended(at: now))]
        let text = ReceiptSummary.text(receipt(awaySeconds: 25 * 60, lines: lines))
        #expect(text == "Away 25 min: 1 still working, 1 stuck, 1 ended")
    }

    @Test func safetyStopCrashAndFlatBattery() {
        let text = ReceiptSummary.text(receipt(awaySeconds: 3_600, start: 50, end: 50, stop: .battery, notRunning: EngineRigClock.start))
        #expect(text == "Away 1 h: stopped because the battery got low, MacBull was not running for part of it, battery 50%")
    }

    @Test func nothingToSayKeepsTheHead() {
        #expect(ReceiptSummary.text(receipt(awaySeconds: 1_800)) == "Away 30 min")
    }
}
