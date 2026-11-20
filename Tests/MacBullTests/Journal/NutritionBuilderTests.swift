import Foundation
import Testing

@testable import MacBull

struct NutritionBuilderTests {
    private typealias Fix = JournalFixtures

    private func stats(
        _ events: [JournalEvent], _ range: StatsRange, now: Date, rollups: JournalRollups = JournalRollups()
    ) -> NutritionStats {
        NutritionBuilder.stats(events: events, rollups: rollups, range: range, now: now, calendar: Fix.calendar)
    }

    private let now = JournalFixtures.date(11, 19, 12)

    @Test func emptyJournalGivesEmptyLabel() {
        for range in StatsRange.allCases {
            #expect(stats([], range, now: now) == .empty)
        }
    }

    @Test func todayWeekAndAllTimeSplitByCalendarDay() {
        let events = [
            // 13 days ago: only in all time.
            Fix.event(Fix.date(11, 6, 10), .awakeStarted(reason: "manual")),
            Fix.event(Fix.date(11, 6, 11), .awakeEnded(reason: "user")),
            // 6 days ago: the first day of the week (today and the six before).
            Fix.event(Fix.date(11, 13, 10), .awakeStarted(reason: "manual")),
            Fix.event(Fix.date(11, 13, 12), .awakeEnded(reason: "user")),
            // 7 days ago: not in the week.
            Fix.event(Fix.date(11, 12, 23, 0), .awakeStarted(reason: "manual")),
            Fix.event(Fix.date(11, 12, 23, 30), .awakeEnded(reason: "user")),
            // Today.
            Fix.event(Fix.date(11, 19, 9), .awakeStarted(reason: "agents")),
            Fix.event(Fix.date(11, 19, 10), .awakeEnded(reason: "agentsDone")),
        ]
        let today = stats(events, .today, now: now)
        #expect(today.cansOpened == 1)
        #expect(today.awakeSeconds == 3600)
        let week = stats(events, .week, now: now)
        #expect(week.cansOpened == 2)
        #expect(week.awakeSeconds == 3 * 3600)
        #expect(week.longestRunSeconds == 2 * 3600)
        let all = stats(events, .allTime, now: now)
        #expect(all.cansOpened == 4)
        #expect(all.awakeSeconds == 3600 + 7200 + 1800 + 3600)
    }

    @Test func timeAsleepIsNotAwakeTime() {
        let events = [
            Fix.event(Fix.date(11, 18, 22), .awakeStarted(reason: "manual")),
            Fix.event(Fix.date(11, 18, 23), .macSlept),
            Fix.event(Fix.date(11, 19, 1), .macWoke),
            Fix.event(Fix.date(11, 19, 6), .awakeEnded(reason: "timer")),
        ]
        let today = stats(events, .today, now: now)
        #expect(today.awakeSeconds == 5 * 3600)
        #expect(today.longestRunSeconds == 5 * 3600)
        #expect(today.cansOpened == 0)
        let week = stats(events, .week, now: now)
        #expect(week.awakeSeconds == 6 * 3600)
        #expect(week.longestRunSeconds == 5 * 3600)
        #expect(week.cansOpened == 1)
    }

    @Test func parallelAgentsAddUpAndFormTheMix() {
        let events = [
            Fix.session(Fix.date(11, 19, 10), "a", .working, agent: "Claude Code"),
            Fix.session(Fix.date(11, 19, 10), "b", .working, agent: "Codex"),
            Fix.session(Fix.date(11, 19, 10, 30), "c", .running, agent: "Aider"),
            Fix.session(Fix.date(11, 19, 11), "a", .turnDone, agent: "Claude Code"),
            Fix.session(Fix.date(11, 19, 11), "b", .idle, agent: "Codex"),
            Fix.session(Fix.date(11, 19, 11), "c", .ended, agent: "Aider"),
        ]
        let today = stats(events, .today, now: now)
        #expect(today.agentSeconds == 3600 + 3600 + 1800)
        #expect(today.agentMix.map(\.agent) == ["Claude Code", "Codex", "Aider"])
        #expect(abs(today.agentMix[0].share - 0.4) < 1e-9)
        #expect(abs(today.agentMix[2].share - 0.2) < 1e-9)
        #expect(today.sessionsFinished == 3)
        #expect(today.emptiesToday == 3)
    }

    @Test func waitingEpisodesGiveTotalAndMedian() {
        let events = [
            Fix.session(Fix.date(11, 19, 9, 0), "a", .working),
            Fix.session(Fix.date(11, 19, 9, 10), "a", .waitingForYou),
            Fix.session(Fix.date(11, 19, 9, 20), "a", .working),
            Fix.session(Fix.date(11, 19, 10, 0), "a", .waitingForYou),
            Fix.session(Fix.date(11, 19, 10, 20), "a", .working),
            Fix.session(Fix.date(11, 19, 11, 0), "b", .waitingForYou, agent: "Codex"),
            Fix.session(Fix.date(11, 19, 11, 50), "b", .ended, agent: "Codex"),
        ]
        let today = stats(events, .today, now: now)
        #expect(today.waitedForYouSeconds == 600 + 1200 + 3000)
        #expect(today.waitedForYouMedianSeconds == 1200)
        // A wait that is still going runs to now.
        let open = events + [Fix.session(Fix.date(11, 19, 11, 55), "c", .waitingForYou)]
        #expect(stats(open, .today, now: now).waitedForYouSeconds == 4800 + 300)
    }

