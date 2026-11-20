import Foundation
import Testing
@testable import MacBull

@MainActor
struct EngineAgentsDoneNoticeTests {
    /// One full cycle: an agent works once, then is quiet until the grace period passes.
    private func finishHold(_ rig: EngineRig, graceMinutes: Double) {
        rig.scan([rig.session()])
        rig.scan([rig.session(.idle)])
        rig.tick(afterMinutes: graceMinutes + 0.1)
    }

    @Test func holdOfAtLeastTwoMinutesNotifies() {
        let rig = EngineRig { $0.graceMinutes = 2 }
        finishHold(rig, graceMinutes: 2)
        #expect(!rig.state.agentHold)
        #expect(rig.notifier.posted.map(\.body) == ["Agents are done. Your Mac can sleep again."])
        #expect(rig.notifier.posted.first?.title == "MacBull")
    }

    @Test func shortHoldIsABlip() {
        let rig = EngineRig { $0.graceMinutes = 1 }
        finishHold(rig, graceMinutes: 1)
        #expect(!rig.state.agentHold)
        #expect(rig.notifier.posted.isEmpty)
    }

    @Test func noNoticeWhileAManualSessionIsActive() {
        let rig = EngineRig { $0.graceMinutes = 2 }
        rig.model.turnOn(minutes: nil)
        finishHold(rig, graceMinutes: 2)
        #expect(rig.notifier.posted.isEmpty)
        #expect(rig.state.manual != nil)
    }

    @Test func saysItIsPuttingAClosedMacToSleep() {
        let rig = EngineRig { $0.graceMinutes = 2 }
        rig.system.lidClosed = true
        finishHold(rig, graceMinutes: 2)
        #expect(rig.notifier.posted.map(\.body) == ["Agents are done. Putting your Mac to sleep."])
    }

    @Test func throttledToOnePerFiveMinutes() {
        let rig = EngineRig { $0.graceMinutes = 2 }
        finishHold(rig, graceMinutes: 2)
        rig.advance(minutes: 0.2)
        finishHold(rig, graceMinutes: 2)
        #expect(rig.notifier.posted.count == 1)
        rig.advance(minutes: 5)
        finishHold(rig, graceMinutes: 2)
        #expect(rig.notifier.posted.count == 2)
    }

    @Test func heldForTheReceiptWhileAwayWithBundling() {
        let rig = EngineRig { $0.graceMinutes = 2 }
        rig.system.send(.awayStarted)
        finishHold(rig, graceMinutes: 2)
        #expect(rig.notifier.posted.isEmpty)
    }

    @Test func sentWhileAwayWhenBundlingIsOff() {
        let rig = EngineRig { $0.graceMinutes = 2; $0.bundleWhileAway = false }
        rig.system.send(.awayStarted)
        finishHold(rig, graceMinutes: 2)
        #expect(rig.notifier.posted.count == 1)
    }

    @Test func safetyStopsStillNotifyWhileAway() {
        let rig = EngineRig()
        rig.system.send(.awayStarted)
        rig.model.turnOn(minutes: nil)
        rig.system.thermal = .serious
        rig.system.send(.thermalChanged)
        #expect(rig.notifier.posted.count == 1)
    }

    @Test func timerEndUserOffAndPauseClearNeverNotify() {
        let rig = EngineRig()
        rig.scan([rig.session()])
        rig.model.turnOff()
        rig.advance(minutes: 10)
        rig.scan([rig.session(.idle)])
        rig.tick(afterMinutes: 5)
        #expect(rig.notifier.posted.isEmpty)
    }
}

@MainActor
struct EngineNotificationGateTests {
    @Test func settingOffSendsNothing() {
        let rig = EngineRig { $0.notifications = false }
        rig.model.turnOn(minutes: nil)
        rig.system.thermal = .critical
        rig.system.send(.thermalChanged)
        rig.scan([rig.session(.waitingForYou)])
        #expect(rig.notifier.posted.isEmpty)
        #expect(rig.state.cutoff == .heat)
    }

