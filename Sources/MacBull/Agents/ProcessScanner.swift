import Darwin
import Foundation

/// The kernel's argument block for one process (KERN_PROCARGS2).
enum ProcessArguments {
    /// Layout: argc (Int32), executable path, nul padding, then argc strings, then the environment.
    /// A process that rewrote its title overwrote the argument area, so argc can be larger than what is
    /// left and the environment follows: reading stops at the first empty string after argv[0].
    static func parse(_ bytes: [UInt8]) -> (executable: String, arguments: [String])? {
        let headerSize = MemoryLayout<Int32>.size
        guard bytes.count > headerSize else { return nil }
        let argc = Int(bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        guard argc > 0 else { return nil }

        var index = headerSize
        let executable = readString(bytes, at: &index)
        while index < bytes.count, bytes[index] == 0 { index += 1 }

        var arguments: [String] = []
        while arguments.count < argc, index < bytes.count {
            if !arguments.isEmpty, bytes[index] == 0 { break }
            arguments.append(readString(bytes, at: &index))
        }
        return (executable, arguments)
    }

    /// The string at `index` up to its nul; moves `index` past the nul.
    private static func readString(_ bytes: [UInt8], at index: inout Int) -> String {
        let start = index
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        if index < bytes.count { index += 1 }
        return text
    }
}

/// Reads the process table through libproc and sysctl. Cheap enough to run every 10 seconds, and meant to
/// run off the main thread. Arguments and paths are cached per process (pid plus start time).
struct ProcessScanner {
    private struct Cached {
        var name: String
        var path: String?
        var arguments: [String]?
    }

    /// Room for processes that start between counting them and listing them.
    private static let spareSlots = 64
    /// Binary paths can be long (app bundles inside app bundles).
    private static let pathBufferSize = Int(MAXPATHLEN) * 4

    private var cache: [ProcessKey: Cached] = [:]
    private let ticksToSeconds: Double

    init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let denominator = max(Double(timebase.denom), 1)
        // CPU times come back in mach absolute time units; this turns them into seconds.
        ticksToSeconds = Double(timebase.numer) / denominator / 1_000_000_000
    }

    mutating func scan(matcher: AgentMatcher, now: Date) -> ProcessSnapshot {
        var entries: [pid_t: ProcessTable.Entry] = [:]
        var seen = Set<ProcessKey>()
        for pid in Self.allPIDs() where pid > 0 {
            guard let basic = Self.basicInfo(pid) else { continue }
            let key = ProcessKey(pid: pid, startTime: basic.startTime)
            seen.insert(key)
            var cached = cache[key]
            if cached?.name != basic.name { cached = Cached(name: basic.name, path: Self.path(pid), arguments: nil) }
            if var current = cached, current.arguments == nil, matcher.needsArguments(name: basic.name, path: current.path) {
                current.arguments = Self.readArguments(pid)
                cached = current
            }
            cache[key] = cached
            entries[pid] = ProcessTable.Entry(
                pid: pid, parent: basic.parent, name: basic.name, startTime: basic.startTime,
                cpuSeconds: cpuSeconds(pid), path: cached?.path, arguments: cached?.arguments ?? []
            )
        }
        cache = cache.filter { seen.contains($0.key) }

        var directories: [pid_t: String] = [:]
        for entry in entries.values where matcher.match(name: entry.name, path: entry.path, arguments: entry.arguments) != nil {
            if let directory = Self.workingDirectory(entry.pid) { directories[entry.pid] = directory }
        }
        return ProcessSnapshot(takenAt: now, table: ProcessTable(entries: entries), directories: directories)
    }

    // MARK: libproc

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + Self.spareSlots)
        let bytes = pids.count * MemoryLayout<pid_t>.size
        let count = proc_listallpids(&pids, Int32(bytes))
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    private static func basicInfo(_ pid: pid_t) -> (name: String, parent: pid_t, startTime: Double)? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let name = withUnsafeBytes(of: info.pbi_name) { cString(from: $0) }
        let command = withUnsafeBytes(of: info.pbi_comm) { cString(from: $0) }
        let start = Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
        return (name.isEmpty ? command : name, pid_t(info.pbi_ppid), start)
    }

    private static func cString(from buffer: UnsafeRawBufferPointer) -> String {
        let end = buffer.firstIndex(of: 0) ?? buffer.count
        return String(decoding: buffer[..<end], as: UTF8.self)
    }

    /// Own user and system time plus what the children it already reaped used.
    private func cpuSeconds(_ pid: pid_t) -> Double {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        guard result == 0 else { return 0 }
        let ticks = usage.ri_user_time &+ usage.ri_system_time &+ usage.ri_child_user_time &+ usage.ri_child_system_time
        return Double(ticks) * ticksToSeconds
    }

    private static func path(_ pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Self.pathBufferSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private static func workingDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { cString(from: $0) }
        return path.isEmpty ? nil : path
    }

    private static func readArguments(_ pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return ProcessArguments.parse(Array(buffer.prefix(size)))?.arguments
    }

    /// The parent of a live process, for walks up the tree outside a scan.
    static func parent(of pid: pid_t) -> pid_t? {
        basicInfo(pid)?.parent
    }
}
