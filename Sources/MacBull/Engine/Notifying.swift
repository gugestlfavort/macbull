import Foundation

/// One user notification, fully decided by the engine.
struct AppNotification: Equatable, Sendable {
    var identifier: String
    var title: String
    var body: String
    /// Groups notifications of one kind (Your Turn).
    var threadID: String?
    /// File name in the bundle's Resources/Sounds folder; nil means the default sound.
    var soundFile: String?
}

/// Posts what the engine decided. The engine owns every rule (settings, throttle, quitting).
@MainActor
protocol Notifying: AnyObject {
    /// Ask macOS for permission (alert and sound). Safe to call more than once.
    func requestAuthorization()
    func post(_ notification: AppNotification)
    /// Remove a delivered or pending notification.
    func withdraw(identifier: String)
    /// Called when the user clicks a notification.
    var onActivate: (@MainActor () -> Void)? { get set }
}

/// The words of every notification (plain, short, no emoji).
enum NotificationText {
    static let yourTurnThread = "your-turn"

    static func safetyStop(
        _ stop: SafetyStop,
        agentsWereWorking: Bool,
        batteryPercent: Int?,
        soundFile: String?
    ) -> AppNotification {
        let reason: String
        switch stop {
        case .heat:
            reason = "Your Mac got too warm"
        case .battery:
            reason = batteryPercent.map { "Battery at \($0)%" } ?? "The battery is low"
        }
        let tail = agentsWereWorking ? " Your agents were still working." : ""
        return AppNotification(
            identifier: stop == .heat ? "heat-stop" : "battery-stop",
            title: "MacBull stopped",
            body: "\(reason), so I let your Mac sleep.\(tail)",
            threadID: nil,
            soundFile: soundFile
        )
    }

    static func agentsDone(puttingMacToSleep: Bool, soundFile: String?) -> AppNotification {
        AppNotification(
            identifier: "agents-done",
            title: "MacBull",
            body: puttingMacToSleep ? "Agents are done. Putting your Mac to sleep." : "Agents are done. Your Mac can sleep again.",
            threadID: nil,
            soundFile: soundFile
        )
    }

    static func yourTurnIdentifier(sessionID: String) -> String {
        "your-turn-\(sessionID)"
    }

    static func yourTurn(_ session: AgentSession, soundFile: String?) -> AppNotification {
        AppNotification(
            identifier: yourTurnIdentifier(sessionID: session.id),
            title: "Your turn",
            body: "\(subject(session)) needs you",
            threadID: yourTurnThread,
            soundFile: soundFile
        )
    }

    static func reminder(_ session: AgentSession, soundFile: String?) -> AppNotification {
        AppNotification(
            identifier: yourTurnIdentifier(sessionID: session.id),
            title: "Still waiting",
            body: "\(subject(session)) still needs you",
            threadID: yourTurnThread,
            soundFile: soundFile
        )
    }

    static func stalled(_ session: AgentSession, minutes: Int) -> AppNotification {
        AppNotification(
            identifier: "stalled-\(session.id)",
            title: "MacBull",
            body: "\(subject(session)) looks stuck, no activity for \(minutes) min",
            threadID: nil,
            soundFile: nil
        )
    }

    static func receipt(_ receipt: Receipt) -> AppNotification {
        AppNotification(
            identifier: "receipt-\(receipt.id.uuidString)",
            title: "While you were away",
            body: ReceiptSummary.text(receipt),
            threadID: nil,
            soundFile: nil
        )
    }

    /// "Claude Code in api" or just "Claude Code" when the folder is unknown.
    private static func subject(_ session: AgentSession) -> String {
        guard let folder = session.folder, !folder.isEmpty else { return session.agent }
        return "\(session.agent) in \(folder)"
    }
}
