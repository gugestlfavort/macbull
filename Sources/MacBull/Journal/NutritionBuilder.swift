import Foundation

/// What a stretch of time added up to. Also the per-day record kept in `rollups.json`.
struct JournalUsage: Codable, Equatable, Sendable {
    /// Waiting episodes kept per usage record for the median; the total stays exact.
    static let maxWaitsKept = 500

    var cansOpened = 0
    var awakeSeconds: TimeInterval = 0
    var agentSecondsByAgent: [String: TimeInterval] = [:]
    var longestRunSeconds: TimeInterval = 0
    var sessionsFinished = 0
    var waitedSeconds: TimeInterval = 0
    var waits: [TimeInterval] = []
    var batterySpentAway = 0
    var safetyStops = 0

    var isEmpty: Bool { self == JournalUsage() }

    mutating func add(_ other: JournalUsage) {
        cansOpened += other.cansOpened
        awakeSeconds += other.awakeSeconds
        for (agent, seconds) in other.agentSecondsByAgent {
            agentSecondsByAgent[agent, default: 0] += seconds
        }
        longestRunSeconds = max(longestRunSeconds, other.longestRunSeconds)
        sessionsFinished += other.sessionsFinished
        waitedSeconds += other.waitedSeconds
        waits.append(contentsOf: other.waits)
        batterySpentAway += other.batterySpentAway
        safetyStops += other.safetyStops
    }
}

/// One folded day: the usage clipped to that local calendar day.
struct DayRollup: Codable, Equatable, Sendable {
    /// Local midnight that starts the day.
    var start: Date
    /// Label for people reading the file, "YYYY-MM-DD".
    var day: String
    var usage: JournalUsage
}

struct JournalRollups: Codable, Equatable, Sendable {
    /// Everything before this moment is in `days`, not in the day files.
    var coveredUntil: Date?
    /// What was in progress at `coveredUntil` (see `JournalTimeline.carry(at:)`).
    var carry: [JournalEvent] = []
    var days: [DayRollup] = []
}

extension JournalTimeline {
    /// Usage inside [lower, upper). Intervals are clipped, and never run past `now`.
    func usage(from lower: Date, to upper: Date, now: Date) -> JournalUsage {
        let cap = min(upper, now)
        var usage = JournalUsage()
        usage.cansOpened = awakeStarts.filter { $0 >= lower && $0 < upper }.count
        usage.awakeSeconds = awakeSegments.map { $0.seconds(from: lower, to: cap) }.reduce(0, +)
        // A run belongs to the range it ends in, and counts whole: it may have begun the day before.
        usage.longestRunSeconds = awakeSegments.filter { $0.end > lower && $0.end <= upper }.map(\.duration).max() ?? 0
        usage.sessionsFinished = finishes.filter { $0.finishedAt >= lower && $0.finishedAt < upper }.count
        usage.batterySpentAway = awayBatteryDrops.filter { $0.at >= lower && $0.at < upper }.map(\.points).reduce(0, +)
        usage.safetyStops = safetyStops.filter { $0.at >= lower && $0.at < upper }.count
        addSessionTime(to: &usage, from: lower, to: cap, now: now)
        return usage
    }

    private func addSessionTime(to usage: inout JournalUsage, from lower: Date, to cap: Date, now: Date) {
        for track in tracks {
            for segment in track.segments {
                let span = JournalSpan(segment.start, segment.end ?? now)
                let seconds = span.seconds(from: lower, to: cap)
                if JournalActivity.isBusy(segment.activity), seconds > 0 {
                    usage.agentSecondsByAgent[track.agent, default: 0] += seconds
                } else if segment.activity == .waitingForYou, seconds > 0 {
                    usage.waitedSeconds += seconds
                    usage.waits.append(seconds)
                }
            }
        }
        usage.waits = Array(usage.waits.prefix(JournalUsage.maxWaitsKept))
    }
}

/// The Nutrition Facts label, from events and rollups. Pure: no clock, no files.
enum NutritionBuilder {
    static func stats(
        events: [JournalEvent], rollups: JournalRollups, range: StatsRange, now: Date, calendar: Calendar
    ) -> NutritionStats {
        let timeline = JournalReplayer.replay(rollups.carry + events, now: now)
        let today = calendar.startOfDay(for: now)
        let tomorrow = nextDay(after: today, calendar: calendar)
        let bounds = bounds(of: range, today: today, tomorrow: tomorrow, calendar: calendar)

        var usage = JournalUsage()
        for day in rollups.days where day.start >= bounds.lower && day.start < bounds.upper {
            usage.add(day.usage)
        }
        let eventsLower = max(bounds.lower, rollups.coveredUntil ?? .distantPast)
        usage.add(timeline.usage(from: eventsLower, to: bounds.upper, now: now))

        let empties = timeline.finishes.filter { $0.finishedAt >= today && $0.finishedAt < tomorrow }.count
        return label(from: usage, emptiesToday: empties)
    }

    /// Per-day usage for the calendar days [firstDay, cutoff), for folding into rollups.
    static func dailyUsage(
        timeline: JournalTimeline, firstDay: Date, cutoff: Date, now: Date, calendar: Calendar
    ) -> [DayRollup] {
        var result: [DayRollup] = []
        var day = firstDay
        while day < cutoff {
            let next = nextDay(after: day, calendar: calendar)
            guard next > day else { break }
            let usage = timeline.usage(from: day, to: next, now: now)
            if !usage.isEmpty {
                result.append(DayRollup(start: day, day: JournalDayName.name(for: day, calendar: calendar), usage: usage))
            }
            day = next
        }
        return result
    }

    static func nextDay(after day: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
    }

    private static func bounds(
        of range: StatsRange, today: Date, tomorrow: Date, calendar: Calendar
    ) -> (lower: Date, upper: Date) {
        switch range {
        case .today:
            return (today, tomorrow)
        case .week:
            let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return (weekStart, tomorrow)
        case .allTime:
            return (.distantPast, tomorrow)
        }
    }

    private static func label(from usage: JournalUsage, emptiesToday: Int) -> NutritionStats {
        let agentSeconds = usage.agentSecondsByAgent.values.reduce(0, +)
        return NutritionStats(
            cansOpened: usage.cansOpened,
            awakeSeconds: usage.awakeSeconds,
            agentSeconds: agentSeconds,
            longestRunSeconds: usage.longestRunSeconds,
            sessionsFinished: usage.sessionsFinished,
            waitedForYouSeconds: usage.waitedSeconds,
            waitedForYouMedianSeconds: median(usage.waits),
            batterySpentAway: usage.batterySpentAway,
            safetyStops: usage.safetyStops,
            agentMix: mix(usage.agentSecondsByAgent, total: agentSeconds),
            emptiesToday: emptiesToday
        )
    }

    static func median(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func mix(_ byAgent: [String: TimeInterval], total: TimeInterval) -> [AgentShare] {
        guard total > 0 else { return [] }
        return byAgent
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            .map { AgentShare(agent: $0.key, share: $0.value / total) }
    }
}

/// "YYYY-MM-DD" names for day files.
enum JournalDayName {
    static func name(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Local midnight for a "YYYY-MM-DD" name; nil when it is not a day name.
    static func date(from name: String, calendar: Calendar) -> Date? {
        let pieces = name.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard pieces.count == 3, let year = pieces[0], let month = pieces[1], let day = pieces[2] else { return nil }
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return Self.name(for: date, calendar: calendar) == name ? calendar.startOfDay(for: date) : nil
    }
}
