import Foundation
import Testing
@testable import MacBull

struct WelcomeFlowTests {
    @Test func withALidAllFiveStepsInOrder() {
        let flow = WelcomeFlow(start: .hello, hasLid: true)
        #expect(flow.steps == [.hello, .login, .lid, .agents, .done])
        #expect(flow.progressLabel == "Step 1 of 5")
        #expect(flow.isFirst)
    }

    @Test func withoutALidTheLidStepIsDroppedAndCountedOut() {
        var flow = WelcomeFlow(start: .hello, hasLid: false)
        #expect(flow.steps == [.hello, .login, .agents, .done])
        flow.next()
        flow.next()
        #expect(flow.current == .agents)
        #expect(flow.progressLabel == "Step 3 of 4")
    }

    @Test func askingForTheLidStepWithoutALidStartsAtAgents() {
        #expect(WelcomeFlow(start: .lid, hasLid: false).current == .agents)
        #expect(WelcomeFlow(start: .lid, hasLid: true).current == .lid)
    }

    @Test func backAndNextStopAtTheEnds() {
        var flow = WelcomeFlow(start: .hello, hasLid: true)
        flow.back()
        #expect(flow.current == .hello)
        for _ in 0..<10 { flow.next() }
        #expect(flow.current == .done)
        #expect(flow.isLast)
        flow.back()
        #expect(flow.current == .agents)
    }

    @Test func agentsLineCoversOffNoneAndRunning() {
        func summary(_ name: String, sessions: Int) -> AgentSummary {
            AgentSummary(name: name, sessions: sessions, isWorking: true, backgroundRuns: 0, isCustom: false, waitingForYou: 0, stalled: 0)
        }
        #expect(WelcomeAgentsLine.text(agentMode: false, agents: []).hasPrefix("Off"))
        #expect(WelcomeAgentsLine.text(agentMode: true, agents: []).hasPrefix("None"))
        let line = WelcomeAgentsLine.text(agentMode: true, agents: [summary("Claude Code", sessions: 2), summary("Codex", sessions: 1)])
        #expect(line == "Right now: Claude Code (2 open), Codex")
    }
}

struct SettingsOptionsTests {
    @Test func durationLabelsRead() {
        #expect(SettingsOptions.durations.map(\.label) == [
            "15 minutes", "30 minutes", "1 hour", "2 hours", "3 hours", "5 hours", "8 hours", "Until turned off",
        ])
        #expect(SettingsOptions.durations.map(\.value) == [15, 30, 60, 120, 180, 300, 480, 0])
    }

    @Test func choicesMatchTheSpec() {
        #expect(SettingsOptions.graceMinutes.map(\.value) == [1, 2, 3, 5, 10])
        #expect(SettingsOptions.batteryPercents.map(\.value) == [10, 15, 20, 30, 50])
        #expect(SettingsOptions.remindAfter.map(\.value) == [0, 2, 5, 15])
        #expect(SettingsOptions.minimumAway.map(\.value) == [10, 20, 30, 60])
        #expect(SettingsOptions.historyDays.map(\.value) == [7, 30, 90])
        #expect(SettingsOptions.hours.count == 24)
        #expect(SettingsOptions.hourLabel(7) == "07:00")
    }

    @Test func aStoredValueOutsideTheChoicesIsAdded() {
        let choices = SettingsOptions.including(45, in: SettingsOptions.durations) { "\($0) minutes" }
        #expect(choices.last?.value == 45)
        #expect(SettingsOptions.including(60, in: SettingsOptions.durations) { "\($0)" } == SettingsOptions.durations)
    }

    @Test func versionComesFromTheBundleOrSaysDev() {
        #expect(AppVersion.label(infoDictionary: ["CFBundleShortVersionString": "0.1.0"]) == "0.1.0")
        #expect(AppVersion.label(infoDictionary: [:]) == "dev")
        #expect(AppVersion.label(infoDictionary: nil) == "dev")
        #expect(AppVersion.label(infoDictionary: ["CFBundleShortVersionString": ""]) == "dev")
    }

    @Test func automationExamplesIncludeTheAwayTab() {
        #expect(AutomationExamples.urls.contains("macbull://settings?tab=away"))
        #expect(AutomationExamples.urls.allSatisfy { $0.hasPrefix("macbull://") })
    }

    @Test func loginItemOnMeansEnabledOrWaitingForApproval() {
        #expect(LoginItemCopy.isOn(.enabled))
        #expect(LoginItemCopy.isOn(.needsApproval))
        #expect(!LoginItemCopy.isOn(.disabled))
        #expect(!LoginItemCopy.isOn(.failed("x")))
        #expect(LoginItemCopy.loginItemsSettingsURL == "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }
}

