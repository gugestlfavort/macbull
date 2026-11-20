import Foundation
import Testing
@testable import MacBull

@MainActor
struct EngineManualTests {
    @Test func turnOnWithoutMinutesUsesTheDefault() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: nil)
        #expect(rig.state.manual == ManualSession(minutes: 0, startedAt: rig.clock.date, endsAt: nil))
        rig.settings.defaultMinutes = 60
        rig.model.turnOn(minutes: nil)
        #expect(rig.state.manual?.minutes == 60)
        #expect(rig.state.manual?.endsAt == rig.clock.date.addingTimeInterval(3_600))
    }

    @Test func turnOnForMinutesSetsEndTime() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: 30)
        #expect(rig.state.manual?.minutes == 30)
        #expect(rig.state.manual?.endsAt == rig.clock.date.addingTimeInterval(1_800))
        #expect(rig.state.isAwake)
        #expect(rig.state.menuIconBase == .on)
    }

    @Test func turnOnWhileOnReplacesTheSession() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: 30)
        let firstTimer = rig.scheduler.oneShots.first
        rig.advance(minutes: 10)
        rig.model.turnOn(minutes: 120)
        #expect(rig.state.manual?.minutes == 120)
        #expect(rig.state.manual?.endsAt == rig.clock.date.addingTimeInterval(7_200))
        #expect(firstTimer?.cancelled == true)
        #expect(rig.scheduler.oneShots.count == 1)
    }

    @Test func turnOnClearsTheCutoffNote() {
        let rig = EngineRig()
        rig.state.cutoff = .heat
        rig.model.turnOn(minutes: nil)
        #expect(rig.state.cutoff == nil)
    }

    @Test func turnOffReleasesEverything() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: nil)
        rig.model.turnOff()
        #expect(rig.state.manual == nil)
        #expect(!rig.state.isAwake)
        #expect(rig.power.last?.system == false)
        #expect(rig.power.last?.display == false)
        #expect(rig.lid.last?.holdWanted == false)
        #expect(rig.journal.kinds.contains(.awakeEnded(reason: "user")))
    }

    @Test func toggleFollowsAwakeState() {
        let rig = EngineRig()
        rig.model.toggle()
        #expect(rig.state.manual != nil)
        rig.model.toggle()
        #expect(rig.state.manual == nil)
    }

    @Test func toggleTurnsOffAnAgentHoldAndPauses() {
        let rig = EngineRig()
        rig.scan([rig.session()])
        #expect(rig.state.agentHold)
        rig.model.toggle()
        #expect(!rig.state.agentHold)
        #expect(rig.state.paused)
    }

    @Test func turnOnAtLaunchWhenSet() {
        let rig = EngineRig(started: false) { $0.startOnLaunch = true; $0.defaultMinutes = 15 }
        rig.model.start()
        #expect(rig.state.manual?.minutes == 15)
    }

    @Test func sleepNowTurnsEverythingOffThenSleeps() {
        let rig = EngineRig()
        rig.scan([rig.session()])
        rig.model.turnOn(minutes: nil)
        rig.model.sleepNow()
        #expect(!rig.state.isAwake)
        #expect(rig.state.paused)
        #expect(rig.lid.events.last == "sleepNow")
        #expect(rig.journal.kinds.contains(.awakeEnded(reason: "sleepNow")))
    }

    @Test func settingsChangeReevaluatesAtOnce() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: nil)
        #expect(rig.power.last?.display == true)
        rig.settings.keepDisplayOn = false
        #expect(rig.power.last?.display == false)
    }
}