    @Test func turningTheSettingOnAsksForPermissionOnce() {
        let rig = EngineRig { $0.notifications = false }
        #expect(rig.notifier.authorizationRequests == 0)
        rig.settings.notifications = true
        rig.settings.keepDisplayOn = false
        #expect(rig.notifier.authorizationRequests == 1)
    }

    @Test func nothingWhileQuitting() {
        let rig = EngineRig()
        rig.model.prepareForQuit()
        rig.model.notifySafetyStop(.heat, agentsWereWorking: false)
        let sent = rig.model.deliver(AppNotification(identifier: "x", title: "t", body: "b", threadID: nil, soundFile: nil))
        #expect(!sent)
        #expect(rig.notifier.posted.isEmpty)
    }

    @Test func customSoundsFollowTheSetting() {
        let on = EngineRig()
        on.system.thermal = .critical
        on.model.turnOn(minutes: nil)
        on.scan([on.session(.waitingForYou)])
        #expect(on.notifier.posted.map(\.soundFile) == [NotificationSound.safetyStop, NotificationSound.waitingForYou])

        let off = EngineRig { $0.notificationSounds = false }
        off.system.thermal = .critical
        off.model.turnOn(minutes: nil)
        off.scan([off.session(.waitingForYou)])
        #expect(off.notifier.posted.map(\.soundFile) == [nil, nil])
    }

    @Test func clickingANotificationOpensThePanel() {
        let rig = EngineRig()
        rig.notifier.onActivate?()
        #expect(rig.panel.showCalls == 1)
        rig.notifier.onActivate?()
        #expect(rig.panel.showCalls == 1)
    }
}

@MainActor
struct EngineYourTurnTests {
    @Test func notifiesOncePerEpisodeWithAnIdentifierPerSession() {
        let rig = EngineRig()
        rig.scan([rig.session(.waitingForYou)])
        rig.scan([rig.session(.waitingForYou)])
        #expect(rig.notifier.posted.count == 1)
        let note = rig.notifier.posted[0]
        #expect(note.identifier == "your-turn-s1")
        #expect(note.threadID == "your-turn")
        #expect(note.body == "Claude Code in api needs you")
        #expect(note.soundFile == NotificationSound.waitingForYou)
    }

    @Test func severalSessionsShareAThreadButNotAnIdentifier() {
        let rig = EngineRig()
        rig.scan([rig.session(.waitingForYou, id: "a"), rig.session(.waitingForYou, id: "b", agent: "Claude Code", folder: nil)])
        #expect(rig.notifier.posted.map(\.identifier) == ["your-turn-a", "your-turn-b"])
        #expect(Set(rig.notifier.posted.compactMap(\.threadID)) == ["your-turn"])
        #expect(rig.notifier.posted[1].body == "Claude Code needs you")
    }

    @Test func episodeEndsWhenTheSessionWorksAgainAndStartsNewOne() {
        let rig = EngineRig()
        rig.scan([rig.session(.waitingForYou)])
        rig.scan([rig.session(.working)])
        #expect(rig.notifier.withdrawn == ["your-turn-s1"])
        rig.scan([rig.session(.waitingForYou)])
        #expect(rig.notifier.posted.count == 2)
    }

    @Test func episodeEndsWhenTheSessionDisappears() {
        let rig = EngineRig()
        rig.scan([rig.session(.waitingForYou)])
        rig.scan([])
        #expect(rig.notifier.withdrawn == ["your-turn-s1"])
    }

