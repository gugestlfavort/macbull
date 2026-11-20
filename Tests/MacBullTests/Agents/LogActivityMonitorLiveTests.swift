import Foundation
import Testing
@testable import MacBull

/// Runs the real file events against a temporary home folder.
struct LogActivityMonitorLiveTests {
    private static func makeHome() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("macbull-logs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func waitForWrite(_ monitor: LogActivityMonitor, agent: String, timeout: TimeInterval) async throws -> LogFacts {
        let deadline = Date().addingTimeInterval(timeout)
        var facts = monitor.refresh(now: Date())
        while facts.lastWriteByAgent[agent] == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(250))
            facts = monitor.refresh(now: Date())
        }
        return facts
    }

    @Test func aNewLogFileWrittenAfterStartingIsSeenThroughFileEvents() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent(".claude/projects/-work-app", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let monitor = LogActivityMonitor(home: home, agents: AgentCatalogue.builtIn)
        defer { monitor.stop() }
        #expect(monitor.refresh(now: Date()).lastWriteByAgent.isEmpty)

        try Data("{}".utf8).write(to: root.appendingPathComponent("session.jsonl"))
        let facts = try await Self.waitForWrite(monitor, agent: "claude", timeout: 8)
        #expect(facts.lastWriteByAgent["claude"] != nil)
        #expect(facts.lastWriteByProject[LogFacts.projectKey(agentID: "claude", folder: "-work-app")] != nil)
        #expect(facts.projectFolders["claude"]?.contains("-work-app") == true)
    }

    @Test func aFolderThatAppearsLaterStartsBeingWatched() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let monitor = LogActivityMonitor(home: home, agents: AgentCatalogue.builtIn)
        defer { monitor.stop() }
        #expect(monitor.refresh(now: Date()) == LogFacts())

        let codex = home.appendingPathComponent(".codex/sessions/2026/11", isDirectory: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        _ = monitor.refresh(now: Date())
        try Data("{}".utf8).write(to: codex.appendingPathComponent("rollout.jsonl"))
        let facts = try await Self.waitForWrite(monitor, agent: "codex", timeout: 8)
        #expect(facts.lastWriteByAgent["codex"] != nil)
    }

    @Test func filesAlreadyThereAtStartAreTrackedButNotAWriteUntilTheyChange() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("open.jsonl")
        try Data("{}".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: file.path)

        let monitor = LogActivityMonitor(home: home, agents: AgentCatalogue.builtIn)
        defer { monitor.stop() }
        // File events can replay the file's creation just before the stream started; its modification
        // time is an hour old, so it is no recent write either way.
        let recent = { (facts: LogFacts) in facts.lastWriteByAgent["codex"].map { Date().timeIntervalSince($0) <= 90 } ?? false }
        #expect(!recent(monitor.refresh(now: Date())))

        // A long-open file: the polled modification time advances.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-5)], ofItemAtPath: file.path)
        #expect(recent(monitor.refresh(now: Date())))
    }
}
