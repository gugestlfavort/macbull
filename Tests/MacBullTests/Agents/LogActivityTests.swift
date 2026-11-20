import Foundation
import CoreServices
import Testing
@testable import MacBull

struct LogActivityTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func state() -> LogActivityState {
        var state = LogActivityState()
        state.setRoots([
            LogRoot(agentID: "claude", path: "/h/.claude/projects", endings: [".jsonl", ".json"], perProject: true),
            LogRoot(agentID: "codex", path: "/h/.codex/sessions", endings: [".jsonl", ".json"], perProject: false),
            LogRoot(agentID: "cursor-agent", path: "/h/.cursor/chats", endings: [".db", ".db-wal", ".jsonl", ".json"], perProject: false),
        ])
        return state
    }

    @Test func classifiesSessionLogsUnderAnAgentsFolder() {
        let state = Self.state()
        #expect(state.classify("/h/.claude/projects/-Users-x-app/abc.jsonl") == .init(agentID: "claude", project: "-Users-x-app"))
        #expect(state.classify("/h/.claude/projects/-Users-x-app/abc/subagents/agent-1.jsonl")?.project == "-Users-x-app")
        #expect(state.classify("/h/.codex/sessions/2026/11/19/rollout-1.jsonl") == .init(agentID: "codex", project: nil))
        #expect(state.classify("/h/.cursor/chats/h/store.db-wal")?.agentID == "cursor-agent")
    }

    @Test func ignoresOtherEndingsOtherFoldersAndMemoryNotes() {
        let state = Self.state()
        #expect(state.classify("/h/.claude/projects/-a/notes.txt") == nil)
        #expect(state.classify("/h/.claude/projects/-a/memory/note.json") == nil)
        #expect(state.classify("/h/.claude/projects-other/-a/x.jsonl") == nil)
        #expect(state.classify("/h/.claude/settings.json") == nil)
        #expect(state.classify("/h/.codex/sessions/x.db") == nil)
    }

    @Test func aFileEventRecordsAgentAndProjectWrites() {
        var state = Self.state()
        let wrote = Self.now.addingTimeInterval(-1.5)
        state.noteFileEvent(path: "/h/.claude/projects/-a/s.jsonl", modified: wrote, now: Self.now)
        let facts = state.facts(projectFolders: [:])
        #expect(facts.lastWriteByAgent["claude"] == wrote)
        #expect(facts.lastWriteByProject[LogFacts.projectKey(agentID: "claude", folder: "-a")] == wrote)
        #expect(facts.lastWriteByAgent["codex"] == nil)
    }

    @Test func aFileEventWithoutAReadableModificationTimeIsIgnored() {
        var state = Self.state()
        state.noteFileEvent(path: "/h/.codex/sessions/x.jsonl", modified: nil, now: Self.now)
        #expect(state.facts(projectFolders: [:]).lastWriteByAgent.isEmpty)
    }

    @Test func aWriteInTheFutureIsClampedToNow() {
        var state = Self.state()
        state.noteFileEvent(path: "/h/.codex/sessions/x.jsonl", modified: Self.now.addingTimeInterval(30), now: Self.now)
        #expect(state.facts(projectFolders: [:]).lastWriteByAgent["codex"] == Self.now)
    }

    @Test func seededFilesAreTrackedButNotNews() {
        var state = Self.state()
        state.seed(path: "/h/.codex/sessions/x.jsonl", modified: Self.now.addingTimeInterval(-3600), now: Self.now)
        state.seed(path: "/h/.codex/sessions/old.jsonl", modified: Self.now.addingTimeInterval(-7 * 3600), now: Self.now)
        #expect(state.tracked.keys.sorted() == ["/h/.codex/sessions/x.jsonl"])
        #expect(state.facts(projectFolders: [:]).lastWriteByAgent.isEmpty)
    }

    @Test func pollCountsAnAdvanceAtTheFilesModificationTime() {
        var state = Self.state()
        let path = "/h/.codex/sessions/x.jsonl"
        state.seed(path: path, modified: Self.now.addingTimeInterval(-600), now: Self.now)
        let wrote = Self.now.addingTimeInterval(-40)
        state.poll(now: Self.now) { _ in wrote }
        #expect(state.facts(projectFolders: [:]).lastWriteByAgent["codex"] == wrote)
        // Seen already: the same time is not a second write.
        var again = state
        again.poll(now: Self.now.addingTimeInterval(10)) { _ in wrote }
        #expect(again.facts(projectFolders: [:]).lastWriteByAgent["codex"] == wrote)
    }

    @Test func pollWithoutAnAdvanceIsNotAWrite() {
        var state = Self.state()
        let path = "/h/.codex/sessions/x.jsonl"
        let stamp = Self.now.addingTimeInterval(-600)
        state.seed(path: path, modified: stamp, now: Self.now)
        state.poll(now: Self.now) { _ in stamp }
        #expect(state.facts(projectFolders: [:]).lastWriteByAgent.isEmpty)
    }

    @Test func trackedFilesAreDroppedWhenGoneOrQuietForSixHours() {
        var state = Self.state()
        state.seed(path: "/h/.codex/sessions/gone.jsonl", modified: Self.now.addingTimeInterval(-60), now: Self.now)
        state.seed(path: "/h/.codex/sessions/quiet.jsonl", modified: Self.now.addingTimeInterval(-3600), now: Self.now)
        state.seed(path: "/h/.codex/sessions/live.jsonl", modified: Self.now.addingTimeInterval(-3600), now: Self.now)
        let later = Self.now.addingTimeInterval(6 * 3600)
        state.poll(now: later) { path in
            switch path {
            case "/h/.codex/sessions/gone.jsonl": nil
            case "/h/.codex/sessions/quiet.jsonl": Self.now.addingTimeInterval(-3600)
            default: later.addingTimeInterval(-5)
            }
        }
        #expect(state.tracked.keys.sorted() == ["/h/.codex/sessions/live.jsonl"])
    }

    @Test func projectEntriesOlderThanNinetySecondsAreDiscarded() {
        var state = Self.state()
        state.noteFileEvent(path: "/h/.claude/projects/-a/s.jsonl", modified: Self.now, now: Self.now)
        state.noteFileEvent(path: "/h/.claude/projects/-b/s.jsonl", modified: Self.now.addingTimeInterval(60), now: Self.now.addingTimeInterval(60))
        state.prune(now: Self.now.addingTimeInterval(100))
        let keys = state.facts(projectFolders: [:]).lastWriteByProject.keys
        #expect(Array(keys) == [LogFacts.projectKey(agentID: "claude", folder: "-b")])
    }

    @Test func fileEventFlagsOnlyCountNewOrModifiedFiles() {
        let file = UInt32(kFSEventStreamEventFlagItemIsFile)
        #expect(LogActivityMonitor.countsAsWrite(file | UInt32(kFSEventStreamEventFlagItemModified)))
        #expect(LogActivityMonitor.countsAsWrite(file | UInt32(kFSEventStreamEventFlagItemCreated)))
        #expect(!LogActivityMonitor.countsAsWrite(file | UInt32(kFSEventStreamEventFlagItemRemoved)))
        #expect(!LogActivityMonitor.countsAsWrite(file | UInt32(kFSEventStreamEventFlagItemRenamed)))
        #expect(!LogActivityMonitor.countsAsWrite(file | UInt32(kFSEventStreamEventFlagItemInodeMetaMod)))
        #expect(!LogActivityMonitor.countsAsWrite(UInt32(kFSEventStreamEventFlagItemIsDir) | UInt32(kFSEventStreamEventFlagItemCreated)))
        #expect(!LogActivityMonitor.countsAsWrite(file | UInt32(kFSEventStreamEventFlagItemCreated) | UInt32(kFSEventStreamEventFlagItemRemoved)))
    }
}