    @Test func reminderAfterTheConfiguredTimeOncePerEpisode() {
        let rig = EngineRig()
        rig.scan([rig.session(.waitingForYou)])
        rig.tick(afterMinutes: 4)
        #expect(rig.notifier.posted.count == 1)
        rig.tick(afterMinutes: 1)
        #expect(rig.notifier.posted.count == 2)
        #expect(rig.notifier.posted[1].title == "Still waiting")
        #expect(rig.notifier.posted[1].identifier == "your-turn-s1")
        rig.tick(afterMinutes: 30)
        #expect(rig.notifier.posted.count == 2)
    }

    @Test func noReminderWhenTheUserIsNotAtTheMacUntilTheyReturn() {
        let rig = EngineRig()
        rig.scan([rig.session(.waitingForYou)])
        rig.system.secondsSinceInput = 600
        rig.tick(afterMinutes: 10)
        #expect(rig.notifier.posted.count == 1)
        rig.system.secondsSinceInput = 30
        rig.tick()
        #expect(rig.notifier.posted.count == 2)
    }

    @Test func reminderOffMeansNone() {
        let rig = EngineRig { $0.remindAfterMinutes = 0 }
        rig.scan([rig.session(.waitingForYou)])
        rig.tick(afterMinutes: 60)
        #expect(rig.notifier.posted.count == 1)
    }

    @Test func newEpisodeGetsItsOwnReminder() {
        let rig = EngineRig()
        rig.scan([rig.session(.waitingForYou)])
        rig.tick(afterMinutes: 5)
        rig.scan([rig.session(.turnDone)])
        rig.scan([rig.session(.waitingForYou)])
        rig.tick(afterMinutes: 5)
        #expect(rig.notifier.posted.map(\.title) == ["Your turn", "Still waiting", "Your turn", "Still waiting"])
    }

    @Test func screenLightsOncePerEpisodeWhenAwayWithTheLidOpen() {
        let rig = EngineRig()
        rig.system.isAway = true
        rig.scan([rig.session(.waitingForYou)])
        rig.scan([rig.session(.waitingForYou)])
        #expect(rig.system.wakeScreenCalls == 1)
        rig.scan([rig.session(.working)])
        rig.scan([rig.session(.waitingForYou)])
        #expect(rig.system.wakeScreenCalls == 2)
    }

    @Test func screenStaysDarkWhenPresentLidClosedOrSettingOff() {
        let present = EngineRig()
        present.scan([present.session(.waitingForYou)])
        #expect(present.system.wakeScreenCalls == 0)

        let closed = EngineRig()
        closed.system.isAway = true
        closed.system.lidClosed = true
        closed.scan([closed.session(.waitingForYou)])
        #expect(closed.system.wakeScreenCalls == 0)

        let off = EngineRig { $0.wakeScreenWhenWaiting = false }
        off.system.isAway = true
        off.scan([off.session(.waitingForYou)])
        #expect(off.system.wakeScreenCalls == 0)
    }

    /// Clock starts at 08:00 UTC; quiet hours 22 to 7 wrap past midnight.
    @Test(arguments: [
        (0.0, 1), (13.0, 1), (14.0, 0), (15.0, 0), (16.0, 0), (22.0, 0), (22.9, 0), (23.0, 1),
    ] as [(Double, Int)])
    func quietHoursWrapPastMidnight(hoursLater: Double, expectedCalls: Int) {
        let rig = EngineRig()
        rig.clock.advance(hoursLater * 3_600)
        rig.system.isAway = true
        rig.scan([rig.session(.waitingForYou)])
        #expect(rig.system.wakeScreenCalls == expectedCalls)
    }

    @Test func quietHoursInsideTheSameDay() {
        let rig = EngineRig { $0.quietHoursStart = 7; $0.quietHoursEnd = 9 }
        rig.system.isAway = true
        rig.scan([rig.session(.waitingForYou)])
        #expect(rig.system.wakeScreenCalls == 0)
    }

    @Test func equalQuietHoursMeanNone() {
        let rig = EngineRig { $0.quietHoursStart = 8; $0.quietHoursEnd = 8 }
        rig.system.isAway = true
        rig.scan([rig.session(.waitingForYou)])
        #expect(rig.system.wakeScreenCalls == 1)
    }

