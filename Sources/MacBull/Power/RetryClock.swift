import Foundation

/// Seconds to wait after a failed attempt. Each clock is independent, so a Low Power Mode
/// failure never delays releasing the lid hold.
enum LidRetry {
    /// A failed enable also triggers a re-check of the setup, so this one is the longest.
    static let enable: TimeInterval = 60
    static let disable: TimeInterval = 15
    static let lowPower: TimeInterval = 60
}

/// "Do not try again before this moment." Pure: the caller supplies the time.
struct RetryClock: Equatable, Sendable {
    private(set) var blockedUntil: Date?

    func canAttempt(at now: Date) -> Bool {
        guard let blockedUntil else { return true }
        return now >= blockedUntil
    }

    mutating func failed(at now: Date, retryAfter delay: TimeInterval) {
        blockedUntil = now.addingTimeInterval(delay)
    }

    mutating func reset() {
        blockedUntil = nil
    }
}