@MainActor
struct EngineTimerTests {
    @Test func timerEndsTheSessionWithoutANotification() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: 1)
        #expect(rig.scheduler.oneShots.count == 1)
        #expect(rig.scheduler.oneShots.first?.interval == 60)
        rig.advance(minutes: 1)
        rig.scheduler.fireOneShots()
        #expect(rig.state.manual == nil)
        #expect(rig.notifier.posted.isEmpty)
        #expect(rig.state.cutoff == nil)
        #expect(rig.journal.kinds.contains(.awakeEnded(reason: "timer")))
    }

    @Test func lateTimerIsCaughtByTheFiveSecondTick() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: 1)
        rig.tick(afterMinutes: 0.5)
        #expect(rig.state.manual != nil)
        rig.tick(afterMinutes: 10)
        #expect(rig.state.manual == nil)
    }

    @Test func tickRunsEveryFiveSecondsWhileAwakeAndEveryThirtyWhenIdle() {
        let rig = EngineRig()
        #expect(rig.scheduler.ticks.count == 1)
        #expect(rig.scheduler.ticks.first?.interval == 30, "off, not away, nobody waiting")
        rig.model.turnOn(minutes: nil)
        #expect(rig.scheduler.ticks.count == 1)
        #expect(rig.scheduler.ticks.first?.interval == 5)
        rig.model.turnOff()
        #expect(rig.scheduler.ticks.count == 1)
        #expect(rig.scheduler.ticks.first?.interval == 30)
    }

    @Test func wakeCatchesAnExpiredEndTime() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: 5)
        rig.advance(minutes: 120)
        rig.system.send(.didWake)
        #expect(rig.state.manual == nil)
        #expect(rig.journal.kinds.contains(.macWoke))
    }

    @Test func notExpiredStaysOnAtWake() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: 60)
        rig.advance(minutes: 5)
        rig.system.send(.didWake)
        #expect(rig.state.manual != nil)
    }

    @Test func agentHoldTakesOverWithoutAGap() {
        let rig = EngineRig()
        rig.scan([rig.session()])
        rig.model.turnOn(minutes: 1)
        let callsBefore = rig.power.calls.count
        rig.advance(minutes: 1)
        rig.scheduler.fireOneShots()
        #expect(rig.state.manual == nil)
        #expect(rig.state.agentHold)
        #expect(rig.power.last?.system == true)
        #expect(rig.power.last?.display == false)
        let gaps = rig.power.calls.dropFirst(callsBefore).filter { !$0.system }
        #expect(gaps.isEmpty)
        let endings = rig.journal.kinds.filter { if case .awakeEnded = $0 { true } else { false } }
        #expect(endings.isEmpty)
    }

    @Test func sleepingThroughTheEndDoesNotNotify() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: 30)
        rig.system.send(.willSleep)
        rig.advance(minutes: 600)
        rig.system.send(.didWake)
        #expect(rig.notifier.posted.isEmpty)
        #expect(rig.journal.kinds.contains(.macSlept))
    }
}

@MainActor
struct EngineAgentHoldTests {
    @Test func holdStartsWhenAnAgentWorks() {
        let rig = EngineRig()
        rig.scan([rig.session()])
        #expect(rig.state.agentHold)
        #expect(rig.state.agentHoldSince == rig.clock.date)
        #expect(rig.state.menuIconBase == .agents)
        #expect(rig.power.last?.system == true)
        #expect(rig.power.last?.display == false)
        #expect(rig.lid.last?.holdWanted == true)
        #expect(rig.journal.kinds.contains(.awakeStarted(reason: "agents")))
    }

    @Test func idleAgentsDoNotHold() {
        let rig = EngineRig()
        rig.scan([rig.session(.idle)])
        #expect(!rig.state.agentHold)
        #expect(!rig.state.isAwake)
    }

    @Test func graceKeepsTheHoldUntilQuietLongEnough() {
        let rig = EngineRig()
        rig.scan([rig.session()])
        rig.advance(minutes: 0.2)
        rig.scan([rig.session(.idle)])
        #expect(rig.state.agentHold)
        rig.tick(afterMinutes: 2.7)
        #expect(rig.state.agentHold)
        rig.tick(afterMinutes: 0.2)
        #expect(!rig.state.agentHold)
        #expect(rig.state.agentHoldSince == nil)
        #expect(!rig.state.paused)
        #expect(rig.journal.kinds.contains(.awakeEnded(reason: "agentsDone")))
    }

    @Test func workingAgainResetsTheGraceClock() {
        let rig = EngineRig()
        rig.scan([rig.session()])
        rig.advance(minutes: 2.5)
        rig.scan([rig.session()])
        rig.advance(minutes: 2.5)
        rig.scan([rig.session(.idle)])
        #expect(rig.state.agentHold)
        rig.tick(afterMinutes: 0.4)
        #expect(rig.state.agentHold)
        rig.tick(afterMinutes: 0.2)
        #expect(!rig.state.agentHold)
    }