    @Test func screenLightsEvenWhenNotificationsAreOff() {
        let rig = EngineRig { $0.notifications = false }
        rig.system.isAway = true
        rig.scan([rig.session(.waitingForYou)])
        #expect(rig.system.wakeScreenCalls == 1)
        #expect(rig.notifier.posted.isEmpty)
    }
}

@MainActor
struct EngineStallTests {
    private func stalled(_ rig: EngineRig, agent: String = "Codex") -> AgentSession {
        var session = rig.session(.stalled, agent: agent)
        session.lastSignOfLife = rig.clock.date.addingTimeInterval(-600)
        return session
    }

    @Test func notifiesOncePerStall() {
        let rig = EngineRig()
        rig.scan([stalled(rig)], working: false)
        rig.scan([stalled(rig)], working: false)
        #expect(rig.notifier.posted.map(\.body) == ["Codex in api looks stuck, no activity for 10 min"])
        rig.scan([rig.session(.working, agent: "Codex")])
        rig.scan([stalled(rig)], working: false)
        #expect(rig.notifier.posted.count == 2)
    }

    @Test func silentWithTheWatchdogOff() {
        let rig = EngineRig { $0.stallWatchdog = false }
        rig.scan([stalled(rig)], working: false)
        #expect(rig.notifier.posted.isEmpty)
    }
}

@MainActor
struct EngineReceiptTests {
    private func finishedLine(_ rig: EngineRig) -> ReceiptLine {
        ReceiptLine(agent: "Claude Code", folder: "api", outcome: .finished(at: rig.clock.date, afterSeconds: 600))
    }

    @Test func receiptOnReturnIsSavedShownAndNotified() {
        let rig = EngineRig()
        rig.system.send(.awayStarted)
        #expect(rig.state.isAway)
        rig.advance(minutes: 30)
        rig.journal.nextReceipt = rig.receipt(lines: [finishedLine(rig)], batteryStart: 84, batteryEnd: 61)
        rig.system.send(.awayEnded)
        #expect(!rig.state.isAway)
        #expect(rig.journal.saved.count == 1)
        #expect(rig.state.latestReceipt == rig.journal.saved.first)
        #expect(rig.state.receipts == rig.journal.saved)
        #expect(rig.notifier.posted.map(\.body) == ["Away 30 min: 1 turn done in 1 project, battery 84% to 61%"])
        #expect(rig.notifier.posted.first?.title == "While you were away")
        #expect(rig.journal.receiptWindows.first?.from == EngineFakes.Clock.start)
        #expect(rig.journal.kinds.contains(.awayStarted))
        #expect(rig.journal.kinds.contains(.awayEnded))
    }

    @Test func tooShortAwayMakesNoReceipt() {
        let rig = EngineRig()
        rig.system.send(.awayStarted)
        rig.advance(minutes: 19)
        rig.journal.nextReceipt = rig.receipt(lines: [finishedLine(rig)])
        rig.system.send(.awayEnded)
        #expect(rig.journal.receiptWindows.isEmpty)
        #expect(rig.state.latestReceipt == nil)
        #expect(rig.notifier.posted.isEmpty)
    }

    @Test func minimumAwayFollowsTheSetting() {
        let rig = EngineRig { $0.receiptMinAwayMinutes = 60 }
        rig.system.send(.awayStarted)
        rig.advance(minutes: 59)
        rig.journal.nextReceipt = rig.receipt(lines: [finishedLine(rig)])
        rig.system.send(.awayEnded)
        #expect(rig.journal.saved.isEmpty)
    }

    @Test func nothingHappenedMeansNoReceiptAndNoNotification() {
        let rig = EngineRig()
        rig.system.send(.awayStarted)
        rig.advance(minutes: 120)
        rig.system.send(.awayEnded)
        #expect(rig.journal.saved.isEmpty)
        #expect(rig.state.latestReceipt == nil)
        #expect(rig.notifier.posted.isEmpty)
    }

