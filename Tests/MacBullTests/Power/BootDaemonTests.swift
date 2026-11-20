import Foundation
import Testing
@testable import MacBull

struct BootDaemonTests {
    private static let tricky = [
        "/Users/jo & \"ann\"/it's <here>/Library/Application Support/MacBull/sleep-disabled",
        "/Users/jo & \"ann\"/it's <here>/Library/Application Support/MacBull/low-power-forced",
        "/Users/jo & \"ann\"/it's <here>/Library/Application Support/MacBull/held-in-bag",
    ]

    private func parse(_ plist: String) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: Data(plist.utf8), format: nil)
        return try #require(object as? [String: Any])
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func plistHasExactlyTheThreeKeys() throws {
        let dict = try parse(BootDaemon.plist(flagPaths: Self.tricky))
        #expect(Set(dict.keys) == ["Label", "ProgramArguments", "RunAtLoad"])
        #expect(dict["Label"] as? String == "app.macbull.boot-reset")
        #expect(dict["RunAtLoad"] as? Bool == true)
        #expect(dict["KeepAlive"] == nil)
    }

    @Test func programArgumentsPassFlagPathsAsPositionalParameters() throws {
        let dict = try parse(BootDaemon.plist(flagPaths: Self.tricky))
        let arguments = try #require(dict["ProgramArguments"] as? [String])
        #expect(Array(arguments.prefix(4)) == ["/bin/sh", "-c", BootDaemon.script, "macbull-boot-reset"])
        #expect(Array(arguments.dropFirst(4)) == Self.tricky)
        for path in Self.tricky { #expect(!BootDaemon.script.contains(path)) }
    }

    @Test func plistIsValidAccordingToPlutil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macbull-test-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        try BootDaemon.plist(flagPaths: Self.tricky).write(to: url, atomically: true, encoding: .utf8)
        #expect(try run("/usr/bin/plutil", ["-lint", url.path]) == 0)
    }

    @Test func xmlEscaping() {
        #expect(BootDaemon.xmlEscape("a&b<c>d\"e'f") == "a&amp;b&lt;c&gt;d&quot;e&apos;f")
        #expect(BootDaemon.xmlEscape("plain /path") == "plain /path")
    }

    @Test func scriptParses() throws {
        #expect(try run("/bin/sh", ["-n", "-c", BootDaemon.script]) == 0)
    }

    /// Only the in-bag flag exists, so no pmset call is made: the script just deletes it and exits 0.
    @Test func scriptDeletesTheInBagFlagUnconditionallyAndExitsZero() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macbull-boot-\(UUID().uuidString) x")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sleep = folder.appendingPathComponent("sleep-disabled").path
        let low = folder.appendingPathComponent("low-power-forced").path
        let bag = folder.appendingPathComponent("held-in-bag").path
        #expect(FileManager.default.createFile(atPath: bag, contents: Data()))
        let status = try run("/bin/sh", ["-c", BootDaemon.script, "macbull-boot-reset", sleep, low, bag])
        #expect(status == 0)
        #expect(!FileManager.default.fileExists(atPath: bag))
    }
}
