import Foundation
import Testing
@testable import MacBull

struct ClaudeHooksTests {
    private static let script = "/Users/x/Library/Application Support/MacBull/claude-hook.sh"

    private static func userHook() -> [String: Any] { ["type": "command", "command": "/usr/local/bin/my-stop-hook"] }

    private static func userSettings() -> [String: Any] {
        [
            "model": "opus",
            "permissions": ["allow": ["Bash(ls:*)"], "deny": [String]()],
            "hooks": [
                "Stop": [["hooks": [userHook()]]],
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "echo pre"]]]],
                "SessionStart": [["hooks": [["type": "command", "command": "echo start"]]]],
            ],
        ]
    }

    private static func hooks(_ settings: [String: Any]) -> [String: Any] {
        settings["hooks"] as? [String: Any] ?? [:]
    }

    private static func groups(_ settings: [String: Any], _ event: String) -> [[String: Any]] {
        hooks(settings)[event] as? [[String: Any]] ?? []
    }

    private static func ourEntries(_ settings: [String: Any]) -> Int {
        hooks(settings).values
            .compactMap { $0 as? [[String: Any]] }
            .flatMap { $0 }
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .filter { ($0["command"] as? String)?.contains(script) == true }
            .count
    }

    private static func same(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        NSDictionary(dictionary: a).isEqual(to: b)
    }

    // MARK: merge and unmerge

    @Test func mergeIntoEmptyRegistersEveryEvent() throws {
        let merged = try ClaudeHooks.merge([:], scriptPath: Self.script)
        #expect(Set(Self.hooks(merged).keys) == Set(ClaudeHooks.eventNames))
        #expect(Self.ourEntries(merged) == ClaudeHooks.eventNames.count)
        #expect(Self.groups(merged, "PreToolUse")[0]["matcher"] as? String == "*")
        #expect(Self.groups(merged, "PostToolUse")[0]["matcher"] as? String == "*")
        #expect(Self.groups(merged, "Stop")[0]["matcher"] == nil)
    }

    @Test func commandQuotesThePathBecauseItHasASpace() throws {
        let merged = try ClaudeHooks.merge([:], scriptPath: Self.script)
        let entry = try #require((Self.groups(merged, "Stop")[0]["hooks"] as? [[String: Any]])?.first)
        #expect(entry["type"] as? String == "command")
        #expect(entry["command"] as? String == "'\(Self.script)'")
    }

    @Test func mergeKeepsUserKeysAndHooks() throws {
        let merged = try ClaudeHooks.merge(Self.userSettings(), scriptPath: Self.script)
        #expect(merged["model"] as? String == "opus")
        #expect(merged["permissions"] != nil)
        let stop = Self.groups(merged, "Stop")
        #expect(stop.count == 2)
        let first = (stop[0]["hooks"] as? [[String: Any]])?.first
        #expect(first?["command"] as? String == "/usr/local/bin/my-stop-hook")
        #expect(Self.groups(merged, "SessionStart").count == 1)
        #expect(Self.groups(merged, "PreToolUse").count == 2)
        #expect(Self.ourEntries(merged) == ClaudeHooks.eventNames.count)
    }

    @Test func mergeTwiceChangesNothing() throws {
        let once = try ClaudeHooks.merge(Self.userSettings(), scriptPath: Self.script)
        let twice = try ClaudeHooks.merge(once, scriptPath: Self.script)
        #expect(Self.same(once, twice))
        #expect(Self.ourEntries(twice) == ClaudeHooks.eventNames.count)
    }

    @Test func unmergeRestoresTheOriginal() throws {
        let merged = try ClaudeHooks.merge(Self.userSettings(), scriptPath: Self.script)
        let restored = try ClaudeHooks.unmerge(merged, scriptPath: Self.script)
        #expect(Self.same(restored, Self.userSettings()))
    }

    @Test func unmergeOfOnlyOursLeavesNoHooksKey() throws {
        let merged = try ClaudeHooks.merge(["model": "opus"], scriptPath: Self.script)
        let restored = try ClaudeHooks.unmerge(merged, scriptPath: Self.script)
        #expect(Self.same(restored, ["model": "opus"]))
    }

    @Test func unmergeKeepsAUserHookSharingOurGroup() throws {
        let command = ClaudeHooks.command(forScript: Self.script)
        let shared: [String: Any] = ["hooks": ["Stop": [["hooks": [Self.userHook(), ["type": "command", "command": command]]]]]]
        let cleaned = try ClaudeHooks.unmerge(shared, scriptPath: Self.script)
        let stop = Self.groups(cleaned, "Stop")
        #expect(stop.count == 1)
        #expect((stop[0]["hooks"] as? [Any])?.count == 1)
    }

    @Test func unmergeWithNothingOfOursChangesNothing() throws {
        let settings: [String: Any] = ["hooks": [String: Any](), "model": "x"]
        #expect(Self.same(try ClaudeHooks.unmerge(settings, scriptPath: Self.script), settings))
        #expect(Self.same(try ClaudeHooks.unmerge(Self.userSettings(), scriptPath: Self.script), Self.userSettings()))
    }

    @Test func wrongShapeThrows() {
        #expect(throws: ClaudeHooks.Failure.self) {
            try ClaudeHooks.merge(["hooks": ["Stop": "nope"]], scriptPath: Self.script)
        }
        #expect(throws: ClaudeHooks.Failure.self) {
            try ClaudeHooks.merge(["hooks": ["a", "b"]], scriptPath: Self.script)
        }
        #expect(throws: ClaudeHooks.Failure.self) {
            try ClaudeHooks.unmerge(["hooks": "nope"], scriptPath: Self.script)
        }
    }

    // MARK: files, in a temporary home

    private static func withHome(_ body: (ClaudeHooks.Paths) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("macbull-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try body(ClaudeHooks.Paths(home: home))
    }

    @Test func installCreatesSettingsAndAnExecutableScript() throws {
        try Self.withHome { paths in
            try ClaudeHooks.install(paths: paths)
            let settings = try ClaudeHooks.parseSettings(Data(contentsOf: paths.settings))
            #expect(Set(settings.keys) == ["hooks"])
            #expect(FileManager.default.isExecutableFile(atPath: paths.script.path))
            #expect(!FileManager.default.fileExists(atPath: paths.backup.path))
        }
    }

    @Test func installTwiceLeavesTheFileUntouched() throws {
        try Self.withHome { paths in
            try ClaudeHooks.install(paths: paths)
            let before = try Data(contentsOf: paths.settings)
            try ClaudeHooks.install(paths: paths)
            #expect(try Data(contentsOf: paths.settings) == before)
        }
    }

    @Test func firstWriteKeepsTheOriginalAsBackupAndUninstallRestoresIt() throws {
        try Self.withHome { paths in
            try FileManager.default.createDirectory(at: paths.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ClaudeHooks.serialize(Self.userSettings()).write(to: paths.settings)
            let original = try Data(contentsOf: paths.settings)
            try ClaudeHooks.install(paths: paths)
            try ClaudeHooks.install(paths: paths)
            #expect(try Data(contentsOf: paths.backup) == original)
            try ClaudeHooks.uninstall(paths: paths)
            let restored = try ClaudeHooks.parseSettings(Data(contentsOf: paths.settings))
            #expect(Self.same(restored, Self.userSettings()))
            #expect(!FileManager.default.fileExists(atPath: paths.script.path))
        }
    }

    @Test func invalidJSONIsRefusedAndNeverWritten() throws {
        try Self.withHome { paths in
            try FileManager.default.createDirectory(at: paths.settings.deletingLastPathComponent(), withIntermediateDirectories: true)
            let garbage = Data("{ \"model\": \"opus\", oops".utf8)
            try garbage.write(to: paths.settings)
            #expect(throws: ClaudeHooks.Failure.self) { try ClaudeHooks.install(paths: paths) }
            #expect(throws: ClaudeHooks.Failure.self) { try ClaudeHooks.uninstall(paths: paths) }
            #expect(try Data(contentsOf: paths.settings) == garbage)
            #expect(!FileManager.default.fileExists(atPath: paths.backup.path))
        }
    }

    // MARK: settings.json formatting

    @Test func serializingKeepsPrettyPrintingAndPlainSlashes() throws {
        let text = try #require(String(
            data: ClaudeHooks.serialize(["env": ["PATH": "/usr/local/bin"]]), encoding: .utf8))
        #expect(text.contains("\n  \""), "pretty printed")
        #expect(text.contains("/usr/local/bin"))
        #expect(!text.contains("\\/"), "slashes are not escaped")
        #expect(text.hasSuffix("}\n"))
    }

    @Test func serializingDoesNotSortTheKeys() throws {
        // Twelve keys written alphabetically: a sorted writer would hand them back alphabetically, any other
        // order is "not sorted". (A dictionary keeps no order, so this is all that can be asked.)
        let names = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet", "kilo", "lima"]
        let settings = Dictionary(uniqueKeysWithValues: names.map { ($0, "x") })
        let text = try #require(String(data: ClaudeHooks.serialize(settings), encoding: .utf8))
        let positions = names.compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        #expect(positions.count == names.count)
        #expect(positions != positions.sorted(), "the keys are not in alphabetical order")
        let back = try ClaudeHooks.parseSettings(ClaudeHooks.serialize(settings))
        #expect(Self.same(back, settings))
    }

    // MARK: events

    @Test func parentPidComesFromTheFileName() {
        #expect(ClaudeHookEvents.parentPID(fromFileName: "1795023727-71640-71632.json") == 71632)
        #expect(ClaudeHookEvents.parentPID(fromFileName: "garbage.json") == 0)
    }

    @Test func drainReadsOldestFirstDeletesFilesAndSkipsBadOnes() throws {
        try Self.withHome { paths in
            let folder = paths.events
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            func drop(_ name: String, _ json: String, age: TimeInterval) throws {
                let url = folder.appendingPathComponent(name)
                try Data(json.utf8).write(to: url)
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
            }
            try drop("1-10-500.json", #"{"session_id":"s","hook_event_name":"PreToolUse","cwd":"/a"}"#, age: 5)
            try drop("1-11-500.json", #"{"session_id":"s","hook_event_name":"Stop"}"#, age: 1)
            try drop("1-12-501.json", "not json", age: 3)
            try drop("1-14-502.json", #"{"session_id":"old","hook_event_name":"Stop"}"#, age: 3600)
            try drop(".1-13-500.tmp", #"{"session_id":"s","hook_event_name":"Stop"}"#, age: 0)

            let events = ClaudeHookEvents.drain(folder: folder)
            #expect(events.map(\.name) == ["PreToolUse", "Stop"])
            #expect(events.first?.parentPID == 500)
            #expect(events.first?.cwd == "/a")
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [".1-13-500.tmp"])
        }
    }

    // MARK: events: Your Turn fields

    private static func parse(_ json: String) -> ClaudeHookEvent? {
        ClaudeHookEvents.parse(Data(json.utf8), fileName: "1-2-3.json", date: Date(timeIntervalSince1970: 0))
    }

    @Test func parseReadsOnlyTheFieldsItNeeds() throws {
        let event = try #require(Self.parse(#"""
        {"session_id":"s","hook_event_name":"Notification","cwd":"/a/b","notification_type":"permission_prompt",
         "message":"Claude needs your permission to use Bash","tool_input":{"command":"rm -rf x"},"transcript_path":"/t.jsonl"}
        """#))
        #expect(event.sessionID == "s")
        #expect(event.name == "Notification")
        #expect(event.cwd == "/a/b")
        #expect(event.notificationType == "permission_prompt")
        #expect(event.mentionsPermission)
        #expect(event.parentPID == 3)
    }

    @Test func messageIsOnlyReducedToWhetherItMentionsPermission() throws {
        let plain = try #require(Self.parse(#"{"session_id":"s","hook_event_name":"Notification","message":"Claude is waiting for your input"}"#))
        #expect(!plain.mentionsPermission)
        let shouting = try #require(Self.parse(#"{"session_id":"s","hook_event_name":"Notification","message":"PERMISSION needed"}"#))
        #expect(shouting.mentionsPermission)
        let none = try #require(Self.parse(#"{"session_id":"s","hook_event_name":"Stop"}"#))
        #expect(!none.mentionsPermission)
        #expect(none.notificationType == nil)
    }

    @Test func theScriptsAnswerIsReadAsIsAndWinsOverALegacyMessage() throws {
        let yes = try #require(Self.parse(#"{"session_id":"s","hook_event_name":"Notification","mentions_permission":true}"#))
        #expect(yes.mentionsPermission)
        let no = try #require(Self.parse(#"{"session_id":"s","hook_event_name":"Notification","mentions_permission":false,"message":"permission"}"#))
        #expect(!no.mentionsPermission)
        let oddlyTyped = try #require(Self.parse(#"{"session_id":"s","hook_event_name":"Notification","mentions_permission":"yes","message":"permission"}"#))
        #expect(oddlyTyped.mentionsPermission, "a wrong type falls back to the legacy message")
    }

    @Test func oddlyTypedOptionalFieldsDoNotSinkTheEvent() throws {
        let event = try #require(Self.parse(#"{"session_id":"s","hook_event_name":"Stop","cwd":5,"message":["x"]}"#))
        #expect(event.cwd == nil)
        #expect(!event.mentionsPermission)
    }

    @Test func requiredFieldsAndShape() {
        #expect(Self.parse(#"{"hook_event_name":"Stop"}"#) == nil)
        #expect(Self.parse(#"{"session_id":"","hook_event_name":"Stop"}"#) == nil)
        #expect(Self.parse(#"{"session_id":"s"}"#) == nil)
        #expect(Self.parse(#"["session_id"]"#) == nil)
        #expect(Self.parse("nope") == nil)
    }

    @Test func staleEventFilesAreDeletedUnreadAndOldHiddenOnesToo() throws {
        try Self.withHome { paths in
            let folder = paths.events
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let now = Date()
            func drop(_ name: String, age: TimeInterval) throws {
                let url = folder.appendingPathComponent(name)
                try Data(#"{"session_id":"s","hook_event_name":"Stop"}"#.utf8).write(to: url)
                try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
            }
            try drop("1-1-1.json", age: ClaudeHookEvents.maxAge + 5)
            try drop("1-2-1.json", age: ClaudeHookEvents.maxAge - 60)
            try drop(".1-3-1.tmp", age: ClaudeHookEvents.maxAge + 5)
            try drop(".1-4-1.tmp", age: 1)
            let events = ClaudeHookEvents.drain(folder: folder, now: now)
            #expect(events.count == 1)
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [".1-4-1.tmp"])
        }
    }

    @Test func unmergeLeavesAnotherToolsOddlyShapedEventAlone() throws {
        let merged = try ClaudeHooks.merge(["hooks": ["Custom": "not a list"]], scriptPath: Self.script)
        let restored = try ClaudeHooks.unmerge(merged, scriptPath: Self.script)
        #expect(Self.same(restored, ["hooks": ["Custom": "not a list"]]))
    }

    @Test func errorMessagesAreWordedForPeople() {
        #expect(ClaudeHooks.Failure.invalidJSON.errorDescription?.contains("not valid JSON") == true)
        #expect(ClaudeHooks.Failure.unexpectedShape("hooks.Stop").errorDescription?.contains("hooks.Stop") == true)
        #expect(ClaudeHooks.Failure.io("disk full").errorDescription?.contains("disk full") == true)
    }
}
