import Foundation
import Testing
@testable import MacBull

@MainActor
struct LidControllerTests {
    // MARK: Setup detection

    @Test func readyWhenPlistExistsAndSudoListsOurRule() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        #expect(rig.controller.setup == .ready)
    }

    @Test func notSetUpWithoutTheBootPlist() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.state.daemonPlistExists = false
        await rig.makeReady()
        #expect(rig.controller.setup == .notSetUp)
        #expect(rig.shell.count(Cmd.list) == 0)
    }

    @Test func notSetUpWhenSudoListingFails() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.shell.fail(Cmd.list)
        await rig.makeReady()
        #expect(rig.controller.setup == .notSetUp)
    }

    @Test func notSetUpWhenALaterRuleAsksForAPassword() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.shell.setListing(FakeShell.readyListing + "\n    (ALL) ALL")
        await rig.makeReady()
        #expect(rig.controller.setup == .notSetUp)
    }

    @Test func noLidMac() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.state.hasLid = false
        await rig.makeReady()
        #expect(rig.controller.setup == .noLid)
    }

    // MARK: Install and uninstall

    @Test func installRefusesUnusualAccountNamesWithoutPrompting() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.state.account = "o'brien"
        let result = await rig.controller.install()
        #expect(result == .failed(LidCopy.badAccountName))
        #expect(rig.privileged.receivedCommands.isEmpty)
        #expect(rig.controller.lastError == LidCopy.badAccountName)
    }

    @Test func installShowsOnePromptWithTheRuleInsideAndSucceeds() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        let result = await rig.controller.install()
        #expect(result == .success)
        #expect(rig.privileged.receivedCommands.count == 1)
        #expect(rig.privileged.receivedPrompts == [LidCopy.installPrompt])
        #expect(rig.controller.setup == .ready)
        #expect(rig.controller.lastError == nil)
    }

    @Test func cancelledInstallShowsNoError() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.privileged.answer(with: .cancelled)
        rig.state.daemonPlistExists = false
        let result = await rig.controller.install()
        #expect(result == .cancelled)
        #expect(rig.controller.lastError == nil)
        #expect(rig.controller.setup == .notSetUp)
    }

    @Test func failedInstallSaysMacOSRefused() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.privileged.answer(with: .failed("boom"))
        let result = await rig.controller.install()
        #expect(result == .failed(LidCopy.macOSRefused))
    }

    @Test func installThatSudoDoesNotReadIsReportedAsSuch() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.shell.fail(Cmd.list)
        let result = await rig.controller.install()
        #expect(result == .failed(LidCopy.sudoersNotIncluded))
    }

    @Test func installOnAMacWithoutALidFails() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.state.hasLid = false
        let result = await rig.controller.install()
        #expect(result == .failed(LidCopy.noLid))
    }

    @Test func uninstallClearsFlagsAndStopsTheWatchdog() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply()
        #expect(rig.controller.isHeld)
        rig.state.daemonPlistExists = false
        let result = await rig.controller.uninstall()
        #expect(result == .success)
        #expect(rig.privileged.receivedPrompts == [LidCopy.removePrompt])
        #expect(!rig.controller.isHeld)
        #expect(!rig.flags.exists(.sleepDisabled))
        #expect(!rig.watchdog.running)
        #expect(rig.controller.setup == .notSetUp)
    }

    @Test func cancelledUninstallChangesNothing() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply()
        rig.privileged.answer(with: .cancelled)
        let result = await rig.controller.uninstall()
        #expect(result == .cancelled)
        #expect(rig.controller.isHeld)
        #expect(rig.flags.exists(.sleepDisabled))
    }

    // MARK: Hold on and off

    @Test func holdSetsFlagAndWatchdogBeforeTheCallAndKeepsThem() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply()
        #expect(rig.shell.count(Cmd.holdOn) == 1)
        #expect(rig.controller.isHeld)
        #expect(rig.flags.exists(.sleepDisabled))
        #expect(rig.watchdog.running)
    }

    @Test func applyIsIdempotent() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply()
        await rig.apply()
        await rig.apply()
        #expect(rig.shell.count(Cmd.holdOn) == 1)
    }

    @Test func noHoldWithoutValidSetup() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.apply()
        #expect(rig.shell.count(Cmd.holdOn) == 0)
        #expect(!rig.controller.isHeld)
    }

    @Test func failedEnableRemovesTheFlagRechecksSetupAndWaitsSixtySeconds() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        let listCallsBefore = rig.shell.count(Cmd.list)
        rig.shell.fail(Cmd.holdOn)
        await rig.apply()
        #expect(!rig.controller.isHeld)
        #expect(!rig.flags.exists(.sleepDisabled))
        #expect(!rig.watchdog.running)
        #expect(rig.shell.count(Cmd.list) == listCallsBefore + 1)
        #expect(rig.controller.lastError == LidCopy.enableFailed)

        rig.clock.now.addTimeInterval(59)
        await rig.apply()
        #expect(rig.shell.count(Cmd.holdOn) == 1)
        rig.clock.now.addTimeInterval(2)
        rig.shell.succeed(Cmd.holdOn)
        await rig.apply()
        #expect(rig.shell.count(Cmd.holdOn) == 2)
        #expect(rig.controller.isHeld)
        #expect(rig.controller.lastError == nil)
    }

    @Test func enableFailureBecauseTheRuleIsGoneShowsNotSetUp() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        rig.shell.fail(Cmd.holdOn)
        rig.shell.fail(Cmd.list)
        await rig.apply()
        #expect(rig.controller.setup == .notSetUp)
    }

    @Test func releaseWhileNotInABagDoesNotSleepTheMac() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply()
        await rig.apply(hold: false)
        #expect(rig.shell.count(Cmd.holdOff) == 1)
        #expect(rig.shell.count(Cmd.sleepNow) == 0)
        #expect(!rig.controller.isHeld)
        #expect(!rig.flags.exists(.sleepDisabled))
        #expect(!rig.watchdog.running)
    }

    @Test func releaseWhileClosedInABagSleepsTheMac() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply(bag: true)
        await rig.apply(hold: false, bag: true)
        #expect(rig.shell.count(Cmd.holdOff) == 1)
        #expect(rig.shell.count(Cmd.sleepNow) == 1)
        #expect(!rig.flags.exists(.heldInBag))
    }

    @Test func failedReleaseRetriesAfterFifteenSeconds() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply()
        rig.shell.fail(Cmd.holdOff)
        await rig.apply(hold: false)
        #expect(rig.controller.isHeld)
        #expect(rig.flags.exists(.sleepDisabled))
        rig.clock.now.addTimeInterval(14)
        await rig.apply(hold: false)
        #expect(rig.shell.count(Cmd.holdOff) == 1)
        rig.clock.now.addTimeInterval(1.5)
        rig.shell.succeed(Cmd.holdOff)
        await rig.apply(hold: false)
        #expect(rig.shell.count(Cmd.holdOff) == 2)
        #expect(!rig.controller.isHeld)
    }

    // MARK: In a bag

    @Test func enteringTheBagTurnsTheDisplayOffOnceAndWritesTheFlag() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply()
        #expect(rig.shell.count(Cmd.displayOff) == 0)
        await rig.apply(bag: true)
        await rig.apply(bag: true)
        #expect(rig.shell.count(Cmd.displayOff) == 1)
        #expect(rig.flags.exists(.heldInBag))
        await rig.apply(bag: false)
        #expect(!rig.flags.exists(.heldInBag))
        await rig.apply(bag: true)
        #expect(rig.shell.count(Cmd.displayOff) == 2)
    }

    // MARK: Low Power Mode

    @Test func lowPowerOnlyWhenHeldBaggedOnBatteryAndWanted() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply(bag: false, battery: true)
        await rig.apply(bag: true, battery: false)
        await rig.apply(bag: true, battery: true, lowPower: false)
        #expect(rig.shell.count(Cmd.lowOn) == 0)
        await rig.apply(bag: true, battery: true)
        #expect(rig.shell.count(Cmd.lowOn) == 1)
        #expect(rig.flags.exists(.lowPowerForced))
    }

    @Test func lowPowerIsReleasedAsSoonAsItIsNotWanted() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply(bag: true, battery: true)
        await rig.apply(bag: true, battery: false)
        #expect(rig.shell.count(Cmd.lowOff) == 1)
        #expect(!rig.flags.exists(.lowPowerForced))
        #expect(rig.watchdog.running, "sleep is still disabled, so the watchdog stays")
    }

    @Test func aUserWhoAlreadyRunsLowPowerKeepsOwnership() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.state.systemLowPower = true
        await rig.makeReady()
        await rig.apply(bag: true, battery: true)
        await rig.apply(bag: true, battery: false)
        #expect(rig.shell.count(Cmd.lowOn) == 0)
        #expect(rig.shell.count(Cmd.lowOff) == 0)
        #expect(!rig.flags.exists(.lowPowerForced))
    }

    @Test func lowPowerFailureRetriesAfterSixtySecondsAndNeverBlocksTheLidHold() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        rig.shell.fail(Cmd.lowOn)
        await rig.apply(bag: true, battery: true)
        #expect(rig.controller.isHeld)
        #expect(!rig.flags.exists(.lowPowerForced))
        rig.clock.now.addTimeInterval(59)
        await rig.apply(bag: true, battery: true)
        #expect(rig.shell.count(Cmd.lowOn) == 1)
        rig.clock.now.addTimeInterval(2)
        await rig.apply(bag: true, battery: true)
        #expect(rig.shell.count(Cmd.lowOn) == 2)
        // Releasing the lid hold is not delayed by the Low Power clock.
        await rig.apply(hold: false, bag: true, battery: true)
        #expect(rig.shell.count(Cmd.holdOff) == 1)
    }

    @Test func lowPowerFlagIsRemovedWhenTheCallFails() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        rig.shell.fail(Cmd.lowOn)
        await rig.apply(bag: true, battery: true)
        #expect(!rig.flags.exists(.lowPowerForced))
    }

    // MARK: Launch and quit

    @Test func restoreAtLaunchUndoesLeftoverFlags() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        #expect(rig.flags.set(.sleepDisabled))
        #expect(rig.flags.set(.lowPowerForced))
        #expect(rig.flags.set(.heldInBag))
        rig.controller.restoreAtLaunch()
        await rig.controller.waitUntilIdle()
        #expect(rig.shell.count(Cmd.holdOff) == 1)
        #expect(rig.shell.count(Cmd.lowOff) == 1)
        #expect(!rig.flags.exists(.sleepDisabled))
        #expect(!rig.flags.exists(.lowPowerForced))
        #expect(!rig.flags.exists(.heldInBag))
        #expect(!rig.controller.isHeld)
    }

    @Test func failedRestoreKeepsTheFlagForTheNextLaunch() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        #expect(rig.flags.set(.sleepDisabled))
        rig.shell.fail(Cmd.holdOff)
        rig.controller.restoreAtLaunch()
        await rig.controller.waitUntilIdle()
        #expect(rig.flags.exists(.sleepDisabled))
    }

    @Test func restoreAtLaunchWithoutFlagsDoesNothing() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.controller.restoreAtLaunch()
        await rig.controller.waitUntilIdle()
        #expect(rig.shell.calls.isEmpty)
    }

    @Test func quitUndoesEverythingAndSleepsABaggedMac() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply(bag: true, battery: true)
        rig.controller.cleanUpForQuit(systemPoweringOff: false)
        #expect(rig.shell.count(Cmd.holdOff) == 1)
        #expect(rig.shell.count(Cmd.lowOff) == 1)
        #expect(rig.shell.count(Cmd.sleepNow) == 1)
        #expect(Flag.noneSet(rig.flags))
        #expect(!rig.watchdog.running)
        #expect(!rig.controller.isHeld)
    }

    @Test func quitDuringPowerOffNeverSleeps() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply(bag: true)
        rig.controller.cleanUpForQuit(systemPoweringOff: true)
        #expect(rig.shell.count(Cmd.holdOff) == 1)
        #expect(rig.shell.count(Cmd.sleepNow) == 0)
    }

    @Test func quitWhileNotInABagDoesNotSleep() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply()
        rig.controller.cleanUpForQuit(systemPoweringOff: false)
        #expect(rig.shell.count(Cmd.holdOff) == 1)
        #expect(rig.shell.count(Cmd.sleepNow) == 0)
    }

    @Test func quitWhenUndoFailsLeavesTheWatchdogAndFlagsToFinishTheJob() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply(bag: true)
        rig.shell.fail(Cmd.holdOff)
        rig.controller.cleanUpForQuit(systemPoweringOff: false)
        #expect(rig.flags.exists(.sleepDisabled))
        #expect(rig.flags.exists(.heldInBag))
        #expect(rig.watchdog.running)
        #expect(rig.shell.count(Cmd.sleepNow) == 0)
    }

    @Test func nothingIsReconciledAfterQuit() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        rig.controller.cleanUpForQuit(systemPoweringOff: false)
        await rig.apply()
        #expect(rig.shell.count(Cmd.holdOn) == 0)
    }

    // MARK: Sleep Now while the hold is on

    @Test func sleepNowWhileHeldSleepsOnlyAfterTheReleaseHasGoneThrough() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply()
        rig.shell.slow(Cmd.holdOff, seconds: 0.15)
        // What the engine does: turn everything off, then ask for the sleep, without waiting in between.
        rig.controller.apply(holdWanted: false, closedInBag: false, onBattery: false, lowPowerWanted: true)
        rig.controller.sleepNow()
        await rig.controller.waitUntilIdle()
        #expect(rig.shell.calls.suffix(2) == [Cmd.holdOff, Cmd.sleepNow])
        #expect(rig.shell.count(Cmd.sleepNow) == 1)
        #expect(!rig.controller.isHeld)
    }

    @Test func sleepNowWaitsForAFailedReleaseToSucceedAndThenSleeps() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply()
        rig.shell.fail(Cmd.holdOff)
        rig.controller.apply(holdWanted: false, closedInBag: false, onBattery: false, lowPowerWanted: true)
        rig.controller.sleepNow()
        await rig.controller.waitUntilIdle()
        #expect(rig.controller.isHeld)
        #expect(rig.shell.count(Cmd.sleepNow) == 0, "the Mac cannot sleep while disablesleep is still on")
        rig.clock.now.addTimeInterval(16)
        rig.shell.succeed(Cmd.holdOff)
        await rig.apply(hold: false)
        #expect(rig.shell.calls.suffix(2) == [Cmd.holdOff, Cmd.sleepNow])
    }

    @Test func turningTheHoldBackOnCancelsAWaitingSleep() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply()
        rig.shell.fail(Cmd.holdOff)
        rig.controller.apply(holdWanted: false, closedInBag: false, onBattery: false, lowPowerWanted: true)
        rig.controller.sleepNow()
        await rig.controller.waitUntilIdle()
        await rig.apply(hold: true)
        rig.clock.now.addTimeInterval(16)
        rig.shell.succeed(Cmd.holdOff)
        await rig.apply(hold: false)
        #expect(!rig.controller.isHeld)
        #expect(rig.shell.count(Cmd.sleepNow) == 0)
    }

    @Test func sleepNowWhileTheEnableIsStillRunningSleepsAfterThePairIsUndone() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        rig.shell.slow(Cmd.holdOn, seconds: 0.15)
        rig.controller.apply(holdWanted: true, closedInBag: false, onBattery: false, lowPowerWanted: true)
        await waitUntilStarted(rig.shell, Cmd.holdOn)
        rig.controller.apply(holdWanted: false, closedInBag: false, onBattery: false, lowPowerWanted: true)
        rig.controller.sleepNow()
        await rig.controller.waitUntilIdle()
        #expect(rig.shell.calls.suffix(3) == [Cmd.holdOn, Cmd.holdOff, Cmd.sleepNow])
    }

    // MARK: Releasing with the lid shut at a desk

    @Test func releaseWithTheLidShutOnBatteryAtADeskStillSleepsTheMac() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        rig.state.lidClosed = true
        await rig.apply(bag: false, battery: true)
        await rig.apply(hold: false, bag: false, battery: true)
        #expect(rig.shell.count(Cmd.holdOff) == 1)
        #expect(rig.shell.count(Cmd.sleepNow) == 1)
    }

    @Test func releaseWithTheLidShutOnPowerAtADeskDoesNotSleepTheMac() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        rig.state.lidClosed = true
        await rig.apply(bag: false, battery: false)
        await rig.apply(hold: false, bag: false, battery: false)
        #expect(rig.shell.count(Cmd.holdOff) == 1)
        #expect(rig.shell.count(Cmd.sleepNow) == 0)
    }

    @Test func releaseWithTheLidOpenOnBatteryDoesNotSleepTheMac() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply(bag: false, battery: true)
        await rig.apply(hold: false, bag: false, battery: true)
        #expect(rig.shell.count(Cmd.holdOff) == 1)
        #expect(rig.shell.count(Cmd.sleepNow) == 0)
    }

    // MARK: Quit while a command is still running

    @Test func quitDuringASlowEnableUndoesItAfterwardsAndOnlyThenClearsTheFlag() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        let flags = rig.flags
        let flagWhenTheDisableStarted = FlagProbe()
        rig.shell.onStart = { command in
            if command == Cmd.holdOff { flagWhenTheDisableStarted.set(flags.exists(.sleepDisabled)) }
        }
        rig.shell.slow(Cmd.holdOn, seconds: 0.2)
        rig.controller.apply(holdWanted: true, closedInBag: false, onBattery: false, lowPowerWanted: true)
        await waitUntilStarted(rig.shell, Cmd.holdOn)

        rig.controller.cleanUpForQuit(systemPoweringOff: false)

        #expect(rig.shell.calls.suffix(2) == [Cmd.holdOn, Cmd.holdOff], "the enable finishes first, the disable lands last")
        #expect(rig.shell.mostAtOnce == 1)
        #expect(flagWhenTheDisableStarted.value == true, "the flag is still there when the disable runs")
        #expect(Flag.noneSet(rig.flags))
        #expect(!rig.watchdog.running)
        await rig.controller.waitUntilIdle()
        #expect(!rig.controller.isHeld)
        #expect(rig.shell.count(Cmd.holdOn) == 1)
        #expect(rig.shell.count(Cmd.holdOff) == 1)
    }

    @Test func quitDuringASlowLowPowerEnableUndoesItAfterwards() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        await rig.apply(bag: true, battery: false)
        rig.shell.slow(Cmd.lowOn, seconds: 0.2)
        rig.controller.apply(holdWanted: true, closedInBag: true, onBattery: true, lowPowerWanted: true)
        await waitUntilStarted(rig.shell, Cmd.lowOn)

        rig.controller.cleanUpForQuit(systemPoweringOff: true)

        let calls = rig.shell.calls
        let on = calls.firstIndex(of: Cmd.lowOn) ?? Int.max
        let off = calls.lastIndex(of: Cmd.lowOff) ?? -1
        #expect(on < off)
        #expect(rig.shell.mostAtOnce == 1)
        #expect(Flag.noneSet(rig.flags))
        await rig.controller.waitUntilIdle()
    }

    @Test func aQueuedEnableThatStartsAfterQuitIsDropped() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        rig.controller.apply(holdWanted: true, closedInBag: false, onBattery: false, lowPowerWanted: true)
        rig.controller.cleanUpForQuit(systemPoweringOff: false)
        await rig.controller.waitUntilIdle()
        #expect(rig.shell.count(Cmd.holdOn) == 0)
        #expect(Flag.noneSet(rig.flags))
    }

    @Test func everyCommandRunsOneAtATime() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        await rig.makeReady()
        rig.shell.slow(Cmd.holdOn, seconds: 0.05)
        rig.shell.slow(Cmd.displayOff, seconds: 0.05)
        rig.shell.slow(Cmd.lowOn, seconds: 0.05)
        await rig.apply(bag: true, battery: true)
        rig.controller.sleepNow()
        await rig.controller.waitUntilIdle()
        #expect(rig.shell.mostAtOnce == 1)
    }

    @Test func sleepNowRunsPmset() async {
        let rig = LidRig()
        defer { rig.cleanUp() }
        rig.controller.sleepNow()
        await rig.controller.waitUntilIdle()
        #expect(rig.shell.count(Cmd.sleepNow) == 1)
    }
}

private func waitUntilStarted(_ shell: FakeShell, _ command: String) async {
    var tries = 0
    while !shell.hasStarted(command), tries < 1000 {
        try? await Task.sleep(for: .milliseconds(2))
        tries += 1
    }
}

private final class FlagProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool?

    var value: Bool? { lock.withLock { stored } }

    func set(_ value: Bool) {
        lock.withLock { stored = value }
    }
}

private enum Flag {
    static func noneSet(_ flags: LidFlags) -> Bool {
        LidFlags.Flag.allCases.allSatisfy { !flags.exists($0) }
    }
}