    @Test func projectNamesAreHiddenWhenTheSettingIsOff() {
        let rig = EngineRig { $0.showProjectNames = false }
        rig.system.send(.awayStarted)
        rig.advance(minutes: 30)
        rig.journal.nextReceipt = rig.receipt(lines: [finishedLine(rig)])
        rig.system.send(.awayEnded)
        #expect(rig.journal.saved.first?.lines.first?.folder == nil)
    }

    @Test func crashNoteAtLaunchGoesIntoTheNextReceiptOnly() {
        let rig = EngineRig(started: false)
        let crashedAt = EngineFakes.Clock.start.addingTimeInterval(-7_200)
        rig.journal.previous = (crashedAt, false)
        rig.model.start()
        rig.system.send(.awayStarted)
        rig.advance(minutes: 30)
        rig.system.send(.awayEnded)
        #expect(rig.journal.saved.count == 1)
        #expect(rig.journal.saved.first?.notRunningSince == crashedAt)
        #expect(rig.notifier.posted.first?.body.contains("MacBull was not running") == true)

        rig.system.send(.awayStarted)
        rig.advance(minutes: 30)
        rig.system.send(.awayEnded)
        #expect(rig.journal.saved.count == 1)
    }

    @Test func cleanQuitLeavesNoCrashNote() {
        let rig = EngineRig(started: false)
        rig.journal.previous = (EngineFakes.Clock.start.addingTimeInterval(-60), true)
        rig.model.start()
        rig.system.send(.awayStarted)
        rig.advance(minutes: 30)
        rig.system.send(.awayEnded)
        #expect(rig.journal.saved.isEmpty)
    }

    @Test func awayAtLaunchStartsAWindow() {
        let rig = EngineRig(started: false)
        rig.system.isAway = true
        rig.model.start()
        #expect(rig.state.isAway)
        #expect(rig.journal.kinds.contains(.awayStarted))
    }

    @Test func duplicateAwayStartKeepsTheFirstTime() {
        let rig = EngineRig()
        rig.system.send(.awayStarted)
        rig.advance(minutes: 15)
        rig.system.send(.awayStarted)
        rig.advance(minutes: 10)
        rig.journal.nextReceipt = rig.receipt(lines: [finishedLine(rig)])
        rig.system.send(.awayEnded)
        #expect(rig.journal.saved.count == 1)
        #expect(rig.journal.receiptWindows.first?.from == EngineFakes.Clock.start)
    }

    @Test func receiptsKeepTheLastTen() {
        let rig = EngineRig()
        for _ in 0..<12 {
            rig.system.send(.awayStarted)
            rig.advance(minutes: 30)
            rig.journal.nextReceipt = rig.receipt(lines: [finishedLine(rig)])
            rig.system.send(.awayEnded)
        }
        #expect(rig.state.receipts.count == 10)
    }

    @Test func receiptIsSavedButSilentWhenNotificationsAreOff() {
        let rig = EngineRig { $0.notifications = false }
        rig.system.send(.awayStarted)
        rig.advance(minutes: 30)
        rig.journal.nextReceipt = rig.receipt(lines: [finishedLine(rig)])
        rig.system.send(.awayEnded)
        #expect(rig.journal.saved.count == 1)
        #expect(rig.notifier.posted.isEmpty)
    }

    @Test func dismissClearsTheCardButKeepsHistory() {
        let rig = EngineRig()
        rig.system.send(.awayStarted)
        rig.advance(minutes: 30)
        rig.journal.nextReceipt = rig.receipt(lines: [finishedLine(rig)])
        rig.system.send(.awayEnded)
        rig.model.dismissReceipt()
        #expect(rig.state.latestReceipt == nil)
        #expect(rig.state.receipts.count == 1)
    }

