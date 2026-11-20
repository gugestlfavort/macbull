import Testing
@testable import MacBull

struct AwayRulesTests {
    @Test func startsOnAnyLeavingEvent() {
        var rules = AwayRules()
        #expect(!rules.isAway)
        #expect(rules.left(secondsSinceInput: 0.2) == .started)
        #expect(rules.isAway)
    }

    @Test func aSecondLeavingEventDoesNotStartASecondWindow() {
        var rules = AwayRules()
        _ = rules.left(secondsSinceInput: 1)
        #expect(rules.left(secondsSinceInput: 2) == nil)
    }

    @Test func unlockOrSwitchBackEndsTheWindow() {
        var rules = AwayRules()
        _ = rules.left(secondsSinceInput: 1)
        #expect(rules.userReturned() == .ended)
        #expect(!rules.isAway)
    }

    @Test func returningWhileNotAwayDoesNothing() {
        var rules = AwayRules()
        #expect(rules.userReturned() == nil)
    }

    @Test func firstInputEndsTheWindow() {
        var rules = AwayRules()
        _ = rules.left(secondsSinceInput: 0.4)
        #expect(rules.poll(secondsSinceInput: 3.4, keepAwakeActive: false) == nil)
        #expect(rules.poll(secondsSinceInput: 6.4, keepAwakeActive: false) == nil)
        #expect(rules.poll(secondsSinceInput: 0.8, keepAwakeActive: false) == .ended)
        #expect(!rules.isAway)
    }

    @Test func aHotkeyLockIsNotMistakenForInput() {
        var rules = AwayRules()
        _ = rules.left(secondsSinceInput: 0.1)
        #expect(rules.poll(secondsSinceInput: 0.3, keepAwakeActive: false) == nil)
        #expect(rules.isAway)
    }

    @Test func jitterBelowToleranceIsNotInput() {
        var rules = AwayRules()
        _ = rules.left(secondsSinceInput: 100)
        #expect(rules.poll(secondsSinceInput: 99.8, keepAwakeActive: false) == nil)
    }

    @Test func tenIdleMinutesWhileKeepingTheMacAwakeStartAway() {
        var rules = AwayRules()
        #expect(rules.poll(secondsSinceInput: 599, keepAwakeActive: true) == nil)
        #expect(rules.poll(secondsSinceInput: 600, keepAwakeActive: true) == .started)
        #expect(rules.isAway)
    }

    @Test func idleRuleDoesNotApplyWhenMacBullIsNotHoldingTheMacAwake() {
        var rules = AwayRules()
        #expect(rules.poll(secondsSinceInput: 5000, keepAwakeActive: false) == nil)
        #expect(!rules.isAway)
    }

    @Test func idleAwayEndsAtInputAndDoesNotRestartUntilIdleAgain() {
        var rules = AwayRules()
        _ = rules.poll(secondsSinceInput: 650, keepAwakeActive: true)
        #expect(rules.poll(secondsSinceInput: 653, keepAwakeActive: true) == nil)
        #expect(rules.poll(secondsSinceInput: 1, keepAwakeActive: true) == .ended)
        #expect(rules.poll(secondsSinceInput: 4, keepAwakeActive: true) == nil)
        #expect(!rules.isAway)
    }

    @Test func lockedWindowSurvivesPollsWithoutInput() {
        var rules = AwayRules()
        _ = rules.left(secondsSinceInput: 2)
        for seconds in stride(from: 5.0, through: 3600.0, by: 300) {
            #expect(rules.poll(secondsSinceInput: seconds, keepAwakeActive: true) == nil)
        }
        #expect(rules.isAway)
        #expect(rules.userReturned() == .ended)
    }

    @Test func aNewWindowCanStartAfterOneEnded() {
        var rules = AwayRules()
        _ = rules.left(secondsSinceInput: 1)
        _ = rules.userReturned()
        #expect(rules.left(secondsSinceInput: 1) == .started)
    }
}
