import Foundation

/// What the log watcher knows right now; input to the judge.
struct LogFacts: Equatable, Sendable {
    /// Last write by an agent (agent id), from any of its session logs.
    var lastWriteByAgent: [String: Date] = [:]
    /// Last write in one project log folder, keyed "<agent id>/<folder name>". Per-project agents only.
    var lastWriteByProject: [String: Date] = [:]
    /// Existing project folder names under the log folder of each per-project agent (agent id).
    var projectFolders: [String: Set<String>] = [:]

    static func projectKey(agentID: String, folder: String) -> String {
        agentID + "/" + folder
    }
}

/// A log folder being watched. `path` is the real path (file events report real paths).
struct LogRoot: Equatable, Sendable {
    let agentID: String
    let path: String
    let endings: [String]
    let perProject: Bool
}

/// Pure bookkeeping for agent log writes: which files count, per-agent and per-project last writes,
/// and the tracked files that are polled by modification time.
struct LogActivityState: Sendable {
    /// A write older than this no longer says anything about now.
    static let windowSeconds: TimeInterval = 90
    /// A tracked file not modified for this long is dropped.
    static let trackedFor: TimeInterval = 6 * 60 * 60

    struct Tracked: Equatable, Sendable {
        var agentID: String
        var modified: Date
    }

    private(set) var roots: [LogRoot] = []
    private(set) var lastWriteByAgent: [String: Date] = [:]
    private(set) var lastWriteByProject: [String: Date] = [:]
    private(set) var tracked: [String: Tracked] = [:]

    mutating func setRoots(_ roots: [LogRoot]) {
        self.roots = roots
    }

    struct Classified: Equatable {
        let agentID: String
        /// The folder directly under the root, for per-project agents.
        let project: String?
    }

    /// Whether `path` is a session log of an agent: right ending, under its log folder, not a memory note.
    func classify(_ path: String) -> Classified? {
        guard !path.contains("/memory/") else { return nil }
        for root in roots {
            let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            guard path.hasPrefix(prefix), root.endings.contains(where: path.hasSuffix) else { continue }
            guard root.perProject else { return Classified(agentID: root.agentID, project: nil) }
            let relative = path.dropFirst(prefix.count)
            // A file directly in the log folder belongs to no project.
            guard let slash = relative.firstIndex(of: "/") else { return Classified(agentID: root.agentID, project: nil) }
            return Classified(agentID: root.agentID, project: String(relative[..<slash]))
        }
        return nil
    }

    /// A new or modified file reported by the file events. `modified` is the file's modification time
    /// when it could be read; without it the write is not trusted and ignored.
    mutating func noteFileEvent(path: String, modified: Date?, now: Date) {
        guard let modified, let classified = classify(path) else { return }
        let time = min(modified, now)
        record(classified, at: time)
        tracked[path] = Tracked(agentID: classified.agentID, modified: modified)
    }

    /// Files already there when monitoring starts: tracked, but not news.
    mutating func seed(path: String, modified: Date, now: Date) {
        guard now.timeIntervalSince(modified) < Self.trackedFor, let classified = classify(path) else { return }
        tracked[path] = Tracked(agentID: classified.agentID, modified: modified)
    }

    /// Compares each tracked file's modification time with the last one seen. An advance is a write at
    /// the file's modification time (the first scan after a wake can be late). Gone or long-quiet files go.
    mutating func poll(now: Date, modifiedTime: (String) -> Date?) {
        for (path, file) in tracked {
            guard let modified = modifiedTime(path), now.timeIntervalSince(modified) < Self.trackedFor else {
                tracked[path] = nil
                continue
            }
            guard modified > file.modified, let classified = classify(path) else { continue }
            record(classified, at: min(modified, now))
            tracked[path] = Tracked(agentID: file.agentID, modified: modified)
        }
    }

    private mutating func record(_ classified: Classified, at time: Date) {
        if lastWriteByAgent[classified.agentID].map({ $0 < time }) ?? true {
            lastWriteByAgent[classified.agentID] = time
        }
        if let project = classified.project {
            let key = LogFacts.projectKey(agentID: classified.agentID, folder: project)
            if lastWriteByProject[key].map({ $0 < time }) ?? true { lastWriteByProject[key] = time }
        }
    }

    /// Project entries older than the window are discarded.
    mutating func prune(now: Date) {
        lastWriteByProject = lastWriteByProject.filter { now.timeIntervalSince($0.value) <= Self.windowSeconds }
    }

    func facts(projectFolders: [String: Set<String>]) -> LogFacts {
        LogFacts(lastWriteByAgent: lastWriteByAgent, lastWriteByProject: lastWriteByProject, projectFolders: projectFolders)
    }
}
