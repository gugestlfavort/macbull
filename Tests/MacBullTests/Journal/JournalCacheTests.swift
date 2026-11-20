import Foundation
import Testing

@testable import MacBull

@MainActor
struct JournalCacheTests {
    private typealias Fix = JournalFixtures

    private func makeJournal(_ folder: URL) -> Journal {
        Journal(baseURL: folder, calendar: Fix.calendar)
    }

    private func dayFile(_ folder: URL, _ month: Int, _ day: Int) -> URL {
        folder.appending(path: "2026-\(String(format: "%02d", month))-\(String(format: "%02d", day)).jsonl")
    }

    // MARK: Cache behaviour

    @Test func aSecondReadServesTheParsedEventsWithoutDecodingTheFileAgain() throws {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        journal.record(.appLaunched, at: Fix.date(11, 19, 9))
        journal.record(.awakeStarted(reason: "manual"), at: Fix.date(11, 19, 10))
        journal.flush()
        // A whole-second modification time, so it can be put back exactly after the file is overwritten.
        let url = dayFile(folder, 11, 19)
        let stamp = Fix.date(11, 19, 11)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        let first = journal.store.readAll()
        #expect(first.count == 2)

        // Same size, same modification time, different bytes: only a cache would not notice.
        let size = try #require((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue)
        try Data(repeating: UInt8(ascii: "x"), count: size).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        #expect(journal.store.readAll() == first)
    }

    @Test func aFileChangedBehindTheStoresBackIsParsedAgain() throws {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        journal.record(.appLaunched, at: Fix.date(11, 19, 9))
        #expect(journal.store.readAll().count == 1)
        let line = try JournalCoding.encoder().encode(Fix.event(Fix.date(11, 19, 10), .macSlept))
        let handle = try FileHandle(forWritingTo: dayFile(folder, 11, 19))
        try handle.seekToEnd()
        try handle.write(contentsOf: line + Data([0x0A]))
        try handle.close()
        #expect(journal.store.readAll().map(\.kind) == [.appLaunched, .macSlept])
    }

    @Test func eventsRecordedAfterARead_andAnotherReadOfAFreshStore_agree() {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        journal.record(.appLaunched, at: Fix.date(11, 18, 22))
        _ = journal.store.readAll()
        journal.record(.awakeStarted(reason: "manual"), at: Fix.date(11, 18, 23))
        journal.record(.awakeEnded(reason: "user"), at: Fix.date(11, 19, 1))
        journal.record(.macSlept, at: Fix.date(11, 19, 2))
        let cached = journal.store.readAll()
        #expect(cached.count == 4)
        let fresh = JournalStore(baseURL: folder, calendar: Fix.calendar, fileManager: .default).readAll()
        #expect(cached == fresh)
    }

    @Test func aHalfWrittenLastLineDoesNotConfuseTheCacheAfterAnAppend() throws {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        journal.record(.appLaunched, at: Fix.date(11, 19, 9))
        journal.flush()
        // A crash left half a line at the end.
        let handle = try FileHandle(forWritingTo: dayFile(folder, 11, 19))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"at":"2026-11-19T1"#.utf8))
        try handle.close()
        #expect(journal.store.readAll().count == 1)
        journal.record(.macSlept, at: Fix.date(11, 19, 10))
        let cached = journal.store.readAll()
        #expect(cached.map(\.kind) == [.appLaunched, .macSlept])
        #expect(cached == JournalStore(baseURL: folder, calendar: Fix.calendar, fileManager: .default).readAll())
    }

    @Test func pruneAndEraseDropWhatTheyDelete() {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        let now = Fix.date(11, 19, 12)
        for day in 10...19 {
            journal.record(.awakeStarted(reason: "manual"), at: Fix.date(11, day, 10))
            journal.record(.awakeEnded(reason: "user"), at: Fix.date(11, day, 11))
        }
        #expect(journal.store.readAll().count == 20)
        journal.prune(keepDays: 3, now: now)
        #expect(journal.store.readAll().count == 8, "the four days that stay; the read waited for the prune")
        journal.eraseAll()
        #expect(journal.store.readAll().isEmpty)
        journal.record(.appLaunched, at: Fix.date(11, 19, 13))
        #expect(journal.store.readAll().map(\.kind) == [.appLaunched])
    }

