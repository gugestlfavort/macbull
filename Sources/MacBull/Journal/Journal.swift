import Foundation

/// The local event journal: append-only day files, receipts and the Nutrition Facts numbers.
/// Never leaves the Mac; never holds prompts, tool input or full paths (the event type has no room
/// for them).
@MainActor
final class Journal: EventJournaling {
    /// Receipts kept for the panel footer.
    static let maxSavedReceipts = 10

    private struct BatteryState: Equatable {
        var percent: Int
        var onAC: Bool
    }

    let store: JournalStore
    private let calendar: Calendar
    private let makeID: () -> UUID
    private var lastBattery: BatteryState?
    private var launchedAt: Date?
    private var quitRecorded = false

    /// `baseURL` defaults to `~/Library/Application Support/MacBull/journal/`.
    init(
        baseURL: URL? = nil,
        calendar: Calendar = .current,
        fileManager: FileManager = .default,
        makeID: @escaping () -> UUID = { UUID() }
    ) {
        self.calendar = calendar
        self.makeID = makeID
        store = JournalStore(
            baseURL: baseURL ?? Self.defaultBaseURL(fileManager),
            calendar: calendar,
            fileManager: fileManager
        )
    }

    static func defaultBaseURL(_ fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "MacBull").appending(path: "journal")
    }

    // MARK: EventJournaling

    func record(_ kind: JournalEventKind, at: Date) {
        if kind == .appLaunched {
            quitRecorded = false
            launchedAt = launchedAt ?? at
        }
        // After a clean quit nothing more is written, or the next launch would see a crash.
        guard !quitRecorded else { return }
        if case let .battery(percent, onAC) = kind {
            let state = BatteryState(percent: percent, onAC: onAC)
            guard state != lastBattery else { return }
            lastBattery = state
        }
        if kind == .appQuit {
            quitRecorded = true
        }
        store.append(JournalEvent(at: at, kind: kind))
    }

    func receipt(from: Date, to: Date) -> Receipt {
        ReceiptBuilder.build(events: store.readAll(), from: from, to: to, id: makeID())
    }

    func savedReceipts() -> [Receipt] {
        store.loadReceipts()
    }

    func save(_ receipt: Receipt) {
        var receipts = store.loadReceipts().filter { $0.id != receipt.id }
        receipts.append(receipt)
        receipts.sort { $0.awayTo > $1.awayTo }
        store.saveReceipts(Array(receipts.prefix(Self.maxSavedReceipts)))
    }

    func nutrition(_ range: StatsRange, now: Date) -> NutritionStats {
        NutritionBuilder.stats(
            events: store.readAll(), rollups: store.loadRollups(), range: range, now: now, calendar: calendar)
    }

    func previousRun() -> (lastEventAt: Date, cleanQuit: Bool)? {
        var events = JournalReplayer.sorted(store.readAll())
        if let launchedAt {
            events = events.filter { $0.at < launchedAt }
        }
        guard let last = events.last else { return nil }
        return (last.at, last.kind == .appQuit)
    }

    /// Deletes day files older than `keepDays` days, after folding them into `rollups.json`. The work runs on the
    /// journal queue, after the writes queued before it; reads wait for it, `flush()` does too.
    func prune(keepDays: Int, now: Date) {
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -max(1, keepDays), to: today) ?? today
        store.prune(before: cutoff, now: now)
    }

    /// Waits until queued writes are on disk.
    func flush() {
        store.flush()
    }

    func eraseAll() {
        store.eraseAll()
        lastBattery = nil
    }
}
