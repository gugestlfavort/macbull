import Foundation

/// A process is identified by its pid and its start time: pids get reused.
struct ProcessKey: Hashable, Sendable {
    let pid: pid_t
    let startTime: Double

    init(pid: pid_t, startTime: Double) {
        self.pid = pid
        self.startTime = startTime
    }

    init(_ entry: ProcessTable.Entry) {
        self.init(pid: entry.pid, startTime: entry.startTime)
    }
}

/// All processes at one moment.
struct ProcessTable: Sendable {
    struct Entry: Equatable, Sendable {
        let pid: pid_t
        let parent: pid_t
        /// Process name (the kernel's command name).
        let name: String
        /// Seconds since 1970.
        let startTime: Double
        /// Own user and system time plus that of the children it already reaped.
        let cpuSeconds: Double
        /// Binary path, when the kernel gave one.
        var path: String?
        /// Full argument list. Only read for language runtimes and direct agent matches; empty otherwise.
        var arguments: [String]

        init(
            pid: pid_t, parent: pid_t, name: String, startTime: Double, cpuSeconds: Double,
            path: String? = nil, arguments: [String] = []
        ) {
            self.pid = pid
            self.parent = parent
            self.name = name
            self.startTime = startTime
            self.cpuSeconds = cpuSeconds
            self.path = path
            self.arguments = arguments
        }
    }

    let entries: [pid_t: Entry]
    let children: [pid_t: [pid_t]]

    init(entries: [pid_t: Entry], children: [pid_t: [pid_t]]) {
        self.entries = entries
        self.children = children
    }

    /// Builds the child lists from the parent pids.
    init(entries: [pid_t: Entry]) {
        var children: [pid_t: [pid_t]] = [:]
        for entry in entries.values.sorted(by: { $0.pid < $1.pid }) {
            children[entry.parent, default: []].append(entry.pid)
        }
        self.init(entries: entries, children: children)
    }

    init(_ list: [Entry]) {
        self.init(entries: Dictionary(list.map { ($0.pid, $0) }, uniquingKeysWith: { _, new in new }))
    }
}

/// One scan's view of the machine.
struct ProcessSnapshot: Sendable {
    let takenAt: Date
    let table: ProcessTable
    /// Working directories of the processes that matched an agent.
    let directories: [pid_t: String]

    init(takenAt: Date, table: ProcessTable, directories: [pid_t: String] = [:]) {
        self.takenAt = takenAt
        self.table = table
        self.directories = directories
    }
}
