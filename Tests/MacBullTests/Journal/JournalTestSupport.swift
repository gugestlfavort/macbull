import Foundation

@testable import MacBull

/// Fixed clock and calendar for journal tests: nothing reads the wall clock.
enum JournalFixtures {
    static let zurich = TimeZone(identifier: "Europe/Zurich") ?? .gmt

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zurich
        return calendar
    }

    /// Local time in Zurich.
    static func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, year: Int = 2026) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return calendar.date(from: parts) ?? .distantPast
    }

    static func event(_ at: Date, _ kind: JournalEventKind) -> JournalEvent {
        JournalEvent(at: at, kind: kind)
    }

    static func session(
        _ at: Date, _ id: String, _ activity: SessionActivity, agent: String = "Claude Code", folder: String? = "api"
    ) -> JournalEvent {
        event(at, .sessionChanged(id: id, agent: agent, folder: folder, activity: activity))
    }

    static func makeTempFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "macbull-journal-\(UUID().uuidString)")
    }

    static func permissions(of url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? Int).map { $0 & 0o777 }
    }
}
