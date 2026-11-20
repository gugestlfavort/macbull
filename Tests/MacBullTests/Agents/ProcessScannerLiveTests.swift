import Foundation
import Testing
@testable import MacBull

/// Reads the real process table of the machine running the tests.
struct ProcessScannerLiveTests {
    @Test func theScanSeesThisProcessWithItsNameParentStartAndArguments() throws {
        var scanner = ProcessScanner()
        // Treat this process like a runtime so its arguments are read.
        let name = ProcessInfo.processInfo.processName
        let matcher = AgentMatcher(definitions: [CustomAgentNames.definition(for: name)])
        let snapshot = scanner.scan(matcher: matcher, now: Date())
        let me = try #require(snapshot.table.entries[getpid()])
        #expect(me.parent == getppid())
        #expect(me.startTime > 0 && me.startTime <= Date().timeIntervalSince1970)
        #expect(me.cpuSeconds > 0)
        #expect(me.path != nil)
        #expect(snapshot.table.children[getppid()]?.contains(getpid()) == true)
        #expect(snapshot.table.entries.count > 20)
    }

    @Test func argumentsAreReadForMatchedProcessesAndTheDirectoryToo() throws {
        var scanner = ProcessScanner()
        let name = ProcessInfo.processInfo.processName
        let matcher = AgentMatcher(definitions: [CustomAgentNames.definition(for: name)])
        let snapshot = scanner.scan(matcher: matcher, now: Date())
        let me = try #require(snapshot.table.entries[getpid()])
        #expect(me.arguments == CommandLine.arguments || !me.arguments.isEmpty)
        #expect(snapshot.directories[getpid()] == FileManager.default.currentDirectoryPath
            || snapshot.directories[getpid()] != nil)
    }

    @Test func aChildProcessIsSeenWithItsParentAndItsArguments() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer { child.terminate() }

        var scanner = ProcessScanner()
        let matcher = AgentMatcher(definitions: [CustomAgentNames.definition(for: "sleep")])
        let snapshot = scanner.scan(matcher: matcher, now: Date())
        let entry = try #require(snapshot.table.entries[child.processIdentifier])
        #expect(entry.name == "sleep")
        #expect(entry.parent == getpid())
        #expect(entry.arguments == ["/bin/sleep", "30"] || entry.arguments == ["sleep", "30"])
        #expect(entry.path == "/bin/sleep")
        #expect(snapshot.directories[child.processIdentifier] != nil)
    }

    @Test func childrenReapedCpuIsCountedInTheParent() throws {
        var scanner = ProcessScanner()
        let matcher = AgentMatcher(definitions: [])
        let before = try #require(scanner.scan(matcher: matcher, now: Date()).table.entries[getpid()]).cpuSeconds
        // A short child that burns some CPU and exits, so its time is reaped into this process.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-c", "sum(i*i for i in range(3_000_000))"]
        try child.run()
        child.waitUntilExit()
        let after = try #require(scanner.scan(matcher: matcher, now: Date()).table.entries[getpid()]).cpuSeconds
        #expect(after - before > 0.05)
    }
}
