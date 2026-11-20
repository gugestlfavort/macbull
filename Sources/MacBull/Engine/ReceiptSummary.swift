import Foundation

/// The one-line text of the "welcome back" notification.
enum ReceiptSummary {
    static func text(_ receipt: Receipt) -> String {
        let away = receipt.awayTo.timeIntervalSince(receipt.awayFrom)
        let minutes = max(1, Int((away / EngineTiming.secondsPerMinute).rounded()))
        let head = "Away \(StatusLine.minutesText(minutes))"
        let parts = ReceiptFormat.countParts(receipt.lines) + eventParts(receipt)
        return parts.isEmpty ? head : "\(head): \(parts.joined(separator: ", "))"
    }

    private static func eventParts(_ receipt: Receipt) -> [String] {
        var parts: [String] = []
        if let stop = receipt.safetyStop {
            parts.append(stop == .heat ? "stopped because the Mac got warm" : "stopped because the battery got low")
        }
        if receipt.notRunningSince != nil { parts.append("MacBull was not running for part of it") }
        if let start = receipt.batteryStart, let end = receipt.batteryEnd {
            parts.append(start == end ? "battery \(start)%" : "battery \(start)% to \(end)%")
        }
        return parts
    }
}
