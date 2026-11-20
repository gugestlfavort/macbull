import Foundation

/// When is the user away? Pure: no clocks, no system calls.
///
/// Away starts at screen lock, display sleep, lid close, fast user switch out, or 10 minutes
/// without input while MacBull keeps the Mac awake. It ends at the first input, an unlock or a
/// switch back. "First input" is seen as the seconds-since-input counter dropping.
struct AwayRules: Equatable, Sendable {
    /// Without input for this long, while MacBull holds the Mac awake, counts as away.
    static let idleLimit: TimeInterval = 600
    /// The counter must fall by more than this to count as new input (sampling jitter).
    static let inputTolerance: TimeInterval = 0.5

    enum Change: Equatable, Sendable {
        case started
        case ended
    }

    private(set) var isAway = false
    private var lastSecondsSinceInput: TimeInterval = 0

    /// A leaving event (lock, display sleep, lid close, switch out, system sleep). Starts the
    /// away window unless one is already open.
    mutating func left(secondsSinceInput: TimeInterval) -> Change? {
        guard !isAway else { return nil }
        isAway = true
        lastSecondsSinceInput = secondsSinceInput
        return .started
    }

    /// An unlock or a switch back to this session.
    mutating func userReturned() -> Change? {
        guard isAway else { return nil }
        isAway = false
        return .ended
    }

    /// A periodic look at the input counter. Starts the idle rule, or ends an open window on new input.
    mutating func poll(secondsSinceInput: TimeInterval, keepAwakeActive: Bool) -> Change? {
        if isAway {
            let sawInput = secondsSinceInput < lastSecondsSinceInput - Self.inputTolerance
            lastSecondsSinceInput = secondsSinceInput
            guard sawInput else { return nil }
            isAway = false
            return .ended
        }
        guard keepAwakeActive, secondsSinceInput >= Self.idleLimit else { return nil }
        isAway = true
        lastSecondsSinceInput = secondsSinceInput
        return .started
    }
}
