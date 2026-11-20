import Foundation
import Testing

@testable import MacBull

@MainActor
struct JournalStorageTests {
    private typealias Fix = JournalFixtures

    private func makeJournal(_ folder: URL) -> Journal {
        Journal(baseURL: folder, calendar: Fix.calendar)
    }

    private func names(in folder: URL) -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return items.sorted()
    }

    @Test func appendAndReadRoundTrip() throws {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        let first = Fix.date(11, 18, 12, 0, 0).addingTimeInterval(0.25)
        let kinds: [(Date, JournalEventKind)] = [
            (first, .appLaunched),
            (Fix.date(11, 18, 12, 5), .awakeStarted(reason: "manual")),
            (Fix.date(11, 18, 12, 6), .sessionChanged(id: "s1", agent: "Claude Code", folder: nil, activity: .waitingForYou)),
            (Fix.date(11, 18, 12, 7), .safetyStop(.heat)),
            (Fix.date(11, 19, 0, 30), .thermal(level: 2)),
            (Fix.date(11, 19, 9, 0), .awakeEnded(reason: "timer")),
        ]
        for (at, kind) in kinds {
            journal.record(kind, at: at)
        }

        let events = journal.store.readAll()
        #expect(events == kinds.map { JournalEvent(at: $0.0, kind: $0.1) })
        #expect(names(in: folder) == ["2026-11-18.jsonl", "2026-11-19.jsonl"])
        let text = try String(contentsOf: folder.appending(path: "2026-11-18.jsonl"), encoding: .utf8)
        #expect(text.contains("2026-11-18T11:00:00.250Z"))
        #expect(text.split(separator: "\n").count == 4)
    }

    @Test func filesAreOwnerOnly() {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        journal.record(.appLaunched, at: Fix.date(11, 18, 12))
        journal.save(Receipt(
            id: UUID(), awayFrom: Fix.date(11, 18, 13), awayTo: Fix.date(11, 18, 14), lines: [], batteryStart: nil,
            batteryEnd: nil, pluggedIn: false, peakThermal: 0, sleptAt: [], safetyStop: .heat, notRunningSince: nil))
        _ = journal.previousRun()
        #expect(Fix.permissions(of: folder) == 0o700)
        #expect(Fix.permissions(of: folder.appending(path: "2026-11-18.jsonl")) == 0o600)
        #expect(Fix.permissions(of: folder.appending(path: "receipts.json")) == 0o600)
    }

    @Test func corruptLinesAreSkipped() throws {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        journal.record(.appLaunched, at: Fix.date(11, 18, 8))
        journal.flush()

        let file = folder.appending(path: "2026-11-18.jsonl")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json at all\n{\"at\":\"nope\"}\n\n{\"at\":\"2026-11-18T10:00:00.000Z\",\"kind\":{\"macSl".utf8))
        try handle.close()

        journal.record(.macWoke, at: Fix.date(11, 18, 13))
        let events = journal.store.readAll()
        #expect(events.map(\.kind) == [.appLaunched, .macWoke])
    }

    @Test func batteryEventsAreDeduplicated() {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        journal.record(.battery(percent: 80, onAC: false), at: Fix.date(11, 18, 12, 0))
        journal.record(.battery(percent: 80, onAC: false), at: Fix.date(11, 18, 12, 1))
        journal.record(.battery(percent: 79, onAC: false), at: Fix.date(11, 18, 12, 2))
        journal.record(.battery(percent: 79, onAC: true), at: Fix.date(11, 18, 12, 3))
        journal.record(.battery(percent: 79, onAC: true), at: Fix.date(11, 18, 12, 4))
        journal.record(.battery(percent: 79, onAC: false), at: Fix.date(11, 18, 12, 5))
        let samples = journal.store.readAll().compactMap { event -> Int? in
            if case let .battery(percent, _) = event.kind { percent } else { nil }
        }
        #expect(samples == [80, 79, 79, 79])
    }

    @Test func previousRunTellsCleanQuitFromCrash() {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = makeJournal(folder)
        #expect(first.previousRun() == nil)

        first.record(.appLaunched, at: Fix.date(11, 18, 9))
        first.record(.macSlept, at: Fix.date(11, 18, 18))
        first.record(.appQuit, at: Fix.date(11, 18, 18, 1))
        first.record(.battery(percent: 50, onAC: false), at: Fix.date(11, 18, 18, 2))

        first.flush()
        let clean = makeJournal(folder).previousRun()
        #expect(clean?.cleanQuit == true)
        #expect(clean?.lastEventAt == Fix.date(11, 18, 18, 1))

        let second = makeJournal(folder)
        second.record(.appLaunched, at: Fix.date(11, 19, 9))
        second.record(.awakeStarted(reason: "agents"), at: Fix.date(11, 19, 9, 5))
        // Asked after this launch was recorded: still about the run before it.
        #expect(second.previousRun()?.cleanQuit == true)

        second.flush()
        let third = makeJournal(folder)
        let crashed = third.previousRun()
        #expect(crashed?.cleanQuit == false)
        #expect(crashed?.lastEventAt == Fix.date(11, 19, 9, 5))
        third.record(.appLaunched, at: Fix.date(11, 19, 10))
        #expect(third.previousRun()?.lastEventAt == Fix.date(11, 19, 9, 5))
    }

    @Test func eraseAllRemovesEverything() {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        let now = Fix.date(11, 19, 12)
        for day in 1...12 {
            journal.record(.awakeStarted(reason: "manual"), at: Fix.date(11, day, 10))
            journal.record(.awakeEnded(reason: "user"), at: Fix.date(11, day, 11))
        }
        journal.prune(keepDays: 3, now: now)
        journal.flush()
        journal.save(Receipt(
            id: UUID(), awayFrom: Fix.date(11, 18, 13), awayTo: Fix.date(11, 18, 14), lines: [], batteryStart: nil,
            batteryEnd: nil, pluggedIn: false, peakThermal: 0, sleptAt: [], safetyStop: .battery, notRunningSince: nil))
        #expect(names(in: folder).contains("rollups.json"))

        journal.eraseAll()
        #expect(names(in: folder).isEmpty)
        #expect(journal.previousRun() == nil)
        #expect(journal.savedReceipts().isEmpty)
        #expect(journal.nutrition(.allTime, now: now) == .empty)
    }

    @Test func pruneFoldsOldDaysIntoRollups() {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        let now = Fix.date(11, 19, 12)
        // Ten days, one can per day: awake 10:00-12:00, a Claude run 10:30-11:30 that finishes.
        for day in 9...19 {
            journal.record(.awakeStarted(reason: "agents"), at: Fix.date(11, day, 10))
            journal.record(Self.sessionKind("s\(day)", .working), at: Fix.date(11, day, 10, 30))
            journal.record(Self.sessionKind("s\(day)", .turnDone), at: Fix.date(11, day, 11, 30))
            journal.record(.awakeEnded(reason: "agentsDone"), at: Fix.date(11, day, 12))
        }
        let before = journal.nutrition(.allTime, now: now)
        #expect(before.cansOpened == 11)
        #expect(before.awakeSeconds == 11 * 2 * 3600)
        #expect(before.agentSeconds == 11 * 3600)

        journal.prune(keepDays: 3, now: now)
        journal.flush()

        #expect(names(in: folder) == ["2026-11-16.jsonl", "2026-11-17.jsonl", "2026-11-18.jsonl", "2026-11-19.jsonl", "rollups.json"])
        let rollups = journal.store.loadRollups()
        #expect(rollups.days.count == 7)
        #expect(rollups.coveredUntil == Fix.date(11, 16, 0))
        #expect(journal.nutrition(.allTime, now: now) == before)
        #expect(journal.nutrition(.week, now: now).cansOpened == 7)
        #expect(journal.nutrition(.today, now: now).cansOpened == 1)

        // A second prune later folds more and still adds up.
        let later = Fix.date(11, 21, 12)
        journal.prune(keepDays: 3, now: later)
        #expect(journal.store.loadRollups().days.count == 9)
        #expect(journal.nutrition(.allTime, now: later).cansOpened == 11)
        #expect(journal.nutrition(.allTime, now: later).awakeSeconds == before.awakeSeconds)
    }

    @Test func pruneKeepsAnIntervalThatCrossesTheCutoff() {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        let now = Fix.date(11, 19, 12)
        journal.record(.awakeStarted(reason: "manual"), at: Fix.date(11, 10, 20))
        journal.record(.awakeEnded(reason: "user"), at: Fix.date(11, 17, 6))
        journal.record(Self.sessionKind("long", .working), at: Fix.date(11, 10, 21))
        journal.record(Self.sessionKind("long", .waitingForYou), at: Fix.date(11, 12, 3))
        journal.record(Self.sessionKind("long", .working), at: Fix.date(11, 12, 4))
        journal.record(Self.sessionKind("long", .turnDone), at: Fix.date(11, 17, 5))
        journal.record(Self.sessionKind("still", .working), at: Fix.date(11, 14, 8))
        let before = journal.nutrition(.allTime, now: now)
        #expect(before.longestRunSeconds == 154 * 3600)
        journal.prune(keepDays: 3, now: now)
        let after = journal.nutrition(.allTime, now: now)
        #expect(after == before)
        #expect(after.sessionsFinished == 1)
        #expect(journal.store.loadRollups().carry.count == 3)
    }

    @Test func savedReceiptsKeepTenMostRecentFirst() {
        let folder = Fix.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = makeJournal(folder)
        #expect(journal.savedReceipts().isEmpty)
        var ids: [UUID] = []
        for day in 1...12 {
            let id = UUID()
            ids.append(id)
            journal.save(Receipt(
                id: id, awayFrom: Fix.date(11, day, 20), awayTo: Fix.date(11, day, 23), lines: [
                    ReceiptLine(agent: "Codex", folder: "api", outcome: .stillWorking),
                ], batteryStart: 90, batteryEnd: 70, pluggedIn: false, peakThermal: 1,
                sleptAt: [Fix.date(11, day, 21)], safetyStop: nil, notRunningSince: nil))
        }
        journal.flush()
        let saved = makeJournal(folder).savedReceipts()
        #expect(saved.count == 10)
        #expect(saved.map(\.id) == ids.suffix(10).reversed())
        #expect(saved.first?.lines.first?.outcome == .stillWorking)
        #expect(saved.first?.sleptAt == [Fix.date(11, 12, 21)])
    }

    private static func sessionKind(_ id: String, _ activity: SessionActivity) -> JournalEventKind {
        .sessionChanged(id: id, agent: "Claude Code", folder: "api", activity: activity)
    }
}