    @Test(arguments: [(0, 60.0), (1, 60.0), (2, 120.0), (10, 600.0)] as [(Int, Double)])
    func graceOptionsBelowOneCountAsOne(minutes: Int, seconds: Double) {
        let rig = EngineRig { $0.graceMinutes = minutes }
        rig.scan([rig.session()])
        rig.scan([rig.session(.idle)])
        rig.clock.advance(seconds - 1)
        rig.scheduler.fireTicks()
        #expect(rig.state.agentHold)
        rig.clock.advance(1)
        rig.scheduler.fireTicks()
        #expect(!rig.state.agentHold)
    }

    @Test func turningOffPausesUntilAgentsAreQuietForTheGrace() {
        let rig = EngineRig()
        rig.scan([rig.session()])
        rig.model.turnOff()
        #expect(rig.state.paused)
        #expect(!rig.state.agentHold)
        rig.advance(minutes: 1)
        rig.scan([rig.session()])
        #expect(!rig.state.agentHold)
        rig.advance(minutes: 1)
        rig.scan([rig.session(.idle)])
        #expect(rig.state.paused)
        rig.tick(afterMinutes: 1.9)
        #expect(rig.state.paused)
        rig.tick(afterMinutes: 0.2)
        #expect(!rig.state.paused)
        rig.scan([rig.session()])
        #expect(rig.state.agentHold)
    }

    @Test func pausedAgentsWorkingDoNotHoldTheMac() {
        let rig = EngineRig()
        rig.scan([rig.session()])
        rig.model.turnOff()
        rig.scan([rig.session()])
        #expect(!rig.state.isAwake)
        #expect(rig.power.last?.system == false)
    }

    @Test func agentModeOffClearsListHoldAndPause() {
        let rig = EngineRig()
        rig.scan([rig.session()], toolEvents: 2)
        rig.model.turnOff()
        rig.settings.agentMode = false
        #expect(rig.state.agents.isEmpty)
        #expect(rig.state.sessions.isEmpty)
        #expect(!rig.state.agentHold)
        #expect(!rig.state.paused)
        #expect(rig.agents.configured.last?.enabled == false)
    }

    @Test func agentModeOffEndsAHoldWithoutNotifying() {
        let rig = EngineRig()
        rig.scan([rig.session()])
        rig.advance(minutes: 5)
        rig.settings.agentMode = false
        #expect(!rig.state.isAwake)
        #expect(rig.notifier.posted.isEmpty)
    }

    @Test func scanResultsAfterAgentModeOffAreThrownAway() {
        let rig = EngineRig { $0.agentMode = false }
        rig.scan([rig.session()])
        #expect(rig.state.agents.isEmpty)
        #expect(!rig.state.agentHold)
    }

    @Test func configuresTheWatcherFromSettings() {
        let rig = EngineRig { $0.customAgents = ["my_agent"]; $0.claudeHooks = true; $0.stallWatchdog = false }
        let last = rig.agents.configured.last
        #expect(last?.enabled == true)
        #expect(last?.custom == ["my_agent"])
        #expect(last?.hooks == true)
        #expect(last?.stall == false)
    }

    @Test func hooksErrorSetByConfiguringIsInStateAtOnce() {
        let rig = EngineRig()
        #expect(rig.state.hooksError == nil)
        rig.agents.hooksErrorAfterConfigure = .some("settings.json is not valid JSON")
        rig.settings.claudeHooks = true
        #expect(rig.state.hooksError == "settings.json is not valid JSON")
        rig.agents.hooksErrorAfterConfigure = .some(nil)
        rig.settings.claudeHooks = false
        #expect(rig.state.hooksError == nil)
    }

    @Test func scansAccumulateStateAndToolPulses() {
        let rig = EngineRig()
        rig.agents.hooksError = "settings.json is not valid JSON"
        rig.scan([rig.session(id: "a"), rig.session(id: "b", agent: "Codex")], toolEvents: 3)
        rig.scan([rig.session(id: "a")], toolEvents: 2)
        #expect(rig.state.toolPulses == 5)
        #expect(rig.state.sessions.map(\.id) == ["a"])
        #expect(rig.state.hooksError == "settings.json is not valid JSON")
    }

    @Test func journalRecordsActivityChangesOnly() {
        let rig = EngineRig()
        rig.scan([rig.session(.working)])
        rig.scan([rig.session(.working)])
        rig.scan([rig.session(.waitingForYou)])
        rig.scan([])
        let changes = rig.journal.kinds.compactMap { kind -> SessionActivity? in
            if case .sessionChanged(_, _, _, let activity) = kind { activity } else { nil }
        }
        #expect(changes == [.working, .waitingForYou, .ended])
    }

