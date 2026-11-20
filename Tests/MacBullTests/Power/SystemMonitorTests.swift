import Foundation
import Testing
@testable import MacBull

/// Smoke tests against the real machine: nothing here depends on what the readings are.
@MainActor
struct SystemMonitorTests {
    @Test func readingsDoNotCrashAndAreSane() {
        let monitor = SystemMonitor()
        if let percent = monitor.batteryPercent { #expect((0...100).contains(percent)) }
        #expect(monitor.secondsSinceInput >= 0)
        #expect(!monitor.isAway)
        if monitor.lidClosed { #expect(monitor.hasLid) }
        _ = monitor.hasExternalDisplay
        _ = monitor.onBattery
        _ = monitor.lowPowerModeOn
        _ = monitor.thermal
    }

    @Test func startIsIdempotent() {
        let monitor = SystemMonitor()
        monitor.start { false }
        monitor.start { false }
        #expect(!monitor.isAway)
    }

    @Test func clamshellReadMatchesMonitor() {
        let monitor = SystemMonitor()
        #expect(monitor.hasLid == (Clamshell.read() != .noLid))
    }
}