    @Test func finishedSessionsAndEmptiesToday() {
        let events = [
            Fix.session(Fix.date(11, 18, 10), "y", .working),
            Fix.session(Fix.date(11, 18, 11), "y", .turnDone),
            Fix.session(Fix.date(11, 19, 10), "t", .working),
            Fix.session(Fix.date(11, 19, 11), "t", .turnDone),
            Fix.session(Fix.date(11, 19, 11, 30), "u", .working),
        ]
        #expect(stats(events, .today, now: now).sessionsFinished == 1)
        #expect(stats(events, .today, now: now).emptiesToday == 1)
        #expect(stats(events, .week, now: now).sessionsFinished == 2)
        #expect(stats(events, .week, now: now).emptiesToday == 1)
    }

    @Test func batterySpentCountsOnlyDropsOnBatteryWhileAway() {
        let events = [
            Fix.event(Fix.date(11, 19, 8), .battery(percent: 90, onAC: false)),
            Fix.event(Fix.date(11, 19, 8, 30), .battery(percent: 85, onAC: false)),
            Fix.event(Fix.date(11, 19, 9), .awayStarted),
            Fix.event(Fix.date(11, 19, 9, 30), .battery(percent: 80, onAC: false)),
            Fix.event(Fix.date(11, 19, 10), .battery(percent: 74, onAC: false)),
            Fix.event(Fix.date(11, 19, 10, 30), .battery(percent: 76, onAC: true)),
            Fix.event(Fix.date(11, 19, 10, 40), .battery(percent: 70, onAC: false)),
            Fix.event(Fix.date(11, 19, 11), .awayEnded),
            Fix.event(Fix.date(11, 19, 11, 30), .battery(percent: 60, onAC: false)),
            Fix.event(Fix.date(11, 19, 11, 40), .safetyStop(.battery)),
            Fix.event(Fix.date(11, 19, 11, 41), .safetyStop(.heat)),
        ]
        let today = stats(events, .today, now: now)
        // 85 to 80 and 80 to 74. The step onto AC and the step off it do not count.
        #expect(today.batterySpentAway == 11)
        #expect(today.safetyStops == 2)
    }

    @Test func anOpenIntervalRunsToNow() {
        let events = [
            Fix.event(Fix.date(11, 19, 10), .awakeStarted(reason: "manual")),
            Fix.session(Fix.date(11, 19, 10, 30), "a", .working),
        ]
        let today = stats(events, .today, now: now)
        #expect(today.awakeSeconds == 2 * 3600)
        #expect(today.longestRunSeconds == 2 * 3600)
        #expect(today.agentSeconds == 90 * 60)
    }

    @Test func aCrashClosesWhatWasOpen() {
        let events = [
            Fix.event(Fix.date(11, 19, 8), .appLaunched),
            Fix.event(Fix.date(11, 19, 10), .awakeStarted(reason: "agents")),
            Fix.session(Fix.date(11, 19, 10, 0), "a", .working),
            Fix.event(Fix.date(11, 19, 10, 30), .battery(percent: 50, onAC: false)),
            // No quit, no end: the Mac lost power.
            Fix.event(Fix.date(11, 19, 11, 0), .appLaunched),
            Fix.event(Fix.date(11, 19, 11, 5), .awakeStarted(reason: "manual")),
        ]
        let today = stats(events, .today, now: now)
        #expect(today.awakeSeconds == 30 * 60 + 55 * 60)
        #expect(today.longestRunSeconds == 55 * 60)
        #expect(today.agentSeconds == 30 * 60)
        #expect(today.cansOpened == 2)
        #expect(today.sessionsFinished == 0)
    }

    @Test func aCleanQuitClosesWhatWasOpen() {
        let events = [
            Fix.event(Fix.date(11, 19, 10), .awakeStarted(reason: "manual")),
            Fix.event(Fix.date(11, 19, 10, 40), .appQuit),
            Fix.event(Fix.date(11, 19, 11, 0), .appLaunched),
        ]
        #expect(stats(events, .today, now: now).awakeSeconds == 40 * 60)
    }

