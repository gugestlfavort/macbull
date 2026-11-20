import Foundation
import Testing
@testable import MacBull

/// Runs the real hook script (`/bin/sh` + `plutil`) in a temporary HOME, the way Claude Code does.
private struct ScriptRig {
    let home: URL
    let paths: ClaudeHooks.Paths
    /// A stand-in for the running app: a process whose name `pgrep -x` finds.
    private let standIn: Process?
    let processName: String

    private static let standInPrefix = "mbhk"

    /// `appRunning: false` names a process nobody runs, so the script sees no MacBull.
    init(appRunning: Bool = true) throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("macbull-script-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        paths = ClaudeHooks.Paths(home: home)
        try ClaudeHooks.install(paths: paths)
        processName = Self.standInPrefix + UUID().uuidString.prefix(8).lowercased()
        guard appRunning else {
            standIn = nil
            return
        }
        let link = home.appendingPathComponent(processName)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/bin/sleep"))
        let process = Process()
        process.executableURL = link
        process.arguments = ["60"]
        try process.run()
        standIn = process
        try Self.waitUntilFound(processName)
    }

    func tearDown() {
        standIn?.terminate()
        try? FileManager.default.removeItem(at: home)
    }

    private static func waitUntilFound(_ name: String) throws {
        var tries = 0
        while !pgrep(name) {
            tries += 1
            if tries > 300 { throw Failure("The stand-in process never showed up") }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private static func pgrep(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-qx", name]
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }

    /// Feeds `input` to the script and returns its exit status.
    @discardableResult
    func run(_ input: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [paths.script.path]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "MACBULL_PROCESS": processName]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    }

    var folderEntries: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: paths.events.path)) ?? []).sorted()
    }

    /// The one finished event file, as a dictionary.
    func writtenEvent() throws -> (object: [String: Any], url: URL) {
        let names = folderEntries.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
        guard names.count == 1, let name = names.first else { throw Failure("Expected one event file, found \(names)") }
        let url = paths.events.appendingPathComponent(name)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let dictionary = object as? [String: Any] else { throw Failure("Not an object") }
        return (dictionary, url)
    }
}

struct ClaudeHookScriptTests {
    private static let payload = """
    {"session_id":"abc-123","hook_event_name":"Notification","cwd":"/Users/me/api","notification_type":"permission_prompt",
     "message":"Claude needs your PERMISSION to use Bash","prompt":"my secret prompt about the merger",
     "tool_input":{"command":"cat ~/.ssh/id_rsa"},"tool_response":{"stdout":"top secret output"},
     "transcript_path":"/Users/me/.claude/projects/x/abc.jsonl"}
    """

    @Test func writesOnlyTheFiveKeysAndNothingFromThePromptOrTheTools() throws {
        let rig = try ScriptRig()
        defer { rig.tearDown() }
        #expect(try rig.run(Self.payload) == 0)
        let (object, url) = try rig.writtenEvent()
        #expect(Set(object.keys) == ["session_id", "hook_event_name", "cwd", "notification_type", "mentions_permission"])
        #expect(object["session_id"] as? String == "abc-123")
        #expect(object["hook_event_name"] as? String == "Notification")
        #expect(object["cwd"] as? String == "/Users/me/api")
        #expect(object["notification_type"] as? String == "permission_prompt")
        #expect(object["mentions_permission"] as? Bool == true)
        let text = try String(contentsOf: url, encoding: .utf8)
        for leaked in ["secret", "merger", "id_rsa", "transcript", "Bash", "message"] {
            #expect(!text.contains(leaked), "\(leaked) must not be written")
        }
    }

    @Test func aMessageWithoutPermissionAnswersFalseAndAnEventWithoutOneAnswersFalseToo() throws {
        let rig = try ScriptRig()
        defer { rig.tearDown() }
        try rig.run(#"{"session_id":"s","hook_event_name":"Notification","message":"Claude is waiting for your input","notification_type":"idle_prompt"}"#)
        let idle = try rig.writtenEvent()
        #expect(idle.object["mentions_permission"] as? Bool == false)
        try FileManager.default.removeItem(at: idle.url)
        try rig.run(#"{"session_id":"s","hook_event_name":"Stop","cwd":"/a","message":"permission"}"#)
        let stop = try rig.writtenEvent()
        #expect(Set(stop.object.keys) == ["session_id", "hook_event_name", "cwd", "mentions_permission"])
        #expect(stop.object["mentions_permission"] as? Bool == false, "only a Notification's message is looked at")
    }

    @Test func aFolderNameWithQuotesBackslashesAndASpaceComesBackExactly() throws {
        let rig = try ScriptRig()
        defer { rig.tearDown() }
        let folder = #"/Users/me/My "best" project\v2 $HOME `x` 'q' é"#
        let escaped = try #require(String(data: JSONSerialization.data(withJSONObject: [folder]), encoding: .utf8))
        let json = #"{"session_id":"s","hook_event_name":"PreToolUse","cwd":\#(escaped.dropFirst().dropLast())}"#
        #expect(try rig.run(json) == 0)
        let written = try rig.writtenEvent()
        #expect(written.object["cwd"] as? String == folder)
        // And the app's own reader takes the file.
        let events = ClaudeHookEvents.drain(folder: rig.paths.events)
        #expect(events.count == 1)
        #expect(events.first?.cwd == folder)
        #expect(events.first?.sessionID == "s")
        #expect(events.first?.name == "PreToolUse")
    }

    @Test func theReaderGetsTheAnswerFromTheScriptsFile() throws {
        let rig = try ScriptRig()
        defer { rig.tearDown() }
        try rig.run(Self.payload)
        let event = try #require(ClaudeHookEvents.drain(folder: rig.paths.events).first)
        #expect(event.mentionsPermission)
        #expect(event.notificationType == "permission_prompt")
    }

    @Test func theEventFileIsOwnerOnlyAndNoTemporaryFileIsLeftBehind() throws {
        let rig = try ScriptRig()
        defer { rig.tearDown() }
        try rig.run(Self.payload)
        let (_, url) = try rig.writtenEvent()
        let mode = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
        #expect(mode == 0o600)
        #expect(rig.folderEntries.allSatisfy { !$0.hasPrefix(".") })
    }

    @Test func withNoMacBullRunningNothingIsWrittenAndItStillSucceeds() throws {
        let rig = try ScriptRig(appRunning: false)
        defer { rig.tearDown() }
        #expect(try rig.run(Self.payload) == 0)
        #expect(rig.folderEntries.isEmpty)
    }

    @Test func garbageOrIncompleteInputWritesNothingAndStillSucceeds() throws {
        let rig = try ScriptRig()
        defer { rig.tearDown() }
        #expect(try rig.run("not json at all") == 0)
        #expect(try rig.run("") == 0)
        #expect(try rig.run(#"{"hook_event_name":"Stop"}"#) == 0)
        #expect(try rig.run(#"{"session_id":"s"}"#) == 0)
        #expect(rig.folderEntries.isEmpty)
    }

    @Test func theInstallerReplacesAnOlderScript() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("macbull-script-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ClaudeHooks.Paths(home: home)
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try "#!/bin/sh\ncat > \"$HOME/everything.json\"\n".write(to: paths.script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.script.path)
        try ClaudeHooks.install(paths: paths)
        #expect(try String(contentsOf: paths.script, encoding: .utf8) == ClaudeHooks.scriptSource)
        #expect(FileManager.default.isExecutableFile(atPath: paths.script.path))
    }
}
