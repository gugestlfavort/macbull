import Foundation
import Testing
@testable import MacBull

@MainActor
struct AgentWatcherTests {
    private static func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("macbull-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private static func watcher(home: URL) -> AgentWatcher {
        AgentWatcher(home: home, interval: .milliseconds(100), tolerance: .zero)
    }

    private static func settings(_ home: URL) -> URL {
        home.appendingPathComponent(".claude/settings.json")
    }

    private static func hasHooks(_ home: URL) -> Bool {
        guard let data = try? Data(contentsOf: settings(home)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["hooks"] != nil
    }

    // MARK: Hooks switch

    @Test func turningHooksOnInstallsAndOffRemoves() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let watcher = Self.watcher(home: home)
        let paths = ClaudeHooks.Paths(home: home)

        watcher.configure(enabled: false, customAgents: [], claudeHooks: true, stallWatchdog: true)
        #expect(Self.hasHooks(home))
        #expect(FileManager.default.isExecutableFile(atPath: paths.script.path))
        #expect(watcher.hooksError == nil)

        watcher.configure(enabled: false, customAgents: [], claudeHooks: false, stallWatchdog: true)
        #expect(!Self.hasHooks(home))
        #expect(!FileManager.default.fileExists(atPath: paths.script.path))
    }

    @Test func configuringAgainWithTheSameSettingTouchesNothing() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let watcher = Self.watcher(home: home)
        watcher.configure(enabled: false, customAgents: [], claudeHooks: true, stallWatchdog: true)
        let installed = try Data(contentsOf: Self.settings(home))
        // The user edits the file by hand; an idempotent configure must not rewrite it.
        try Data("{}".utf8).write(to: Self.settings(home))
        watcher.configure(enabled: false, customAgents: [], claudeHooks: true, stallWatchdog: true)
        #expect(try Data(contentsOf: Self.settings(home)) == Data("{}".utf8))
        #expect(installed != Data("{}".utf8))
    }

    @Test func aFreshWatcherSelfHealsWhenHooksAreOn() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        Self.watcher(home: home).configure(enabled: false, customAgents: [], claudeHooks: true, stallWatchdog: false)
        try FileManager.default.removeItem(at: ClaudeHooks.Paths(home: home).script)
        let relaunched = Self.watcher(home: home)
        relaunched.configure(enabled: false, customAgents: [], claudeHooks: true, stallWatchdog: false)
        #expect(FileManager.default.isExecutableFile(atPath: ClaudeHooks.Paths(home: home).script.path))
    }

    @Test func aFirstConfigureWithHooksOffTouchesNothing() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        Self.watcher(home: home).configure(enabled: false, customAgents: [], claudeHooks: false, stallWatchdog: false)
        #expect(!FileManager.default.fileExists(atPath: Self.settings(home).path))
    }

    @Test func invalidSettingsFileGivesAMessageAndIsLeftAlone() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: Self.settings(home).deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("{ nope".utf8)
        try garbage.write(to: Self.settings(home))
        let watcher = Self.watcher(home: home)
        watcher.configure(enabled: false, customAgents: [], claudeHooks: true, stallWatchdog: true)
        #expect(watcher.hooksError?.contains("not valid JSON") == true)
        #expect(try Data(contentsOf: Self.settings(home)) == garbage)
    }

    @Test func theErrorClearsWhenAnInstallWorksLater() throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: Self.settings(home).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ nope".utf8).write(to: Self.settings(home))
        let watcher = Self.watcher(home: home)
        watcher.configure(enabled: false, customAgents: [], claudeHooks: true, stallWatchdog: true)
        #expect(watcher.hooksError != nil)
        watcher.configure(enabled: false, customAgents: [], claudeHooks: false, stallWatchdog: true)
        try Data("{}".utf8).write(to: Self.settings(home))
        watcher.configure(enabled: false, customAgents: [], claudeHooks: true, stallWatchdog: true)
        #expect(watcher.hooksError == nil)
        #expect(Self.hasHooks(home))
    }

    // MARK: Scanning

    private static func waitFor(_ condition: () -> Bool, seconds: Double = 10) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func scansDeliverResultsAndTheFirstOneIsABaseline() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let watcher = Self.watcher(home: home)
        var results: [AgentScanResult] = []
        watcher.onResult = { results.append($0) }
        watcher.configure(enabled: true, customAgents: [], claudeHooks: false, stallWatchdog: true)
        try await Self.waitFor { results.count >= 2 }
        watcher.stop()
        #expect(results.count >= 2)
        #expect(results.first?.anyWorking == false)
    }

    @Test func stoppingStopsResultsAndConfigureIsSafeToRepeat() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let watcher = Self.watcher(home: home)
        var count = 0
        watcher.onResult = { _ in count += 1 }
        for _ in 0..<3 { watcher.configure(enabled: true, customAgents: [], claudeHooks: false, stallWatchdog: true) }
        try await Self.waitFor { count >= 1 }
        watcher.configure(enabled: false, customAgents: [], claudeHooks: false, stallWatchdog: true)
        let atStop = count
        try await Task.sleep(for: .milliseconds(500))
        #expect(count == atStop)
        watcher.stop()
    }

    @Test func aResultThatFinishesAfterTurningTheModeOffIsDiscarded() async throws {
        let home = try Self.makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let watcher = AgentWatcher(home: home, interval: .seconds(60), tolerance: .zero)
        var count = 0
        watcher.onResult = { _ in count += 1 }
        watcher.configure(enabled: true, customAgents: [], claudeHooks: false, stallWatchdog: true)
        // The first scan starts at once; switch off before it can be delivered.
        watcher.configure(enabled: false, customAgents: [], claudeHooks: false, stallWatchdog: true)
        try await Task.sleep(for: .seconds(1))
        #expect(count == 0)
    }

    @Test func bringToFrontOfAnUnknownSessionIsFalse() {
        let watcher = AgentWatcher(home: FileManager.default.temporaryDirectory, interval: .seconds(60), tolerance: .zero)
        #expect(!watcher.bringToFront(sessionID: "nope"))
    }
}
