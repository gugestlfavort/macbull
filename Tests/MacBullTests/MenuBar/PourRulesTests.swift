import CoreGraphics
import Testing
@testable import MacBull

struct PourRulesTests {
    private static let steps = PourRules.steps

    // MARK: - Level from remaining time (ported from the reference)

    @Test func nineStopsEightSteps() {
        #expect(PourStop.allCases.count == 9)
        #expect(Self.steps == 8)
    }

    @Test func stopsSitOnTheirOwnIndex() {
        #expect(PourRules.level(forRemainingMinutes: 60) == 3 / Self.steps)
        #expect(PourRules.level(forRemainingMinutes: 15) == 1 / Self.steps)
        #expect(PourRules.level(forRemainingMinutes: 480) == 7 / Self.steps)
    }

    @Test func betweenStopsIsInterpolated() {
        let level = PourRules.level(forRemainingMinutes: 45)
        #expect(level > 2 / Self.steps && level < 3 / Self.steps)
        #expect(abs(level - 2.5 / Self.steps) < 1e-9)
    }

    @Test func belowTheFirstStopRunsDownToEmpty() {
        #expect(abs(PourRules.level(forRemainingMinutes: 7.5) - 0.5 / Self.steps) < 1e-9)
    }

    @Test func nothingLeftIsEmpty() {
        #expect(PourRules.level(forRemainingMinutes: 0) == 0)
        #expect(PourRules.level(forRemainingMinutes: -3) == 0)
    }

    @Test func pastTheLastNumericStopStaysBelowTheTop() {
        #expect(PourRules.level(forRemainingMinutes: 600) == 7 / Self.steps)
        #expect(PourRules.level(forRemainingMinutes: 600) < 1)
    }

    // MARK: - Stops and minutes

    @Test func stopMinutesFollowTheTable() {
        #expect(PourStop.allCases.map(\.minutes) == [nil, 15, 30, 60, 120, 180, 300, 480, 0])
        #expect(PourStop.allCases.map(\.label) == ["Off", "15m", "30m", "1h", "2h", "3h", "5h", "8h", "\u{221E}"])
    }

    @Test func levelOfAStopIsItsIndexOverEight() {
        #expect(PourRules.level(for: .off) == 0)
        #expect(PourRules.level(for: .h1) == 3 / Self.steps)
        #expect(PourRules.level(for: .untilOff) == 1)
    }

    // MARK: - Drag position

    @Test func pointerHeightPicksTheNearestStop() {
        let height: CGFloat = 150
        // 8% from the top is the fullest stop, 92% the empty one
        #expect(PourRules.stop(atY: 0.08 * height, height: height) == .untilOff)
        #expect(PourRules.stop(atY: 0.92 * height, height: height) == .off)
        #expect(PourRules.stop(atY: 0.5 * height, height: height) == .h2)
    }

    @Test func pointerOutsideTheRangeClampsToTheEnds() {
        #expect(PourRules.stop(atY: -40, height: 150) == .untilOff)
        #expect(PourRules.stop(atY: 400, height: 150) == .off)
    }

    @Test func pointerStepsAreEvenlySpaced() {
        let height: CGFloat = 200
        let span = (PourRules.rangeBottom - PourRules.rangeTop) * height
        for stop in PourStop.allCases {
            let fromTop = 1 - CGFloat(stop.rawValue) / 8
            let y = PourRules.rangeTop * height + fromTop * span
            #expect(PourRules.stop(atY: y, height: height) == stop)
        }
    }

    @Test func zeroHeightIsOff() {
        #expect(PourRules.stop(atY: 10, height: 0) == .off)
    }

    // MARK: - Pour table

    @Test func pourAtOffIsAHint() {
        #expect(PourRules.pour(stop: .off, previous: .h2) == 0.1)
        #expect(PourRules.pour(stop: .off, previous: nil) == 0.1)
    }

    @Test func pourEasesBackWhenTheLevelGoesDown() {
        #expect(PourRules.pour(stop: .h1, previous: .h5) == 0.2)
    }

    @Test func pourGrowsWithTheStopWhenGoingUpOrFirst() {
        #expect(PourRules.pour(stop: .h1, previous: .m15) == 0.35 + 0.65 * 3 / 8)
        #expect(PourRules.pour(stop: .untilOff, previous: nil) == 1)
        #expect(PourRules.pour(stop: .m15, previous: nil) == 0.35 + 0.65 / 8)
    }

    // MARK: - Accessibility

    @Test func currentStopIsOffWhenNotRunning() {
        #expect(PourRules.currentStop(manual: nil) == .off)
    }

    @Test func currentStopMatchesARunningDuration() {
        func stop(_ minutes: Int) -> PourStop {
            PourRules.currentStop(manual: ManualSession(minutes: minutes, startedAt: .distantPast, endsAt: nil))
        }
        #expect(stop(60) == .h1)
        #expect(stop(480) == .h8)
        #expect(stop(0) == .untilOff)
        #expect(stop(45) == .off, "a duration that is not a stop, such as 45 minutes from a URL")
    }

    @Test func steppingMovesOneStopAndStopsAtTheEnds() {
        #expect(PourRules.stepped(.h1, by: 1) == .h2)
        #expect(PourRules.stepped(.h1, by: -1) == .m30)
        #expect(PourRules.stepped(.untilOff, by: 1) == .untilOff)
        #expect(PourRules.stepped(.off, by: -1) == .off)
    }

    @Test func quickPicksAreTheSixOnTheSpec() {
        #expect(QuickPick.all.map(\.label) == ["15m", "30m", "1h", "2h", "5h", "\u{221E}"])
        #expect(QuickPick.all.map(\.minutes) == [15, 30, 60, 120, 300, 0])
        #expect(QuickPick.all.allSatisfy { !$0.spokenName.isEmpty })
    }
}
