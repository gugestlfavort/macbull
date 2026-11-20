import Testing
@testable import MacBull

struct SudoListingTests {
    private static let ours = PmsetCommand.allCases.map(\.text).joined(separator: ", ")

    private static func listing(_ lines: String...) -> String {
        """
        Matching Defaults entries for tester on mac:
            env_reset, env_keep+="BLOCKSIZE COLORFGBG", !fqdn

        User tester may run the following commands on mac:
        \(lines.joined(separator: "\n"))
        """
    }

    private func allowed(_ listing: String) -> Bool {
        SudoListing.allowsWithoutPassword(listing)
    }

    @Test func ourRuleAloneIsAllowed() {
        #expect(allowed(Self.listing("    (root) NOPASSWD: \(Self.ours)")))
    }

    @Test func nothingListedIsNotAllowed() {
        #expect(!allowed(""))
        #expect(!allowed("Sorry, user tester may not run sudo on mac."))
        #expect(!allowed(Self.listing("")))
    }

    @Test func laterAllAllWithPasswordTakesPermissionAway() {
        let text = Self.listing("    (root) NOPASSWD: \(Self.ours)", "    (ALL) ALL")
        #expect(!allowed(text))
    }

    @Test func earlierAllAllIsOverriddenByOurLaterRule() {
        let text = Self.listing("    (ALL) ALL", "    (root) NOPASSWD: \(Self.ours)")
        #expect(allowed(text))
    }

    @Test func allAllAloneNeedsAPassword() {
        #expect(!allowed(Self.listing("    (ALL) ALL")))
        #expect(!allowed(Self.listing("    (ALL : ALL) ALL")))
    }

    @Test func continuationLinesBelongToThePreviousEntry() {
        let text = Self.listing(
            "    (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0,",
            "        /usr/bin/pmset -b lowpowermode 1,",
            "        /usr/bin/pmset -b lowpowermode 0"
        )
        #expect(allowed(text))
    }

    @Test func missingOneCommandIsNotAllowed() {
        let text = Self.listing(
            "    (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -b lowpowermode 1"
        )
        #expect(!allowed(text))
    }

    @Test func passwdTagAfterNopasswdTakesAwayLaterCommands() {
        let text = Self.listing(
            "    (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, "
                + "PASSWD: /usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset -b lowpowermode 0"
        )
        #expect(!allowed(text))
    }

    @Test func commandsBeforeNopasswdTagStillNeedAPassword() {
        let text = Self.listing(
            "    (root) /usr/bin/pmset -a disablesleep 1, NOPASSWD: /usr/bin/pmset -a disablesleep 0, "
                + "/usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset -b lowpowermode 0"
        )
        #expect(!allowed(text))
    }

    @Test func nopasswdAppliesToAllLaterCommandsInTheEntry() {
        let text = Self.listing(
            "    (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, "
                + "/usr/bin/pmset -b lowpowermode 1, /usr/bin/pmset -b lowpowermode 0"
        )
        #expect(allowed(text))
    }

    @Test func stackedTagsAreRead() {
        #expect(allowed(Self.listing("    (root) SETENV: NOPASSWD: \(Self.ours)")))
    }

    @Test func bareProgramMeansAnyArguments() {
        #expect(allowed(Self.listing("    (root) NOPASSWD: /usr/bin/pmset")))
    }

    @Test func allWithNopasswdIsAllowed() {
        #expect(allowed(Self.listing("    (ALL) NOPASSWD: ALL")))
        #expect(allowed(Self.listing("    (ALL : ALL) NOPASSWD: ALL")))
        #expect(allowed(Self.listing("    (root : wheel) NOPASSWD: ALL")))
    }

    @Test func trailingWildcardCoversCommandsThatStartWithThePrefix() {
        #expect(allowed(Self.listing("    (root) NOPASSWD: /usr/bin/pmset *")))
        #expect(allowed(Self.listing("    (root) NOPASSWD: /usr/bin/pmset*")))
        #expect(allowed(Self.listing("    (root) NOPASSWD: /usr/bin/pmset -a *, /usr/bin/pmset -b *")))
    }

    @Test func wildcardForOnlyOneProfileIsNotEnough() {
        #expect(!allowed(Self.listing("    (root) NOPASSWD: /usr/bin/pmset -a *")))
        #expect(!allowed(Self.listing("    (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1*")))
    }

    @Test func otherProgramsDoNotCount() {
        #expect(!allowed(Self.listing("    (root) NOPASSWD: /usr/bin/pmsetx *")))
        #expect(!allowed(Self.listing("    (root) NOPASSWD: /sbin/shutdown")))
    }

    @Test func onlyRootOrAllRunAsEntriesCount() {
        #expect(!allowed(Self.listing("    (operator) NOPASSWD: \(Self.ours)")))
        #expect(!allowed(Self.listing("    (operator) NOPASSWD: ALL")))
        #expect(allowed(Self.listing("    (root, operator) NOPASSWD: \(Self.ours)")))
    }

    @Test func laterPasswordEntryForRootOverridesAnEarlierWildcard() {
        let text = Self.listing("    (ALL) NOPASSWD: ALL", "    (root) PASSWD: ALL")
        #expect(!allowed(text))
    }

    @Test func negatedRuleDenies() {
        let text = Self.listing("    (root) NOPASSWD: ALL, !/usr/bin/pmset")
        #expect(!allowed(text))
    }

    @Test func extraWhitespaceInCommandsIsIgnored() {
        let text = Self.listing("    (root) NOPASSWD: /usr/bin/pmset   -a  disablesleep 1, \(PmsetCommand.holdOff.text), \(PmsetCommand.lowPowerOn.text), \(PmsetCommand.lowPowerOff.text)")
        #expect(allowed(text))
    }

    @Test func defaultsLinesAndHeadersAreNotEntries() {
        let entries = SudoListing.entries(in: Self.listing("    (root) NOPASSWD: ALL"))
        #expect(entries.count == 1)
        #expect(entries.first?.runAs == "root")
    }

    @Test func entriesKeepOrderAndBodies() {
        let entries = SudoListing.entries(in: Self.listing("    (root) NOPASSWD: /bin/a,", "        /bin/b", "    (ALL) ALL"))
        #expect(entries.map(\.runAs) == ["root", "ALL"])
        #expect(entries.first?.body == "NOPASSWD: /bin/a, /bin/b")
    }

    @Test func escapedCommasStayInsideOneCommand() {
        let rules = SudoListing.rules(inBody: "NOPASSWD: /bin/echo a\\,b, /bin/true")
        #expect(rules.map(\.command) == ["/bin/echo a\\,b", "/bin/true"])
    }
}
