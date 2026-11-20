import Foundation
import IOKit.pwr_mgt

/// Creates and releases one kind of assertion. A seam so tests do not touch the real power system.
@MainActor
protocol AssertionBackend: AnyObject {
    /// Returns the assertion id, or nil when the system refused.
    func create(kind: IOKitPowerAssertions.Kind, reason: String) -> IOPMAssertionID?
    func release(_ id: IOPMAssertionID)
}

/// The two IOKit assertions: prevent idle system sleep, prevent idle display sleep.
/// Created and released only when the wanted state changes.
@MainActor
final class IOKitPowerAssertions: PowerAssertions {
    enum Kind: Equatable, Sendable {
        case systemSleep
        case displaySleep
    }

    static let systemReason = "MacBull is keeping this Mac awake"
    static let displayReason = "MacBull is keeping the display on"

    private let backend: AssertionBackend
    private var systemID: IOPMAssertionID?
    private var displayID: IOPMAssertionID?

    init(backend: AssertionBackend = SystemAssertionBackend()) {
        self.backend = backend
    }

    func set(preventSystemSleep: Bool, preventDisplaySleep: Bool) {
        systemID = reconcile(systemID, wanted: preventSystemSleep, kind: .systemSleep, reason: Self.systemReason)
        displayID = reconcile(displayID, wanted: preventDisplaySleep, kind: .displaySleep, reason: Self.displayReason)
    }

    private func reconcile(_ held: IOPMAssertionID?, wanted: Bool, kind: Kind, reason: String) -> IOPMAssertionID? {
        switch (held, wanted) {
        case (nil, true):
            return backend.create(kind: kind, reason: reason)
        case let (id?, false):
            backend.release(id)
            return nil
        default:
            return held
        }
    }
}

/// The real IOKit calls.
@MainActor
final class SystemAssertionBackend: AssertionBackend {
    func create(kind: IOKitPowerAssertions.Kind, reason: String) -> IOPMAssertionID? {
        let type = kind == .systemSleep ? kIOPMAssertPreventUserIdleSystemSleep : kIOPMAssertPreventUserIdleDisplaySleep
        var id = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id
        )
        guard status == kIOReturnSuccess else {
            Log.power.error("Assertion \(reason, privacy: .public) failed: \(status)")
            return nil
        }
        return id
    }

    func release(_ id: IOPMAssertionID) {
        let status = IOPMAssertionRelease(id)
        if status != kIOReturnSuccess { Log.power.error("Assertion release failed: \(status)") }
    }
}
