import AppKit
import Foundation
import IOKit.pwr_mgt

/// Battery, heat, lid, displays and presence.
@MainActor
final class SystemMonitor: SystemMonitoring {
    /// How often input is polled, while a poll can change something.
    static let pollInterval: TimeInterval = 3

    var onEvent: (@MainActor (SystemEvent) -> Void)?

    private var rules = AwayRules()
    private var keepAwakeActive: @MainActor () -> Bool = { false }
    private var started = false
    private var lastLidClosed = false
    private var timer: Timer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var userActivityAssertion = IOPMAssertionID(0)
    private let clamshellWatcher = ClamshellWatcher()
    private let powerSourceWatcher = PowerSourceWatcher()
    private var powerCache = PowerReadingCache()

    // MARK: - Readings

    var hasLid: Bool { Clamshell.read() != .noLid }
    var lidClosed: Bool { Clamshell.read() == .closed }
    var hasExternalDisplay: Bool { DisplayProbe.hasExternalDisplay() }
    var batteryPercent: Int? { powerReading().percent }
    var onBattery: Bool { powerReading().onBattery }
    var lowPowerModeOn: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
    var thermal: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }
    var isAway: Bool { rules.isAway }

    private func powerReading() -> PowerReading {
        powerCache.reading(at: Date()) { PowerSourceReader.read() }
    }

    var secondsSinceInput: TimeInterval {
        let anyInput = CGEventType(rawValue: UInt32.max) ?? .null
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    // MARK: - Start

    func start(keepAwakeActive: @escaping @MainActor () -> Bool) {
        self.keepAwakeActive = keepAwakeActive
        guard !started else { return }
        started = true
        lastLidClosed = lidClosed
        observeSystem()
        observeSession()
        observeLock()
        clamshellWatcher.start { [weak self] in self?.lidMayHaveChanged() }
        powerSourceWatcher.start { [weak self] in
            self?.powerCache.invalidate()
            self?.emit(.powerSourceChanged)
        }
        startTimer()
    }

    /// Light a sleeping display once. Declares user activity, which wakes the display.
    func wakeScreen() {
        let status = IOPMAssertionDeclareUserActivity(
            "MacBull: an agent needs you" as CFString, kIOPMUserActiveLocal, &userActivityAssertion
        )
        if status != kIOReturnSuccess { Log.power.error("Wake screen failed: \(status)") }
    }

    // MARK: - Observers

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.handleWillSleep() }
        observe(workspace, NSWorkspace.didWakeNotification) {
            $0.powerCache.invalidate()
            $0.emit(.didWake)
        }
        observe(workspace, NSWorkspace.willPowerOffNotification) { $0.emit(.powerOff) }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.leave() }
        observe(.default, ProcessInfo.thermalStateDidChangeNotification) { $0.emit(.thermalChanged) }
        observe(.default, .NSProcessInfoPowerStateDidChange) { $0.emit(.powerSourceChanged) }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.emit(.displaysChanged) }
    }

    private func observeSession() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.leave() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.returned() }
    }

    /// There is no public lock notification; these distributed ones are what the system posts.
    private func observeLock() {
        let center = DistributedNotificationCenter.default()
        observe(center, Notification.Name("com.apple.screenIsLocked")) { $0.leave() }
        observe(center, Notification.Name("com.apple.screenIsUnlocked")) { $0.returned() }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        handler: @escaping @MainActor (SystemMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { handler(self) }
            }
        }
        observers.append((center, token))
    }

    // MARK: - Events and away

    private func emit(_ event: SystemEvent) {
        onEvent?(event)
    }

    private func handleWillSleep() {
        emit(.willSleep)
        leave()
    }

    private func lidMayHaveChanged() {
        let closed = lidClosed
        guard closed != lastLidClosed else { return }
        lastLidClosed = closed
        emit(.lidChanged)
        if closed { leave() }
    }

    private func leave() {
        publish(rules.left(secondsSinceInput: secondsSinceInput))
    }

    private func returned() {
        publish(rules.userReturned())
    }

    private func publish(_ change: AwayRules.Change?) {
        switch change {
        case .started: emit(.awayStarted)
        case .ended: emit(.awayEnded)
        case nil: break
        }
    }

    // MARK: - Input polling

    private func startTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 1
        self.timer = timer
    }

    /// Input only matters while away (to end it) or while MacBull holds the Mac awake (the idle rule).
    private func tick() {
        let active = keepAwakeActive()
        guard rules.isAway || active else { return }
        publish(rules.poll(secondsSinceInput: secondsSinceInput, keepAwakeActive: active))
    }
}