    @Test func eraseHistoryClearsEverything() {
        let rig = EngineRig()
        rig.system.send(.awayStarted)
        rig.advance(minutes: 30)
        rig.journal.nextReceipt = rig.receipt(lines: [finishedLine(rig)])
        rig.system.send(.awayEnded)
        rig.model.eraseHistory()
        #expect(rig.journal.erased)
        #expect(rig.state.receipts.isEmpty)
        #expect(rig.state.latestReceipt == nil)
    }
}

@MainActor
struct EngineLaunchQuitAndURLTests {
    @Test func launchRestoresTheLidFirstAndJournalsTheLaunchFirst() {
        let rig = EngineRig()
        #expect(rig.lid.events.first == "restore")
        #expect(rig.journal.kinds.first == .appLaunched)
        #expect(rig.journal.prunes.count == 1)
        #expect(rig.journal.prunes.first?.keepDays == 30)
        #expect(rig.system.started)
    }

    @Test func historyIsPrunedDailyWithTheSetting() {
        let rig = EngineRig { $0.historyDays = 7 }
        rig.tick(afterMinutes: 23 * 60)
        #expect(rig.journal.prunes.count == 1)
        rig.tick(afterMinutes: 61)
        #expect(rig.journal.prunes.count == 2)
        #expect(rig.journal.prunes.last?.keepDays == 7)
    }

    @Test func savedReceiptsAreLoadedAtLaunch() {
        let rig = EngineRig(started: false)
        let old = rig.receipt(notRunningSince: EngineFakes.Clock.start)
        rig.journal.save(old)
        rig.model.start()
        #expect(rig.state.receipts == [old])
    }

    @Test func welcomeOpensOnFirstLaunchOnly() {
        let first = EngineRig(started: false) { $0.welcomeDone = false }
        first.model.start()
        #expect(first.windows.welcomeSteps == [.hello])
        let later = EngineRig()
        #expect(later.windows.welcomeSteps.isEmpty)
    }

    @Test func welcomeOpensExactlyOnceEvenIfStartIsCalledAgain() {
        let rig = EngineRig(started: false) { $0.welcomeDone = false }
        rig.model.start()
        rig.model.start()
        #expect(rig.windows.welcomeSteps == [.hello])
    }

    @Test func showPanelForwardsToThePanelUnlessItIsAlreadyOpen() {
        let rig = EngineRig()
        rig.model.showPanel()
        rig.model.showPanel()
        #expect(rig.panel.showCalls == 1)
        rig.panel.closePanel()
        rig.model.showPanel()
        #expect(rig.panel.showCalls == 2)
    }

    @Test func quitUndoesEverythingInOrder() {
        let rig = EngineRig()
        rig.model.turnOn(minutes: 30)
        rig.scan([rig.session()])
        rig.model.quit()
        #expect(rig.state.quitting)
        #expect(rig.state.manual == nil)
        #expect(!rig.state.agentHold)
        #expect(rig.agents.stopped)
        #expect(rig.power.last?.system == false)
        #expect(rig.power.last?.display == false)
        #expect(rig.lid.events.last == "cleanUp(false)")
        #expect(rig.journal.kinds.suffix(2) == [.awakeEnded(reason: "quit"), .appQuit])
        #expect(rig.terminated.count == 1)
        #expect(rig.scheduler.live.isEmpty)
    }

    @Test func quitIsIdempotent() {
        let rig = EngineRig()
        rig.model.prepareForQuit()
        rig.model.prepareForQuit()
        rig.model.quit()
        let quits = rig.journal.kinds.filter { $0 == .appQuit }
        #expect(quits.count == 1)
        #expect(rig.lid.events.filter { $0.hasPrefix("cleanUp") }.count == 1)
    }

    @Test func powerOffTellsTheLidNotToSleepTheMac() {
        let rig = EngineRig()
        rig.system.send(.powerOff)
        rig.model.prepareForQuit()
        #expect(rig.lid.events.last == "cleanUp(true)")
    }

