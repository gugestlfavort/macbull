import Foundation
import Testing
@testable import MacBull

struct ProcessArgumentsTests {
    private static func block(argc: Int32, executable: String, padding: Int = 3, argv: [String], environment: [String] = []) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc) { Array($0) }
        bytes += Array(executable.utf8) + [0] + [UInt8](repeating: 0, count: padding)
        for argument in argv { bytes += Array(argument.utf8) + [0] }
        for variable in environment { bytes += Array(variable.utf8) + [0] }
        return bytes
    }

    @Test func readsArgcStringsAfterTheExecutablePath() {
        let bytes = Self.block(argc: 3, executable: "/usr/local/bin/node", argv: ["node", "cli.js", "--x"], environment: ["HOME=/Users/x"])
        let parsed = ProcessArguments.parse(bytes)
        #expect(parsed?.executable == "/usr/local/bin/node")
        #expect(parsed?.arguments == ["node", "cli.js", "--x"])
    }

    @Test func aRewrittenTitleStopsAtTheFirstEmptyString() {
        // argc still says 3 but the argument area now holds just the title, then zeros, then the environment.
        var bytes = Self.block(argc: 3, executable: "/usr/local/bin/node", argv: ["claude"])
        bytes += [UInt8](repeating: 0, count: 12)
        bytes += Array("HOME=/Users/x".utf8) + [0] + Array("PATH=/bin".utf8) + [0]
        #expect(ProcessArguments.parse(bytes)?.arguments == ["claude"])
    }

    @Test func fewerStringsThanArgcIsFine() {
        let bytes = Self.block(argc: 5, executable: "/bin/x", argv: ["x", "a"])
        #expect(ProcessArguments.parse(bytes)?.arguments == ["x", "a"])
    }

    @Test func garbageIsRejected() {
        #expect(ProcessArguments.parse([]) == nil)
        #expect(ProcessArguments.parse([1, 0, 0]) == nil)
        #expect(ProcessArguments.parse(Self.block(argc: 0, executable: "/bin/x", argv: [])) == nil)
    }

    @Test func spacesAndUnicodeSurvive() {
        let bytes = Self.block(argc: 2, executable: "/bin/x", argv: ["x", "fix the café bug"])
        #expect(ProcessArguments.parse(bytes)?.arguments == ["x", "fix the café bug"])
    }
}