struct AwayFormatTests {
    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    private func receipt(lines: [ReceiptLine] = [], from: TimeInterval = 7 * 3600 + 12 * 60) -> Receipt {
        Receipt(
            id: UUID(), awayFrom: noon, awayTo: noon.addingTimeInterval(from), lines: lines,
            batteryStart: 84, batteryEnd: 61, pluggedIn: false, peakThermal: 0, sleptAt: [],
            safetyStop: nil, notRunningSince: nil
        )
    }

    @Test func durationsRead() {
        #expect(AwayFormat.duration(20) == "under a minute")
        #expect(AwayFormat.duration(45 * 60) == "45 min")
        #expect(AwayFormat.duration(3600) == "1 h")
        #expect(AwayFormat.duration(7 * 3600 + 12 * 60) == "7 h 12 min")
    }

    @Test func summaryCountsOutcomesAndShowsBattery() {
        let lines = [
            ReceiptLine(agent: "Claude Code", folder: "api", outcome: .finished(at: noon, afterSeconds: 600)),
            ReceiptLine(agent: "Codex", folder: nil, outcome: .finished(at: noon, afterSeconds: 60)),
            ReceiptLine(agent: "Aider", folder: "web", outcome: .waitingForYou(since: noon)),
        ]
        #expect(AwayFormat.summary(receipt(lines: lines)) == "2 finished, 1 waiting for you, battery 84% to 61%")
        #expect(AwayFormat.title(receipt()) == "Away 7 h 12 min")
    }

    @Test func summaryNamesSafetyStopAndMissingRun() {
        var stopped = receipt()
        stopped.safetyStop = .heat
        stopped.notRunningSince = noon
        stopped.batteryEnd = 84
        let text = AwayFormat.summary(stopped)
        #expect(text.contains("stopped: too warm"))
        #expect(text.contains("not running"))
        #expect(!text.contains("battery"))
    }
}

struct AgentStatusWordTests {
    private func agent(working: Bool = false, runs: Int = 0, custom: Bool = false, waiting: Int = 0, stalled: Int = 0) -> AgentSummary {
        AgentSummary(name: "X", sessions: 1, isWorking: working, backgroundRuns: runs, isCustom: custom, waitingForYou: waiting, stalled: stalled)
    }

    @Test func wordsFollowTheSpec() {
        #expect(AgentStatusWord.text(for: agent(custom: true)) == "Running")
        #expect(AgentStatusWord.text(for: agent(working: true, runs: 1)) == "Background run")
        #expect(AgentStatusWord.text(for: agent(working: true)) == "Working")
        #expect(AgentStatusWord.text(for: agent()) == "Idle")
        #expect(AgentStatusWord.text(for: agent(waiting: 1)) == "Idle, waiting for you")
        #expect(AgentStatusWord.text(for: agent(working: true, stalled: 1)) == "Working, stuck")
    }
}

@MainActor
struct LidSetupRunnerTests {
    @Test func cancelledShowsNoError() async {
        let runner = LidSetupRunner(spinnerLead: .milliseconds(1))
        let result = await runner.run { .cancelled }
        #expect(result == .cancelled)
        #expect(runner.errorText == nil)
        #expect(!runner.isWorking)
    }

    @Test func failureShowsTheMessage() async {
        let runner = LidSetupRunner(spinnerLead: .milliseconds(1))
        await runner.run { .failed("macOS did not accept the change") }
        #expect(runner.errorText == "macOS did not accept the change")
    }

    @Test func successClearsAnEarlierError() async {
        let runner = LidSetupRunner(spinnerLead: .milliseconds(1))
        await runner.run { .failed("nope") }
        await runner.run { .success }
        #expect(runner.errorText == nil)
    }

    @Test func spinnerIsOnBeforeTheOperationRuns() async {
        let runner = LidSetupRunner(spinnerLead: .milliseconds(1))
        var wasWorking = false
        await runner.run {
            wasWorking = runner.isWorking
            return .success
        }
        #expect(wasWorking)
    }
}