    @Test func eventsAfterQuitChangeNothing() {
        let rig = EngineRig()
        rig.model.prepareForQuit()
        let callsBefore = rig.power.calls.count
        rig.model.turnOn(minutes: nil)
        rig.scan([rig.session()])
        #expect(rig.power.calls.count == callsBefore)
        #expect(!rig.state.agentHold)
    }

    @Test func urlCommandsAreDispatchedInOrder() throws {
        let rig = EngineRig()
        let urls = try ["macbull://on?minutes=30", "macbull://settings?tab=away", "macbull://welcome?step=agents", "macbull://panel", "macbull://nonsense"]
            .map { try #require(URL(string: $0)) }
        rig.model.handle(urls: urls)
        #expect(rig.state.manual?.minutes == 30)
        #expect(rig.windows.settingsTabs == [.away])
        #expect(rig.windows.welcomeSteps == [.agents])
        #expect(rig.panel.showCalls == 1)
        rig.model.handle(urls: [try #require(URL(string: "macbull://panel"))])
        #expect(rig.panel.showCalls == 1)
        rig.model.handle(urls: [try #require(URL(string: "macbull://off"))])
        #expect(rig.state.manual == nil)
    }

    @Test func urlToggleAndDefaultDuration() throws {
        let rig = EngineRig { $0.defaultMinutes = 120 }
        rig.model.handle(urls: [try #require(URL(string: "macbull://on"))])
        #expect(rig.state.manual?.minutes == 120)
        rig.model.handle(urls: [try #require(URL(string: "macbull://toggle"))])
        #expect(rig.state.manual == nil)
        rig.model.handle(urls: [try #require(URL(string: "macbull://on?minutes=0"))])
        #expect(rig.state.manual?.endsAt == nil)
    }

    @Test func urlsBeforeStartWaitForIt() throws {
        let rig = EngineRig(started: false)
        rig.model.handle(urls: [try #require(URL(string: "macbull://on?minutes=15"))])
        #expect(rig.state.manual == nil)
        rig.model.start()
        #expect(rig.state.manual?.minutes == 15)
        #expect(rig.journal.kinds.first == .appLaunched)
    }

    @Test func loginItemAndBringToFrontPassThrough() {
        let rig = EngineRig()
        #expect(rig.model.loginItemStatus() == .disabled)
        #expect(rig.model.setLoginItem(true) == .enabled)
        #expect(rig.model.loginItemStatus() == .enabled)
        rig.agents.frontResult = false
        #expect(!rig.model.bringToFront(sessionID: "s1"))
        #expect(rig.agents.frontRequests == ["s1"])
    }

    @Test func statusLineChangesAreAnnounced() {
        let rig = EngineRig()
        var lines: [String] = []
        rig.model.onStatusLineChange = { lines.append($0) }
        rig.model.turnOn(minutes: 30)
        rig.tick()
        rig.tick(afterMinutes: 1)
        rig.model.turnOff()
        #expect(lines == ["Awake for 30 min more", "Awake for 29 min more", "Off, the Mac sleeps as usual"])
    }

    @Test func agentModeOffEndsTheKnownSessionsInTheJournal() {
        let rig = EngineRig()
        rig.scan([rig.session(.working, id: "a"), rig.session(.waitingForYou, id: "b")])
        rig.settings.agentMode = false
        let ended = rig.journal.kinds.filter {
            if case .sessionChanged(_, _, _, .ended) = $0 { true } else { false }
        }
        #expect(ended.count == 2)
    }

    @Test func statusLineNamesWorkingAgents() {
        let rig = EngineRig()
        rig.scan([rig.session(.working, id: "a", agent: "Claude Code"), rig.session(.working, id: "b", agent: "Codex")])
        #expect(rig.model.statusLine == "Awake while Claude Code and Codex work")
    }
}
