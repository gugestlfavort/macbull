import Foundation

// A replay of the journal's events into plain intervals. The receipt and the nutrition label are
// both read from this one structure, so they cannot disagree about what happened.

/// A span of time with `end >= start`.
struct JournalSpan: Equatable, Sendable {
    var start: Date
    var end: Date

    init(_ start: Date, _ end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Seconds of the span that fall inside [lower, upper).
    func seconds(from lower: Date, to upper: Date) -> TimeInterval {
        max(0, min(end, upper).timeIntervalSince(max(start, lower)))
    }
}

enum JournalActivity {
    /// Counts as agent time: the agent is doing work.
    static func isBusy(_ activity: SessionActivity) -> Bool {
        switch activity {
        case .working, .backgroundRun, .running: true
        case .waitingForYou, .turnDone, .idle, .stalled, .ended: false
        }
    }

    /// Still in play: busy, waiting for the user or stalled.
    static func isLive(_ activity: SessionActivity) -> Bool {
        isBusy(activity) || activity == .waitingForYou || activity == .stalled
    }
}

/// One stretch in which a session kept the same activity.
struct JournalSegment: Equatable, Sendable {
    var activity: SessionActivity
    var start: Date
    /// nil while the activity goes on (runs to "now"). `ended` segments are zero-length.
    var end: Date?
    /// Cut short because MacBull quit or crashed; what happened next is unknown.
    var closedByRestart = false
}

struct JournalSessionTrack: Equatable, Sendable {
    var id: String
    var agent: String
    var folder: String?
    var segments: [JournalSegment] = []
}

/// A working run that ended: the agent finished.
struct JournalRunFinish: Equatable, Sendable {
    var sessionID: String
    var agent: String
    var startedAt: Date
    var finishedAt: Date
}

struct JournalBatterySample: Equatable, Sendable {
    var at: Date
    var percent: Int
    var onAC: Bool
}

struct JournalThermalSample: Equatable, Sendable {
    var at: Date
    var level: Int
}

struct JournalStopMark: Equatable, Sendable {
    var at: Date
    var stop: SafetyStop
}

struct JournalBatteryDrop: Equatable, Sendable {
    var at: Date
    var points: Int
}

/// MacBull started without a clean quit before it.
struct JournalLaunchGap: Equatable, Sendable {
    var launchedAt: Date
    var lastAliveAt: Date
}

struct JournalTimeline: Equatable, Sendable {
    /// Every awakeStarted, for "cans opened".
    var awakeStarts: [Date] = []
    /// Awake periods with the time the Mac slept taken out, so each one is continuous.
    var awakeSegments: [JournalSpan] = []
    /// The awake and asleep periods as recorded, before the sleep is taken out.
    var awakeSpans: [JournalSpan] = []
    var sleepSpans: [JournalSpan] = []
    var sleptAt: [Date] = []
    var tracks: [JournalSessionTrack] = []
    var finishes: [JournalRunFinish] = []
    /// Battery percentage points lost while away and on battery.
    var awayBatteryDrops: [JournalBatteryDrop] = []
    var safetyStops: [JournalStopMark] = []
    var batterySamples: [JournalBatterySample] = []
    var thermalSamples: [JournalThermalSample] = []
    var launchGaps: [JournalLaunchGap] = []
}

/// Replays events in time order. State that was open when MacBull quit is closed at the quit; state
/// open at a crash is closed at the last event seen before the next launch.
struct JournalReplayer {
    /// A working run that ended in idle (agents without hooks) shorter than this is a blip.
    static let idleBlipSeconds: TimeInterval = 120

    private let now: Date
    private var timeline = JournalTimeline()
    private var tracks: [String: JournalSessionTrack] = [:]
    private var awakeOpen: Date?
    private var sleepOpen: Date?
    private var awakeRaw: [JournalSpan] = []
    private var sleeps: [JournalSpan] = []
    private var away = false
    private var lastBattery: JournalBatterySample?
    private var previousAt: Date?
    private var previousWasQuit = false

    static func replay(_ events: [JournalEvent], now: Date) -> JournalTimeline {
        var replayer = JournalReplayer(now: now)
        for event in sorted(events) {
            replayer.apply(event)
        }
        return replayer.finish()
    }

