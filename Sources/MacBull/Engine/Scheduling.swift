import Foundation

@MainActor
protocol ScheduledTask: AnyObject {
    func cancel()
}

/// Timers behind a seam, so tests fire them by hand and never wait.
@MainActor
protocol Scheduling: AnyObject {
    func every(_ interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask
    func after(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask
}

@MainActor
final class TimerTask: ScheduledTask {
    private let timer: Timer

    init(timer: Timer) {
        self.timer = timer
    }

    func cancel() {
        timer.invalidate()
    }
}

/// Real timers on the main run loop, in common modes so they keep firing while menus are open.
@MainActor
final class TimerScheduler: Scheduling {
    func every(_ interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        schedule(interval: interval, repeats: true, action)
    }

    func after(_ delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        schedule(interval: max(delay, 0), repeats: false, action)
    }

    private func schedule(interval: TimeInterval, repeats: Bool, _ action: @escaping @MainActor () -> Void) -> any ScheduledTask {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = min(1, interval / 10)
        RunLoop.main.add(timer, forMode: .common)
        return TimerTask(timer: timer)
    }
}
