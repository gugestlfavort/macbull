import Foundation

/// "While you were away": the receipt for one away window. Pure: no clock, no files.
enum ReceiptBuilder {
    /// `events` is the whole journal (or at least the last known state before the window and
    /// everything in it); events after `to` are ignored.
    static func build(events: [JournalEvent], from: Date, to: Date, id: UUID = UUID()) -> Receipt {
        let visible = events.filter { $0.at <= to }
        let timeline = JournalReplayer.replay(visible, now: to)
        let battery = batteryFacts(timeline.batterySamples, from: from)
        return Receipt(
            id: id,
            awayFrom: from,
            awayTo: to,
            lines: lines(timeline, from: from, to: to),
            batteryStart: battery.start,
            batteryEnd: battery.end,
            pluggedIn: battery.pluggedIn,
            peakThermal: peakThermal(timeline.thermalSamples, from: from),
            sleptAt: timeline.sleptAt.filter { $0 >= from },
            safetyStop: timeline.safetyStops.first { $0.at >= from }?.stop,
            notRunningSince: timeline.launchGaps.first { $0.launchedAt >= from }?.lastAliveAt
        )
    }

    // MARK: Battery and heat

    private static func batteryFacts(
        _ samples: [JournalBatterySample], from: Date
    ) -> (start: Int?, end: Int?, pluggedIn: Bool) {
        let start = samples.last { $0.at <= from } ?? samples.first { $0.at > from }
        let end = samples.last
        return (start?.percent, end?.percent, end?.onAC ?? false)
    }

    private static func peakThermal(_ samples: [JournalThermalSample], from: Date) -> Int {
        let before = samples.last { $0.at <= from }?.level ?? 0
        let during = samples.filter { $0.at > from }.map(\.level).max() ?? 0
        return max(before, during)
    }

    // MARK: Sessions

    private static func lines(_ timeline: JournalTimeline, from: Date, to: Date) -> [ReceiptLine] {
        var found: [(line: ReceiptLine, order: Date)] = []
        for track in timeline.tracks {
            let finishes = timeline.finishes.filter { $0.sessionID == track.id }
            guard let outcome = outcome(of: track, finishes: finishes, from: from, to: to) else { continue }
            let runs = finishes.filter { $0.finishedAt >= from && $0.finishedAt <= to }
            let line = ReceiptLine(
                agent: track.agent, folder: track.folder, outcome: outcome,
                turns: runs.count,
                workSeconds: runs.reduce(0) { $0 + $1.finishedAt.timeIntervalSince($1.startedAt) })
            found.append((line, moment(of: outcome)))
        }
        return found.sorted { lhs, rhs in
            let lhsRank = rank(lhs.line.outcome)
            let rhsRank = rank(rhs.line.outcome)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhs.order != rhs.order {
                return lhs.order > rhs.order
            }
            if lhs.line.agent != rhs.line.agent {
                return lhs.line.agent < rhs.line.agent
            }
            return (lhs.line.folder ?? "") < (rhs.line.folder ?? "")
        }.map(\.line)
    }

    private static func outcome(
        of track: JournalSessionTrack, finishes: [JournalRunFinish], from: Date, to: Date
    ) -> ReceiptOutcome? {
        guard let last = track.segments.last else { return nil }
        if last.end == nil, let live = liveOutcome(last) {
            return live
        }
        if let finish = finishes.last(where: { $0.finishedAt >= from && $0.finishedAt <= to }) {
            return .finished(at: finish.finishedAt, afterSeconds: finish.finishedAt.timeIntervalSince(finish.startedAt))
        }
        return closedOutcome(track, last: last, from: from)
    }

    private static func liveOutcome(_ segment: JournalSegment) -> ReceiptOutcome? {
        if JournalActivity.isBusy(segment.activity) {
            return .stillWorking
        }
        switch segment.activity {
        case .waitingForYou: return .waitingForYou(since: segment.start)
        case .stalled: return .stalled(since: segment.start)
        default: return nil
        }
    }

    /// A session that went away without finishing: cut off by a restart, or closed while it waited.
    private static func closedOutcome(_ track: JournalSessionTrack, last: JournalSegment, from: Date) -> ReceiptOutcome? {
        if last.closedByRestart, JournalActivity.isLive(last.activity), let end = last.end, end >= from {
            return .ended(at: end)
        }
        guard last.activity == .ended, last.start >= from, track.segments.count >= 2 else { return nil }
        let before = track.segments[track.segments.count - 2].activity
        if before == .waitingForYou || before == .stalled {
            return .ended(at: last.start)
        }
        return nil
    }

    private static func rank(_ outcome: ReceiptOutcome) -> Int {
        switch outcome {
        case .waitingForYou: 0
        case .stalled: 1
        case .stillWorking: 2
        case .finished: 3
        case .ended: 4
        }
    }

    private static func moment(of outcome: ReceiptOutcome) -> Date {
        switch outcome {
        case let .finished(at, _): at
        case let .waitingForYou(since): since
        case let .stalled(since): since
        case let .ended(at): at
        case .stillWorking: .distantPast
        }
    }
}
