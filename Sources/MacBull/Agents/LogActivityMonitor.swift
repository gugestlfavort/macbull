import CoreServices
import Darwin
import Foundation
import OSLog

/// Watches the log folders of every agent in the catalogue with file events (2 s latency) and polls the
/// tracked files' modification times each scan. Safe to call from any thread.
final class LogActivityMonitor: @unchecked Sendable {
    /// File events arrive at most this late.
    static let latency: TimeInterval = 2

    private struct Guarded {
        var state = LogActivityState()
        var stream: FSEventStreamRef?
        var watchedPaths: [String] = []
        var started = false
    }

    private let home: URL
    private let agents: [AgentDefinition]
    private let queue = DispatchQueue(label: "app.macbull.agents.logs")
    private let lock = NSLock()
    private var guardedState = Guarded()

    init(home: URL, agents: [AgentDefinition]) {
        self.home = home
        self.agents = agents.filter { !$0.logFolders.isEmpty }
    }

    deinit {
        stop()
    }

    private func guarded<T>(_ body: (inout Guarded) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&guardedState)
    }

    /// Refreshes which log folders exist (they appear after an agent's first run), restarts the file
    /// events when the set changed, polls tracked files and returns what the judge needs.
    func refresh(now: Date) -> LogFacts {
        let roots = existingRoots()
        let projectFolders = projectFolderNames(roots)
        let isFirst = guarded { !$0.started }
        if isFirst { seed(roots, now: now) }
        guarded { box in
            box.started = true
            box.state.setRoots(roots)
        }
        restartStreamIfNeeded(paths: roots.map(\.path))
        return guarded { box in
            box.state.poll(now: now, modifiedTime: Self.modificationDate)
            box.state.prune(now: now)
            return box.state.facts(projectFolders: projectFolders)
        }
    }

    func stop() {
        let stream: FSEventStreamRef? = guarded { box in
            defer {
                box.stream = nil
                box.watchedPaths = []
            }
            return box.stream
        }
        if let stream { Self.tear(down: stream) }
    }

    // MARK: Folders

    private func existingRoots() -> [LogRoot] {
        var roots: [LogRoot] = []
        for agent in agents {
            for folder in agent.logFolders {
                let url = home.appendingPathComponent(folder, isDirectory: true)
                guard let real = Self.realPath(url.path), Self.isDirectory(real) else { continue }
                roots.append(LogRoot(agentID: agent.id, path: real, endings: agent.logEndings, perProject: agent.logsPerProject))
            }
        }
        return roots
    }

    private func projectFolderNames(_ roots: [LogRoot]) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for root in roots where root.perProject {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            result[root.agentID, default: []].formUnion(names)
        }
        return result
    }

    /// Every log file modified in the last 6 hours becomes tracked, without counting as a write.
    private func seed(_ roots: [LogRoot], now: Date) {
        var found: [(path: String, modified: Date)] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        for root in roots {
            let url = URL(fileURLWithPath: root.path, isDirectory: true)
            guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { continue }
            for case let file as URL in walker {
                guard root.endings.contains(where: file.path.hasSuffix),
                      let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      now.timeIntervalSince(modified) < LogActivityState.trackedFor else { continue }
                found.append((file.path, modified))
            }
        }
        guarded { box in
            box.state.setRoots(roots)
            for file in found { box.state.seed(path: file.path, modified: file.modified, now: now) }
        }
    }

    // MARK: File events

    private func restartStreamIfNeeded(paths: [String]) {
        let unchanged = guarded { $0.watchedPaths == paths && ($0.stream != nil || paths.isEmpty) }
        guard !unchanged else { return }
        stop()
        guard !paths.isEmpty else { return }
        guard let stream = makeStream(paths: paths) else {
            Log.agents.error("Could not watch the agent log folders")
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            Log.agents.error("Could not start watching the agent log folders")
            Self.tear(down: stream)
            return
        }
        guarded { box in
            box.stream = stream
            box.watchedPaths = paths
        }
    }

    private func makeStream(paths: [String]) -> FSEventStreamRef? {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let monitor = Unmanaged<LogActivityMonitor>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            monitor.handle(paths: paths, flags: Array(UnsafeBufferPointer(start: eventFlags, count: count)))
        }
        return FSEventStreamCreate(kCFAllocatorDefault, callback, &context, paths as CFArray,
                                   FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency, flags)
    }

    private static func tear(down stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    /// Only new or modified files count; deletes, renames and metadata-only changes are ignored.
    static func countsAsWrite(_ flags: FSEventStreamEventFlags) -> Bool {
        let file = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile)
        let wrote = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified)
        let gone = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)
        return flags & file != 0 && flags & wrote != 0 && flags & gone == 0
    }

    private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        let now = Date()
        let writes = zip(paths, flags).filter { Self.countsAsWrite($0.1) }.map(\.0)
        guard !writes.isEmpty else { return }
        guarded { box in
            for path in writes {
                box.state.noteFileEvent(path: path, modified: Self.modificationDate(path), now: now)
            }
        }
    }

    // MARK: File system

    static func modificationDate(_ path: String) -> Date? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        let time = info.st_mtimespec
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000)
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
