import Foundation
import Testing
@testable import MacBull

/// Quit flush, the power-off notice, the idle tick and the status line (review fixes 5, 8, 9).
@MainActor
struct EngineHousekeepingTests {
    // MARK: Quit flushes the journal

    @Test func quitFlushesTheJournalAfterTheLastEventIsRecorded() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: 30)
        rig.model.quit()
        #expect(rig.journal.kinds.last == .appQuit)
        #expect(rig.journal.flushedAfter == [rig.journal.events.count], "flushed once, after appQuit was queued")
    }

    @Test func quittingTwiceFlushesOnce() {
        let rig = EngineRig()
        rig.model.prepareForQuit()
        rig.model.prepareForQuit()
        #expect(rig.journal.flushedAfter.count == 1)
    }

    // MARK: A power-off notice does not stick

    private func lastCleanUp(_ rig: EngineRig) -> String? {
        rig.lid.events.last { $0.hasPrefix("cleanUp") }
    }

    @Test func aRecentPowerOffNoticeTellsTheLidNotToSleepTheMac() {
        let rig = EngineRig()
        rig.system.send(.powerOff)
        rig.advance(minutes: 0.5)
        rig.model.prepareForQuit()
        #expect(lastCleanUp(rig) == "cleanUp(true)")
    }

    @Test func aPowerOffNoticeThatCameToNothingIsForgottenAfterSixtySeconds() {
        let rig = EngineRig()
        rig.system.send(.powerOff)
        rig.advance(minutes: 1.01)
        rig.model.prepareForQuit()
        #expect(lastCleanUp(rig) == "cleanUp(false)")
    }

    @Test func wakingClearsThePowerOffNotice() {
        let rig = EngineRig()
        rig.system.send(.powerOff)
        rig.system.send(.didWake)
        rig.model.prepareForQuit()
        #expect(lastCleanUp(rig) == "cleanUp(false)")
    }

    @Test func theUserComingBackClearsThePowerOffNotice() {
        let rig = EngineRig()
        rig.system.send(.awayStarted)
        rig.system.send(.powerOff)
        rig.system.send(.awayEnded)
        rig.model.prepareForQuit()
        #expect(lastCleanUp(rig) == "cleanUp(false)")
    }

    // MARK: The tick slows down when nothing needs watching

    private func interval(_ rig: EngineRig) -> TimeInterval? {
        rig.scheduler.ticks.first?.interval
    }

    @Test func awayKeepsTheFastTickAndComingBackSlowsIt() {
        let rig = EngineRig()
        #expect(interval(rig) == EngineTiming.idleTickSeconds)
        rig.system.send(.awayStarted)
        #expect(interval(rig) == EngineTiming.tickSeconds)
        rig.system.send(.awayEnded)
        #expect(interval(rig) == EngineTiming.idleTickSeconds)
        #expect(rig.scheduler.ticks.count == 1, "the old tick is cancelled, never two at once")
    }

    @Test func aWaitingSessionKeepsTheFastTickForTheReminders() {
        let rig = EngineRig()
        rig.scan([rig.session(.waitingForYou)])
        #expect(interval(rig) == EngineTiming.tickSeconds)
        rig.scan([])
        #expect(interval(rig) == EngineTiming.idleTickSeconds)
    }

    @Test func anAgentHoldKeepsTheFastTick() {
        let rig = EngineRig()
        rig.scan([rig.session(.working)])
        #expect(rig.state.agentHold)
        #expect(interval(rig) == EngineTiming.tickSeconds)
    }

    @Test func theSlowTickStillEvaluatesAndEventsStillStartEvaluations() {
        let rig = EngineRig()
        rig.system.onBattery = true
        rig.system.send(.powerSourceChanged)
        #expect(rig.state.onBattery, "a power event evaluates at once, without waiting for the slow tick")
        rig.system.batteryPercent = 55
        rig.tick()
        #expect(rig.state.batteryPercent == 55)
    }

    @Test func nothingIsRescheduledAfterQuit() {
        let rig = EngineRig()
        rig.model.prepareForQuit()
        rig.model.retuneTick()
        #expect(rig.scheduler.ticks.isEmpty)
    }

    // MARK: The power source is read once per evaluation

    @Test func oneEvaluationReadsEachPowerNumberOnce() {
        let rig = EngineRig()
        rig.system.resetReadCounts()
        rig.model.turnOn(minutes: nil)
        #expect(rig.system.onBatteryReads == 1)
        #expect(rig.system.batteryPercentReads == 1)
    }

    // MARK: The tooltip text comes from the tick

    @Test func theCountdownTextReachesTheMenuBarFromTheEngineTick() {
        let rig = EngineRig()
        var lines: [String] = []
        rig.model.onStatusLineChange = { lines.append($0) }
        rig.model.turnOn(minutes: 30)
        rig.tick(afterMinutes: 1)
        rig.tick(afterMinutes: 1)
        #expect(lines == ["Awake for 30 min more", "Awake for 29 min more", "Awake for 28 min more"])
    }
}