    @Test func waitingAndTurnDoneCountAsIdleForKeepAwake() {
        let rig = EngineRig()
        rig.scan([rig.session(.waitingForYou, id: "a"), rig.session(.turnDone, id: "b")], working: false)
        #expect(!rig.state.agentHold)
    }
}

@MainActor
struct EngineCutoffTests {
    @Test func heatCutsOffAManualSession() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: nil)
        rig.system.thermal = .serious
        rig.system.send(.thermalChanged)
        #expect(rig.state.manual == nil)
        #expect(rig.state.cutoff == .heat)
        #expect(rig.state.menuIconBase == .cutoff)
        #expect(rig.power.last?.system == false)
        #expect(rig.lid.last?.holdWanted == false)
        #expect(rig.journal.kinds.contains(.safetyStop(.heat)))
        #expect(rig.journal.kinds.contains(.awakeEnded(reason: "cutoff")))
        #expect(rig.model.statusLine == "Turned off because the Mac got too warm")
    }

    @Test func batteryCutsOffAndNamesThePercent() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: nil)
        rig.system.onBattery = true
        rig.system.batteryPercent = 15
        rig.system.send(.powerSourceChanged)
        #expect(rig.state.cutoff == .battery)
        #expect(rig.notifier.posted.map(\.body) == ["Battery at 15%, so I let your Mac sleep."])
        #expect(rig.notifier.posted.first?.title == "MacBull stopped")
    }

    @Test func cutoffWhileAgentsHoldPausesAndSaysSo() {
        let rig = EngineRig()
        rig.scan([rig.session()])
        rig.system.thermal = .critical
        rig.system.send(.thermalChanged)
        #expect(rig.state.cutoff == .heat)
        #expect(rig.state.paused)
        #expect(!rig.state.agentHold)
        #expect(rig.notifier.posted.first?.body == "Your Mac got too warm, so I let your Mac sleep. Your agents were still working.")
        rig.scan([rig.session()])
        #expect(!rig.state.agentHold)
        #expect(rig.state.cutoff == .heat)
    }

    @Test func fairHeatCutsOffWhenHeldAndClosedInABag() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: nil)
        rig.system.lidClosed = true
        rig.system.thermal = .fair
        rig.system.send(.lidChanged)
        #expect(rig.state.closedInBag)
        #expect(rig.state.cutoff == .heat)
    }

    @Test func fairHeatIsFineOnADeskOrWithoutTheLidHold() {
        let desk = EngineRig()
        desk.model.turnOn(minutes: nil)
        desk.system.lidClosed = true
        desk.system.hasExternalDisplay = true
        desk.system.thermal = .fair
        desk.system.send(.lidChanged)
        #expect(!desk.state.closedInBag)
        #expect(desk.state.manual != nil)

        let open = EngineRig()
        open.model.turnOn(minutes: nil)
        open.system.thermal = .fair
        open.system.send(.thermalChanged)
        #expect(open.state.manual != nil)

        let noLidMode = EngineRig { $0.lidHold = false }
        noLidMode.model.turnOn(minutes: nil)
        noLidMode.system.lidClosed = true
        noLidMode.system.thermal = .fair
        noLidMode.system.send(.lidChanged)
        #expect(noLidMode.state.cutoff == nil)
    }

    @Test func turningOnInABadStateCutsOffAtOnce() {
        let rig = EngineRig()
        rig.system.onBattery = true
        rig.system.batteryPercent = 10
        rig.model.turnOn(minutes: nil)
        #expect(rig.state.manual == nil)
        #expect(rig.state.cutoff == .battery)
        #expect(rig.power.last?.system == false)
        #expect(rig.notifier.posted.count == 1)
    }

    @Test func repeatedImmediateCutoffsAreThrottled() {
        let rig = EngineRig()
        rig.system.onBattery = true
        rig.system.batteryPercent = 10
        rig.model.turnOn(minutes: nil)
        rig.advance(minutes: 1)
        rig.model.turnOn(minutes: nil)
        #expect(rig.notifier.posted.count == 1)
        rig.advance(minutes: 5)
        rig.model.turnOn(minutes: nil)
        #expect(rig.notifier.posted.count == 2)
    }

    @Test func heatAndBatteryThrottleSeparately() {
        let rig = EngineRig()
        rig.system.onBattery = true
        rig.system.batteryPercent = 10
        rig.model.turnOn(minutes: nil)
        rig.system.thermal = .serious
        rig.model.turnOn(minutes: nil)
        #expect(rig.notifier.posted.map(\.identifier) == ["battery-stop", "heat-stop"])
    }

    @Test func agentHoldRefusesToStartInABadState() {
        let rig = EngineRig()
        rig.system.thermal = .serious
        rig.scan([rig.session()])
        #expect(!rig.state.agentHold)
        #expect(rig.state.cutoff == nil)
        #expect(rig.notifier.posted.isEmpty)
        rig.system.thermal = .nominal
        rig.tick()
        #expect(rig.state.agentHold)
    }

    @Test func batteryNoteGoesWhenPluggedIn() {
        let rig = EngineRig()
        rig.system.onBattery = true
        rig.system.batteryPercent = 10
        rig.model.turnOn(minutes: nil)
        #expect(rig.state.cutoff == .battery)
        rig.system.onBattery = false
        rig.system.send(.powerSourceChanged)
        #expect(rig.state.cutoff == nil)
    }

    @Test func batteryNoteGoesWhenTheGuardIsTurnedOff() {
        let rig = EngineRig()
        rig.system.onBattery = true
        rig.system.batteryPercent = 10
        rig.model.turnOn(minutes: nil)
        rig.settings.batteryGuard = false
        #expect(rig.state.cutoff == nil)
    }

    @Test func heatNoteStaysUntilNominal() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: nil)
        rig.system.thermal = .serious
        rig.system.send(.thermalChanged)
        rig.system.thermal = .fair
        rig.system.send(.thermalChanged)
        #expect(rig.state.cutoff == .heat)
        rig.system.thermal = .nominal
        rig.system.send(.thermalChanged)
        #expect(rig.state.cutoff == nil)
    }

    @Test func noCutoffWhenNotAwake() {
        let rig = EngineRig()
        rig.system.thermal = .critical
        rig.system.send(.thermalChanged)
        #expect(rig.state.cutoff == nil)
        #expect(rig.notifier.posted.isEmpty)
    }

    @Test func guardsOffNeverCutOff() {
        let rig = EngineRig { $0.heatGuard = false; $0.batteryGuard = false }
        rig.model.turnOn(minutes: nil)
        rig.system.thermal = .critical
        rig.system.onBattery = true
        rig.system.batteryPercent = 1
        rig.system.send(.thermalChanged)
        #expect(rig.state.manual != nil)
    }
}

