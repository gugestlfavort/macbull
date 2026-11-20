import Foundation

/// A day file on disk.
struct JournalDayFile: Equatable, Sendable {
    /// Local midnight of the day the file holds.
    var day: Date
    var url: URL
}

/// What a day file looked like when it was parsed. If the file still looks like this, the parsed events are good.
private struct FileSignature: Equatable {
    var size: UInt64
    var modified: Date?
}

private struct CachedDay {
    var signature: FileSignature
    var events: [JournalEvent]
}

/// All journal file access. Writes are queued and run off the caller's thread; every read goes
/// through the same serial queue, so it always sees the writes before it.
///
/// Parsed events are kept in memory per day file: a read decodes only the files that changed since the last
/// read (in practice none, or today's), an append adds to its day's list, and deleting or erasing drops it.
final class JournalStore: @unchecked Sendable {
    static let rollupsName = "rollups.json"
    static let receiptsName = "receipts.json"
    static let dayFileExtension = "jsonl"
    private static let folderMode = 0o700
    private static let fileMode = 0o600

    let baseURL: URL
    private let fileManager: FileManager
    private let calendar: Calendar
    private let queue = DispatchQueue(label: "app.macbull.journal.io")
    /// Parsed events by day file name. Touched only on `queue`.
    private var cache: [String: CachedDay] = [:]

    init(baseURL: URL, calendar: Calendar, fileManager: FileManager) {
        self.baseURL = baseURL
        self.calendar = calendar
        self.fileManager = fileManager
    }

    // MARK: Events

    /// Queues the write; returns at once.
    func append(_ event: JournalEvent) {
        queue.async { self.appendNow(event) }
    }

    /// Returns once every queued write is done.
    func flush() {
        queue.sync {}
    }

    /// Every readable event, in file order (days oldest first). Corrupt lines are skipped.
    func readAll() -> [JournalEvent] {
        queue.sync { readAllNow() }
    }

    func dayFiles() -> [JournalDayFile] {
        queue.sync { dayFilesNow() }
    }

    func delete(_ files: [JournalDayFile]) {
        queue.sync { deleteNow(files) }
    }

    /// Folds the day files older than `cutoff` into `rollups.json`, then deletes them. Queued behind the
    /// writes before it and run off the caller's thread; returns at once. `flush()` waits for it.
    func prune(before cutoff: Date, now: Date) {
        queue.async { self.pruneNow(before: cutoff, now: now) }
    }

