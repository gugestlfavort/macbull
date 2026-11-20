import Foundation

/// Words for receipts in the Away tab.
enum AwayFormat {
    /// "7 h 12 min", "45 min", "under a minute".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "under a minute" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// "2 finished, 1 waiting for you, battery 84% to 61%".
    static func summary(_ receipt: Receipt) -> String {
        var parts: [String] = []
        let finished = receipt.lines.filter { if case .finished = $0.outcome { true } else { false } }.count
        let waiting = receipt.lines.filter { if case .waitingForYou = $0.outcome { true } else { false } }.count
        let stalled = receipt.lines.filter { if case .stalled = $0.outcome { true } else { false } }.count
        let working = receipt.lines.filter { if case .stillWorking = $0.outcome { true } else { false } }.count
        if finished > 0 { parts.append("\(finished) finished") }
        if waiting > 0 { parts.append("\(waiting) waiting for you") }
        if stalled > 0 { parts.append("\(stalled) stuck") }
        if working > 0 { parts.append("\(working) still working") }
        if let stop = receipt.safetyStop {
            parts.append(stop == .heat ? "stopped: too warm" : "stopped: battery low")
        }
        if let start = receipt.batteryStart, let end = receipt.batteryEnd, start != end {
            parts.append("battery \(start)% to \(end)%")
        }
        if receipt.notRunningSince != nil { parts.append("MacBull was not running for part of it") }
        return parts.isEmpty ? "Nothing to report" : parts.joined(separator: ", ")
    }

    /// "Away 7 h 12 min".
    static func title(_ receipt: Receipt) -> String {
        "Away \(duration(receipt.awayTo.timeIntervalSince(receipt.awayFrom)))"
    }
}
