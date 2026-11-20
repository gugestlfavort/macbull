import Foundation
import Testing
@testable import MacBull

struct LidRulesTests {
    @Test func validAccountNames() {
        for name in ["sam", "Sam.Rivera", "dev_user", "a-b", "user01", "x"] {
            #expect(AccountName.isValid(name), "\(name)")
        }
    }

    @Test func invalidAccountNames() {
        for name in ["", "john doe", "o'brien", "a;b", "a,b", "a=b", "user$", "a/b", "ünal", "a\nb", "a:b", "#1", "a\\b"] {
            #expect(!AccountName.isValid(name), "\(name)")
        }
    }

    @Test func sudoersRuleIsOneExactLine() {
        let expected = "tester ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, "
            + "/usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset -b lowpowermode 0"
        #expect(SudoRule.text(forAccount: "tester") == expected)
        #expect(!SudoRule.text(forAccount: "tester").contains("\n"))
    }

    @Test func ourRuleIsRecognisedByOurParser() {
        let rule = SudoRule.text(forAccount: "tester")
        let body = String(rule.dropFirst("tester ALL=".count))
        let listing = "User tester may run the following commands on mac:\n    \(body)"
        #expect(SudoListing.allowsWithoutPassword(listing))
    }

    @Test func commandArguments() {
        #expect(PmsetCommand.holdOn.sudoArguments == ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"])
        #expect(PmsetCommand.holdOff.text == "/usr/bin/pmset -a disablesleep 0")
        #expect(PmsetCommand.lowPowerOn.text == "/usr/bin/pmset -b lowpowermode 1")
        #expect(PmsetCommand.lowPowerOff.sudoArguments.first == "-n")
    }

    @Test func retryDelaysFollowTheSpec() {
        #expect(LidRetry.enable == 60)
        #expect(LidRetry.disable == 15)
        #expect(LidRetry.lowPower == 60)
    }

    @Test func retryClockBlocksUntilTheDelayPasses() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var clock = RetryClock()
        #expect(clock.canAttempt(at: start))
        clock.failed(at: start, retryAfter: 15)
        #expect(!clock.canAttempt(at: start.addingTimeInterval(14.9)))
        #expect(clock.canAttempt(at: start.addingTimeInterval(15)))
        clock.reset()
        #expect(clock.canAttempt(at: start))
    }

    @Test func retryClocksAreIndependent() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var sleep = RetryClock()
        let lowPower = RetryClock()
        sleep.failed(at: start, retryAfter: LidRetry.enable)
        #expect(lowPower.canAttempt(at: start))
    }

    @Test func percentIsIntegerDivision() {
        #expect(PowerSourceReader.percent(current: 83, maximum: 100) == 83)
        #expect(PowerSourceReader.percent(current: 2999, maximum: 6000) == 49)
        #expect(PowerSourceReader.percent(current: 0, maximum: 100) == 0)
        #expect(PowerSourceReader.percent(current: 5, maximum: 0) == nil)
    }
}