    /// By time; events with the same time keep their file order.
    static func sorted(_ events: [JournalEvent]) -> [JournalEvent] {
        // Day files are appended in time order, so this is nearly always already true: skip the sort.
        if zip(events, events.dropFirst()).allSatisfy({ $0.at <= $1.at }) { return events }
        return events.enumerated().sorted { lhs, rhs in
            if lhs.element.at != rhs.element.at {
                return lhs.element.at < rhs.element.at
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private init(now: Date) {
        self.now = now
    }

    // MARK: Events

    private mutating func apply(_ event: JournalEvent) {
        let at = event.at
        switch event.kind {
        case .appLaunched: applyLaunch(at)
        case .appQuit: closeAll(at: at)
        case .awakeStarted: applyAwakeStart(at)
        case .awakeEnded: applyAwakeEnd(at)
        case let .sessionChanged(id, agent, folder, activity):
            applySession(id: id, agent: agent, folder: folder, activity: activity, at: at)
        case .macSlept: applySleep(at)
        case .macWoke: applyWake(at)
        case let .battery(percent, onAC): applyBattery(JournalBatterySample(at: at, percent: percent, onAC: onAC))
        case let .thermal(level): timeline.thermalSamples.append(JournalThermalSample(at: at, level: level))
        case let .safetyStop(stop): timeline.safetyStops.append(JournalStopMark(at: at, stop: stop))
        case .awayStarted: away = true
        case .awayEnded: away = false
        }
        previousAt = at
        previousWasQuit = event.kind == .appQuit
    }

    private mutating func applyLaunch(_ at: Date) {
        guard let lastAlive = previousAt, !previousWasQuit else { return }
        timeline.launchGaps.append(JournalLaunchGap(launchedAt: at, lastAliveAt: lastAlive))
        closeAll(at: lastAlive)
    }

    private mutating func closeAll(at moment: Date) {
        if let start = awakeOpen {
            awakeRaw.append(JournalSpan(start, moment))
            awakeOpen = nil
        }
        if let start = sleepOpen {
            sleeps.append(JournalSpan(start, moment))
            sleepOpen = nil
        }
        away = false
        for id in tracks.keys {
            closeOpenSegment(of: id, at: moment)
        }
    }

    private mutating func closeOpenSegment(of id: String, at moment: Date) {
        guard var track = tracks[id], var last = track.segments.popLast(), last.end == nil else { return }
        last.end = max(moment, last.start)
        last.closedByRestart = true
        track.segments.append(last)
        tracks[id] = track
    }

    private mutating func applyAwakeStart(_ at: Date) {
        timeline.awakeStarts.append(at)
        if awakeOpen == nil {
            awakeOpen = at
        }
    }

    private mutating func applyAwakeEnd(_ at: Date) {
        if let start = awakeOpen {
            awakeRaw.append(JournalSpan(start, at))
            awakeOpen = nil
        }
    }

    private mutating func applySleep(_ at: Date) {
        timeline.sleptAt.append(at)
        if sleepOpen == nil {
            sleepOpen = at
        }
    }

    private mutating func applyWake(_ at: Date) {
        if let start = sleepOpen {
            sleeps.append(JournalSpan(start, at))
            sleepOpen = nil
        }
    }

    private mutating func applyBattery(_ sample: JournalBatterySample) {
        if away, let previous = lastBattery, !previous.onAC, !sample.onAC, sample.percent < previous.percent {
            timeline.awayBatteryDrops.append(
                JournalBatteryDrop(at: sample.at, points: previous.percent - sample.percent))
        }
        lastBattery = sample
        timeline.batterySamples.append(sample)
    }

    private mutating func applySession(
        id: String, agent: String, folder: String?, activity: SessionActivity, at: Date
    ) {
        var track = tracks[id] ?? JournalSessionTrack(id: id, agent: agent, folder: folder)
        track.agent = agent
        track.folder = folder ?? track.folder
        defer { tracks[id] = track }
        if let last = track.segments.last {
            if last.end == nil && last.activity == activity { return }
            if last.activity == .ended && activity == .ended { return }
            if last.end == nil {
                track.segments[track.segments.count - 1].end = max(at, last.start)
            }
        }
        track.segments.append(
            JournalSegment(activity: activity, start: at, end: activity == .ended ? at : nil))
    }

    // MARK: Result

    private mutating func finish() -> JournalTimeline {
        if let start = awakeOpen {
            awakeRaw.append(JournalSpan(start, now))
        }
        if let start = sleepOpen {
            sleeps.append(JournalSpan(start, now))
        }
        timeline.awakeSpans = awakeRaw
        timeline.sleepSpans = sleeps
        timeline.awakeSegments = Self.subtract(awakeRaw, minus: sleeps).filter { $0.duration > 0 }
        timeline.tracks = tracks.values.sorted { $0.id < $1.id }
        timeline.finishes = timeline.tracks.flatMap(Self.finishes(of:)).sorted { $0.finishedAt < $1.finishedAt }
        return timeline
    }

    static func subtract(_ spans: [JournalSpan], minus holes: [JournalSpan]) -> [JournalSpan] {
        let holes = holes.sorted { $0.start < $1.start }
        var result: [JournalSpan] = []
        for span in spans {
            var cursor = span.start
            for hole in holes where hole.end > cursor && hole.start < span.end {
                if hole.start > cursor {
                    result.append(JournalSpan(cursor, hole.start))
                }
                cursor = max(cursor, hole.end)
            }
            if cursor < span.end {
                result.append(JournalSpan(cursor, span.end))
            }
        }
        return result
    }

    /// A run starts when a session turns busy and ends in turnDone, ended or (after at least the
    /// blip length) idle. Waiting and stalled do not break a run.
    static func finishes(of track: JournalSessionTrack) -> [JournalRunFinish] {
        var runStart: Date?
        var previous: SessionActivity?
        var result: [JournalRunFinish] = []
        for segment in track.segments {
            defer { previous = segment.activity }
            switch segment.activity {
            case .working, .backgroundRun, .running:
                runStart = runStart ?? segment.start
            case .waitingForYou, .stalled:
                break
            case .turnDone, .ended, .idle:
                if let start = runStart, endsRun(segment.activity, after: previous, from: start, at: segment.start) {
                    result.append(
                        JournalRunFinish(
                            sessionID: track.id, agent: track.agent, startedAt: start,
                            finishedAt: segment.start))
                }
                runStart = nil
            }
            if segment.closedByRestart {
                runStart = nil
            }
        }
        return result
    }

    /// A session that is closed or goes quiet while it waits for the user or is stalled did not
    /// finish its work, and a short idle after work is a blip.
    private static func endsRun(
        _ activity: SessionActivity, after previous: SessionActivity?, from start: Date, at end: Date
    ) -> Bool {
        let abandoned = previous == .waitingForYou || previous == .stalled
        switch activity {
        case .turnDone: return true
        case .ended: return !abandoned
        case .idle: return !abandoned && end.timeIntervalSince(start) >= idleBlipSeconds
        default: return false
        }
    }
}

extension JournalTimeline {
    /// What was in progress at `moment`, as events that restore it when replayed first. Kept in the
    /// rollups when the days before `moment` are folded away, so a run that crosses the cut keeps
    /// its true start.
    func carry(at moment: Date) -> [JournalEvent] {
        var events: [JournalEvent] = []
        for span in awakeSpans where span.start < moment && span.end > moment {
            events.append(JournalEvent(at: span.start, kind: .awakeStarted(reason: "carried")))
        }
        for span in sleepSpans where span.start < moment && span.end > moment {
            events.append(JournalEvent(at: span.start, kind: .macSlept))
        }
        for track in tracks {
            guard let segment = track.segments.last(where: { $0.start < moment }),
                segment.activity != .ended, segment.end.map({ $0 > moment }) ?? true
            else { continue }
            events.append(
                JournalEvent(
                    at: segment.start,
                    kind: .sessionChanged(
                        id: track.id, agent: track.agent, folder: track.folder, activity: segment.activity)))
        }
        return events
    }
}