@MainActor
struct EnginePowerAndLidTests {
    @Test func manualHoldsSystemAndDisplay() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: nil)
        #expect(rig.power.last?.system == true)
        #expect(rig.power.last?.display == true)
    }

    @Test func displaySettingOffKeepsDisplayFree() {
        let rig = EngineRig { $0.keepDisplayOn = false }
        rig.model.turnOn(minutes: nil)
        #expect(rig.power.last?.system == true)
        #expect(rig.power.last?.display == false)
    }

    @Test func baggedWithLidModeKeepsSystemNotDisplay() {
        let rig = EngineRig()
        rig.system.lidClosed = true
        rig.model.turnOn(minutes: nil)
        #expect(rig.state.closedInBag)
        #expect(rig.power.last?.system == true)
        #expect(rig.power.last?.display == false)
        #expect(rig.lid.last == EngineFakes.ApplyCall(holdWanted: true, closedInBag: true, onBattery: false, lowPowerWanted: false))
    }

    @Test func baggedOnBatteryAsksForLowPower() {
        let rig = EngineRig()
        rig.system.lidClosed = true
        rig.system.onBattery = true
        rig.system.batteryPercent = 80
        rig.model.turnOn(minutes: nil)
        #expect(rig.lid.last?.lowPowerWanted == true)
        rig.settings.lowPowerInBag = false
        #expect(rig.lid.last?.lowPowerWanted == false)
    }

    @Test func baggedWithoutPermissionLetsTheMacSleep() {
        let rig = EngineRig()
        rig.lid.setup = .notSetUp
        rig.system.lidClosed = true
        rig.model.turnOn(minutes: nil)
        #expect(rig.power.last?.system == false)
        #expect(rig.lid.last?.holdWanted == false)
    }

    @Test func baggedWithTheSettingOffLetsTheMacSleep() {
        let rig = EngineRig { $0.lidHold = false }
        rig.system.lidClosed = true
        rig.model.turnOn(minutes: nil)
        #expect(rig.power.last?.system == false)
    }

    @Test func externalDisplayCountsAsADesk() {
        let rig = EngineRig()
        rig.system.lidClosed = true
        rig.system.hasExternalDisplay = true
        rig.model.turnOn(minutes: nil)
        #expect(!rig.state.closedInBag)
        #expect(rig.power.last?.display == true)
        #expect(rig.lid.last?.closedInBag == false)
    }

    @Test func lidHoldIsWantedAsSoonAsAwakeWhateverTheLidDoes() {
        let rig = EngineRig()
        #expect(rig.lid.last?.holdWanted == false)
        rig.model.turnOn(minutes: nil)
        #expect(rig.lid.last?.holdWanted == true)
        #expect(rig.state.lidHeld)
    }

    @Test func lidHoldNotWantedWithoutSetupOrSetting() {
        let rig = EngineRig()
        rig.lid.setup = .notSetUp
        rig.model.turnOn(minutes: nil)
        #expect(rig.lid.last?.holdWanted == false)
        #expect(rig.state.lidSetup == .notSetUp)
        rig.lid.setup = .ready
        rig.settings.lidHold = false
        #expect(rig.lid.last?.holdWanted == false)
    }

    @Test func lidFactsAreMirroredIntoState() {
        let rig = EngineRig()
        rig.lid.lastError = "pmset failed"
        rig.model.turnOn(minutes: nil)
        #expect(rig.state.lidError == "pmset failed")
        #expect(rig.state.lidSetup == .ready)
    }

    @Test func theWantedAssertionsAreAskedForOnEveryEvaluationSoARefusedOneIsRetried() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: nil)
        let before = rig.power.calls.count
        for _ in 0..<5 { rig.tick() }
        let ticks = rig.power.calls.dropFirst(before)
        #expect(ticks.count == 5)
        let wanted = rig.power.calls[before - 1]
        #expect(wanted.system)
        #expect(ticks.allSatisfy { $0.system == wanted.system && $0.display == wanted.display })
    }

    @Test func batteryAndThermalAreMirroredAndJournaledOnChange() {
        let rig = EngineRig()
        rig.system.batteryPercent = 79
        rig.system.send(.powerSourceChanged)
        rig.system.send(.powerSourceChanged)
        rig.system.thermal = .fair
        rig.system.send(.thermalChanged)
        #expect(rig.state.batteryPercent == 79)
        #expect(rig.state.thermal == .fair)
        let batteries = rig.journal.kinds.filter { if case .battery = $0 { true } else { false } }
        #expect(batteries == [.battery(percent: 80, onAC: true), .battery(percent: 79, onAC: true)])
        #expect(rig.journal.kinds.contains(.thermal(level: 1)))
    }

    @Test func installAndRemoveWriteTheNewLidSetupAndErrorIntoState() async {
        let rig = EngineRig()
        rig.lid.setup = .notSetUp
        rig.model.turnOn(minutes: nil)
        rig.lid.duringInstall = { rig.lid.setup = .ready; rig.lid.lastError = nil }
        _ = await rig.model.installLid()
        #expect(rig.state.lidSetup == .ready)
        rig.lid.duringUninstall = { rig.lid.setup = .notSetUp; rig.lid.lastError = "could not remove" }
        _ = await rig.model.removeLid()
        #expect(rig.state.lidSetup == .notSetUp)
        #expect(rig.state.lidError == "could not remove")
    }

    @Test func theTickPicksUpLidFactsThatChangedByThemselves() {
        let rig = EngineRig()
        rig.lid.setup = .notSetUp
        rig.lid.lastError = "the rule was removed"
        rig.tick()
        #expect(rig.state.lidSetup == .notSetUp)
        #expect(rig.state.lidError == "the rule was removed")
    }

    @Test func installAndRemoveRecheckSetup() async {
        let rig = EngineRig()
        let installed = await rig.model.installLid()
        let removed = await rig.model.removeLid()
        #expect(installed == .success)
        #expect(removed == .cancelled)
        #expect(rig.lid.events.filter { $0 == "refresh" }.count == 3)
    }
}