    @Test func pruneReturnsBeforeItsWorkIsDoneAndFlushWaitsForIt() {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        for day in 1...12 {
            journal.record(.awakeStarted(reason: "manual"), at: Fix.date(11, day, 10))
            journal.record(.awakeEnded(reason: "user"), at: Fix.date(11, day, 11))
        }
        journal.flush()
        journal.prune(keepDays: 3, now: Fix.date(11, 19, 12))
        journal.flush()
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        #expect(names == ["rollups.json"], "all twelve days are older than the cutoff")
    }

    // MARK: Replay order

    @Test func replayOrderKeepsFileOrderForTiesAndSortsOnlyWhenNeeded() {
        let t0 = Fix.date(11, 19, 9)
        let t1 = Fix.date(11, 19, 10)
        let inOrder = [Fix.event(t0, .appLaunched), Fix.event(t0, .macSlept), Fix.event(t1, .macWoke)]
        #expect(JournalReplayer.sorted(inOrder) == inOrder)
        let shuffled = [inOrder[2], inOrder[0], inOrder[1]]
        #expect(JournalReplayer.sorted(shuffled) == inOrder, "later event first in the file: sorted by time, the tie keeps file order")
        #expect(JournalReplayer.sorted([]).isEmpty)
    }

    // MARK: Cost

    /// 90 days of 500 events each, written straight to day files.
    private func writeBusyHistory(into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JournalCoding.encoder()
        let firstDay = Fix.calendar.date(byAdding: .day, value: -89, to: Fix.date(11, 19, 0)) ?? Fix.date(11, 19, 0)
        for offset in 0..<90 {
            let midnight = Fix.calendar.date(byAdding: .day, value: offset, to: firstDay) ?? firstDay
            // In time order, as an app that appends them would have written them.
            var moments: [(second: Int, kind: JournalEventKind)] = [(0, .awakeStarted(reason: "agents"))]
            for index in 0..<249 {
                let id = "s\(index % 4)"
                moments.append((10 + index * 60, .sessionChanged(id: id, agent: "Claude Code", folder: "api", activity: index % 2 == 0 ? .working : .waitingForYou)))
                moments.append((20 + index * 60, .battery(percent: 100 - index % 90, onAC: index % 7 == 0)))
            }
            moments.append((20_000, .awakeEnded(reason: "agentsDone")))
            moments.sort { $0.second < $1.second }
            var data = Data()
            for moment in moments {
                let event = Fix.event(midnight.addingTimeInterval(TimeInterval(8 * 3600 + moment.second)), moment.kind)
                data.append(try encoder.encode(event))
                data.append(0x0A)
            }
            let name = JournalDayName.name(for: midnight, calendar: Fix.calendar)
            try data.write(to: folder.appending(path: "\(name).jsonl"))
        }
    }

    @Test func nutritionOverNinetyBusyDaysIsQuickOnTheSecondCall() throws {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writeBusyHistory(into: folder)
        let journal = makeJournal(folder)
        let now = Fix.date(11, 19, 12)

        let cold = journal.nutrition(.allTime, now: now)
        #expect(journal.store.readAll().count == 90 * 500)

        // Second call and after: nothing is decoded any more. Best of three, so a busy test machine does not fail it.
        let clock = ContinuousClock()
        var best = Duration.seconds(60)
        for _ in 0..<3 {
            var warm = NutritionStats.empty
            best = min(best, clock.measure { warm = journal.nutrition(.allTime, now: now) })
            #expect(warm == cold)
        }
        #expect(best < .milliseconds(50), "took \(best)")
    }
}