    /// Journal files, rollups and receipts. The folder stays.
    func eraseAll() {
        queue.sync {
            let items = (try? fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)) ?? []
            for url in items where isOurs(url) {
                remove(url)
            }
            cache.removeAll()
        }
    }

    // MARK: Rollups and receipts

    func loadRollups() -> JournalRollups {
        queue.sync { readJSON(JournalRollups.self, named: Self.rollupsName) ?? JournalRollups() }
    }

    func saveRollups(_ rollups: JournalRollups) {
        queue.sync { writeJSON(rollups, named: Self.rollupsName) }
    }

    func loadReceipts() -> [Receipt] {
        queue.sync { readJSON([Receipt].self, named: Self.receiptsName) ?? [] }
    }

    func saveReceipts(_ receipts: [Receipt]) {
        queue.sync { writeJSON(receipts, named: Self.receiptsName) }
    }

    // MARK: Day files (queue only)

    private func fileName(for date: Date) -> String {
        "\(JournalDayName.name(for: date, calendar: calendar)).\(Self.dayFileExtension)"
    }

    private func dayFilesNow() -> [JournalDayFile] {
        let items = (try? fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)) ?? []
        return items
            .filter { $0.pathExtension == Self.dayFileExtension }
            .compactMap { url -> JournalDayFile? in
                let name = url.deletingPathExtension().lastPathComponent
                return JournalDayName.date(from: name, calendar: calendar).map { JournalDayFile(day: $0, url: url) }
            }
            .sorted { $0.day < $1.day }
    }

    private func isOurs(_ url: URL) -> Bool {
        url.pathExtension == Self.dayFileExtension
            || url.lastPathComponent == Self.rollupsName
            || url.lastPathComponent == Self.receiptsName
    }

    private func readAllNow() -> [JournalEvent] {
        var events: [JournalEvent] = []
        let files = dayFilesNow()
        for file in files {
            let name = file.url.lastPathComponent
            let signature = signature(of: file.url)
            if let signature, let cached = cache[name], cached.signature == signature {
                events.append(contentsOf: cached.events)
                continue
            }
            guard let parsed = parseDayFile(file.url) else { continue }
            if let signature { cache[name] = CachedDay(signature: signature, events: parsed) }
            events.append(contentsOf: parsed)
        }
        let present = Set(files.map { $0.url.lastPathComponent })
        cache = cache.filter { present.contains($0.key) }
        return events
    }

    private func parseDayFile(_ url: URL) -> [JournalEvent]? {
        guard let data = try? Data(contentsOf: url) else {
            Log.journal.error("Could not read a journal day file")
            return nil
        }
        let decoder = JournalCoding.decoder()
        var events: [JournalEvent] = []
        var skipped = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if let event = try? decoder.decode(JournalEvent.self, from: Data(line)) {
                events.append(event)
            } else {
                skipped += 1
            }
        }
        if skipped > 0 {
            Log.journal.error("Skipped \(skipped) unreadable journal lines")
        }
        return events
    }

    private func signature(of url: URL) -> FileSignature? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else { return nil }
        return FileSignature(size: size, modified: attributes[.modificationDate] as? Date)
    }

    private func deleteNow(_ files: [JournalDayFile]) {
        for file in files {
            remove(file.url)
            cache[file.url.lastPathComponent] = nil
        }
    }

    private func pruneNow(before cutoff: Date, now: Date) {
        let old = dayFilesNow().filter { $0.day < cutoff }
        guard let oldest = old.first else { return }

        var rollups = readJSON(JournalRollups.self, named: Self.rollupsName) ?? JournalRollups()
        let firstDay = rollups.coveredUntil ?? oldest.day
        if firstDay < cutoff {
            let timeline = JournalReplayer.replay(rollups.carry + readAllNow(), now: now)
            let folded = NutritionBuilder.dailyUsage(
                timeline: timeline, firstDay: firstDay, cutoff: cutoff, now: now, calendar: calendar)
            let foldedStarts = Set(folded.map(\.start))
            rollups.days = (rollups.days.filter { !foldedStarts.contains($0.start) } + folded).sorted { $0.start < $1.start }
            rollups.coveredUntil = cutoff
            rollups.carry = timeline.carry(at: cutoff)
            writeJSON(rollups, named: Self.rollupsName)
        }
        // Rollups are on disk before any day file goes.
        deleteNow(old)
    }

    private func appendNow(_ event: JournalEvent) {
        do {
            try ensureFolder()
            let url = baseURL.appending(path: fileName(for: event.at))
            var line = try JournalCoding.encoder().encode(event)
            let before = cache[url.lastPathComponent] == nil ? nil : signature(of: url)
            line.append(0x0A)
            if fileManager.fileExists(atPath: url.path) {
                try appendLine(line, to: url)
            } else if !fileManager.createFile(
                atPath: url.path, contents: line, attributes: [.posixPermissions: Self.fileMode])
            {
                Log.journal.error("Could not create a journal day file")
            }
            noteAppended(line, to: url, before: before)
        } catch {
            Log.journal.error("Journal write failed: \(String(describing: error))")
        }
    }

    /// Keeps a cached day in step with the line just written. Anything that does not add up drops the day,
    /// and the next read parses the file again.
    private func noteAppended(_ line: Data, to url: URL, before: FileSignature?) {
        let name = url.lastPathComponent
        guard var cached = cache[name] else { return }
        guard let before, cached.signature == before, let after = signature(of: url),
              let event = try? JournalCoding.decoder().decode(JournalEvent.self, from: line) else {
            cache[name] = nil
            return
        }
        cached.events.append(event)
        cached.signature = after
        cache[name] = cached
    }

    private func appendLine(_ line: Data, to url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { close(handle) }
        var data = line
        let size = try handle.seekToEnd()
        if size > 0 {
            try handle.seek(toOffset: size - 1)
            // A crash can leave a half-written last line: start ours on a fresh line.
            if try handle.read(upToCount: 1) != Data([0x0A]) {
                data.insert(0x0A, at: 0)
            }
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func close(_ handle: FileHandle) {
        do {
            try handle.close()
        } catch {
            Log.journal.error("Could not close a journal file: \(String(describing: error))")
        }
    }

    // MARK: JSON files (queue only)

    private func ensureFolder() throws {
        try fileManager.createDirectory(
            at: baseURL, withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.folderMode])
        try fileManager.setAttributes([.posixPermissions: Self.folderMode], ofItemAtPath: baseURL.path)
    }

    private func readJSON<T: Decodable>(_ type: T.Type, named name: String) -> T? {
        let url = baseURL.appending(path: name)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try JournalCoding.decoder().decode(type, from: Data(contentsOf: url))
        } catch {
            Log.journal.error("Could not read \(name): \(String(describing: error))")
            return nil
        }
    }

    private func writeJSON(_ value: some Encodable, named name: String) {
        do {
            try ensureFolder()
            let url = baseURL.appending(path: name)
            try JournalCoding.encoder(pretty: true).encode(value).write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: Self.fileMode], ofItemAtPath: url.path)
        } catch {
            Log.journal.error("Could not write \(name): \(String(describing: error))")
        }
    }

    private func remove(_ url: URL) {
        do {
            try fileManager.removeItem(at: url)
        } catch {
            Log.journal.error("Could not delete a journal file: \(String(describing: error))")
        }
    }
}