    @Test func springForwardNightIsOneHourShort() {
        // Europe/Zurich, 29 March 2026: 02:00 jumps to 03:00, the day has 23 hours.
        let events = [
            Fix.event(Fix.date(3, 28, 22), .awakeStarted(reason: "agents")),
            Fix.session(Fix.date(3, 28, 22), "a", .working),
            Fix.session(Fix.date(3, 29, 8), "a", .turnDone),
            Fix.event(Fix.date(3, 29, 8), .awakeEnded(reason: "agentsDone")),
        ]
        let noon = Fix.date(3, 29, 12)
        let today = stats(events, .today, now: noon)
        #expect(today.awakeSeconds == 7 * 3600)
        #expect(today.agentSeconds == 7 * 3600)
        #expect(today.cansOpened == 0)
        let week = stats(events, .week, now: noon)
        #expect(week.awakeSeconds == 9 * 3600)
        #expect(week.longestRunSeconds == 9 * 3600)
        #expect(week.cansOpened == 1)
        // The week reaches back to 23 March.
        let older = events + [
            Fix.event(Fix.date(3, 23, 9), .awakeStarted(reason: "manual")),
            Fix.event(Fix.date(3, 23, 10), .awakeEnded(reason: "user")),
            Fix.event(Fix.date(3, 22, 9), .awakeStarted(reason: "manual")),
            Fix.event(Fix.date(3, 22, 10), .awakeEnded(reason: "user")),
        ]
        #expect(stats(older, .week, now: noon).cansOpened == 2)
    }

    @Test func fallBackNightIsOneHourLong() {
        // 25 October 2026: 03:00 falls back to 02:00, the day has 25 hours.
        let events = [
            Fix.event(Fix.date(10, 24, 22), .awakeStarted(reason: "manual")),
            Fix.event(Fix.date(10, 25, 8), .awakeEnded(reason: "user")),
        ]
        let noon = Fix.date(10, 25, 12)
        #expect(stats(events, .today, now: noon).awakeSeconds == 9 * 3600)
        #expect(stats(events, .week, now: noon).awakeSeconds == 11 * 3600)
    }

    @Test func allTimeAddsRollupsToTheRetainedEvents() {
        let folded = DayRollup(
            start: Fix.date(11, 8, 0), day: "2026-11-08",
            usage: JournalUsage(
                cansOpened: 2, awakeSeconds: 7200, agentSecondsByAgent: ["Claude Code": 3600, "Codex": 3600],
                longestRunSeconds: 20000, sessionsFinished: 3, waitedSeconds: 900, waits: [300, 600],
                batterySpentAway: 7, safetyStops: 1))
        let carried = [Fix.event(Fix.date(11, 9, 22), .awakeStarted(reason: "carried"))]
        let rollups = JournalRollups(coveredUntil: Fix.date(11, 10, 0), carry: carried, days: [folded])
        let events = [
            // The tail of an interval that began before the cut (carried in the rollups).
            Fix.event(Fix.date(11, 10, 2), .awakeEnded(reason: "user")),
            Fix.event(Fix.date(11, 19, 10), .awakeStarted(reason: "manual")),
            Fix.event(Fix.date(11, 19, 11), .awakeEnded(reason: "user")),
            Fix.session(Fix.date(11, 19, 10), "a", .working, agent: "Claude Code"),
            Fix.session(Fix.date(11, 19, 10, 30), "a", .waitingForYou, agent: "Claude Code"),
            Fix.session(Fix.date(11, 19, 10, 40), "a", .turnDone, agent: "Claude Code"),
        ]
        let all = stats(events, .allTime, now: now, rollups: rollups)
        #expect(all.cansOpened == 3)
        #expect(all.awakeSeconds == 7200 + 7200 + 3600)
        #expect(all.longestRunSeconds == 20000)
        #expect(all.agentSeconds == 7200 + 1800)
        #expect(all.sessionsFinished == 4)
        #expect(all.waitedForYouSeconds == 900 + 600)
        #expect(all.waitedForYouMedianSeconds == 600)
        #expect(all.batterySpentAway == 7)
        #expect(all.safetyStops == 1)
        #expect(all.agentMix.first?.agent == "Claude Code")

        let today = stats(events, .today, now: now, rollups: rollups)
        #expect(today.cansOpened == 1)
        #expect(today.sessionsFinished == 1)
        #expect(today.safetyStops == 0)
    }

    @Test func medianOfEvenAndOddLists() {
        #expect(NutritionBuilder.median([]) == 0)
        #expect(NutritionBuilder.median([5]) == 5)
        #expect(NutritionBuilder.median([9, 1, 5]) == 5)
        #expect(NutritionBuilder.median([4, 1, 3, 2]) == 2.5)
    }

    @Test func dayNamesRoundTrip() {
        let day = Fix.date(3, 29, 15)
        #expect(JournalDayName.name(for: day, calendar: Fix.calendar) == "2026-03-29")
        #expect(JournalDayName.date(from: "2026-03-29", calendar: Fix.calendar) == Fix.date(3, 29, 0))
        #expect(JournalDayName.date(from: "2026-02-30", calendar: Fix.calendar) == nil)
        #expect(JournalDayName.date(from: "rollups", calendar: Fix.calendar) == nil)
    }
}
