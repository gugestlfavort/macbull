import Foundation

/// The one line used as tooltip, accessibility description and "MacBull, <line>".
enum StatusLine {
    @MainActor
    static func text(state: AppState, now: Date) -> String {
        text(
            manual: state.manual,
            agentHold: state.agentHold,
            workingAgents: state.agents.filter(\.isWorking).map(\.name),
            cutoff: state.cutoff,
            paused: state.paused,
            now: now
        )
    }

    static func text(
        manual: ManualSession?,
        agentHold: Bool,
        workingAgents: [String],
        cutoff: SafetyStop?,
        paused: Bool,
        now: Date
    ) -> String {
        if let manual {
            guard let end = manual.endsAt else { return "Awake until you turn it off" }
            return "Awake for \(minutesText(remainingMinutes(until: end, now: now))) more"
        }
        if agentHold {
            if workingAgents.isEmpty { return "Awake while agents finish up" }
            let verb = workingAgents.count == 1 ? "works" : "work"
            return "Awake while \(naturalList(workingAgents)) \(verb)"
        }
        if let cutoff {
            switch cutoff {
            case .heat: return "Turned off because the Mac got too warm"
            case .battery: return "Turned off because the battery is low"
            }
        }
        if paused { return "Off until your agents finish" }
        return "Off, the Mac sleeps as usual"
    }

    /// Rounded up to whole minutes, at least 1.
    static func remainingMinutes(until end: Date, now: Date) -> Int {
        let seconds = end.timeIntervalSince(now)
        return max(1, Int((seconds / EngineTiming.secondsPerMinute).rounded(.up)))
    }

    /// Below 60: "N min". Otherwise "H h" or "H h M min".
    static func minutesText(_ minutes: Int) -> String {
        let perHour = 60
        guard minutes >= perHour else { return "\(minutes) min" }
        let hours = minutes / perHour
        let rest = minutes % perHour
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    static func naturalList(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names.dropLast().joined(separator: ", ")) and \(names[names.count - 1])"
        }
    }
}
