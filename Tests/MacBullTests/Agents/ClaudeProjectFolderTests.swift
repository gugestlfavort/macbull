import Foundation
import Testing
@testable import MacBull

struct ClaudeProjectFolderTests {
    @Test func everythingButAsciiLettersAndDigitsBecomesADash() {
        #expect(ClaudeProjectFolder.plainName(forDirectory: "/Users/sam/projects/MacBull") == "-Users-sam-projects-MacBull")
        #expect(
            ClaudeProjectFolder.plainName(forDirectory: "/Users/sam/Documents/Side Project (Alpha + Beta)")
                == "-Users-sam-Documents-Side-Project--Alpha---Beta-"
        )
        #expect(ClaudeProjectFolder.plainName(forDirectory: "/work/my_app.v2") == "-work-my-app-v2")
    }

    @Test func decomposedAccentsAreComposedFirst() {
        // "e" plus a combining accent is one composed unit, so one dash; decomposed it would be "e-".
        #expect(ClaudeProjectFolder.plainName(forDirectory: "/a/cafe\u{301}") == "-a-caf-")
        #expect(ClaudeProjectFolder.plainName(forDirectory: "/a/caf\u{E9}") == "-a-caf-")
    }

    @Test func eachUTF16UnitGetsItsOwnDash() {
        // Emoji are a surrogate pair: two dashes. CJK characters are one unit each.
        #expect(ClaudeProjectFolder.plainName(forDirectory: "/a/\u{1F4C1}") == "-a---")
        #expect(ClaudeProjectFolder.plainName(forDirectory: "/a/\u{65E5}\u{672C}") == "-a---")
    }

    @Test func existingFolderIsFoundByItsPlainName() {
        let existing: Set<String> = ["-Users-x-app", "-Users-x-other"]
        #expect(ClaudeProjectFolder.resolve(directory: "/Users/x/app", existing: existing) == "-Users-x-app")
        #expect(ClaudeProjectFolder.resolve(directory: "/Users/x/new", existing: existing) == nil)
    }

    @Test func namesOverTwoHundredAreMatchedByTheirFirstTwoHundredCharactersAndADash() throws {
        let directory = "/" + String(repeating: "abcdefghij/", count: 25)
        let plain = ClaudeProjectFolder.plainName(forDirectory: directory)
        #expect(plain.utf16.count > ClaudeProjectFolder.maxPlainLength)
        let truncated = String(plain.prefix(200)) + "-k3j2h1"
        let unrelated = String(plain.prefix(199)) + "x-zzzz"
        let found = ClaudeProjectFolder.resolve(directory: directory, existing: [unrelated, truncated, "-other"])
        #expect(found == truncated)
        #expect(ClaudeProjectFolder.resolve(directory: directory, existing: [unrelated]) == nil)
    }

    @Test func aShortNameIsNeverMatchedByPrefix() {
        #expect(ClaudeProjectFolder.resolve(directory: "/a/b", existing: ["-a-b-hash"]) == nil)
    }

    @Test func aLongNameThatExistsExactlyIsUsedAsIs() {
        let directory = "/" + String(repeating: "abcdefghij/", count: 25)
        let plain = ClaudeProjectFolder.plainName(forDirectory: directory)
        #expect(ClaudeProjectFolder.resolve(directory: directory, existing: [plain]) == plain)
    }
}
