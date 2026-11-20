import Foundation
@testable import MacBull

/// Records every command and answers from a handler. Never starts a real process.
final class FakeShell: ShellRunning, @unchecked Sendable {
    static let readyListing = "User tester may run the following commands on mac:\n    (root) NOPASSWD: "
        + PmsetCommand.allCases.map(\.text).joined(separator: ", ")

    private let lock = NSLock()
    private var recorded: [String] = []
    private var failing: Set<String> = []
    private var listing = FakeShell.readyListing
    private var delays: [String: TimeInterval] = [:]
    private var startedCommands: Set<String> = []
    private var running = 0
    private var mostRunningAtOnce = 0
    /// Called when a command starts (before its delay), off the main thread.
    var onStart: (@Sendable (String) -> Void)?

    /// Commands in the order they finished.

    var calls: [String] {
        lock.withLock { recorded }
    }

    func fail(_ command: String) {
        lock.withLock { _ = failing.insert(command) }
    }

    func succeed(_ command: String) {
        lock.withLock { _ = failing.remove(command) }
    }

    func setListing(_ text: String) {
        lock.withLock { listing = text }
    }

    /// Makes a command take this long, like a slow `sudo`.
    func slow(_ command: String, seconds: TimeInterval) {
        lock.withLock { delays[command] = seconds }
    }

    func hasStarted(_ command: String) -> Bool {
        lock.withLock { startedCommands.contains(command) }
    }

    /// The most commands that ever ran at the same moment.
    var mostAtOnce: Int { lock.withLock { mostRunningAtOnce } }

    func count(_ command: String) -> Int {
        calls.filter { $0 == command }.count
    }

    func run(_ executable: String, _ arguments: [String]) async -> ShellResult {
        answer(executable, arguments)
    }

    func runBlocking(_ executable: String, _ arguments: [String]) -> ShellResult {
        answer(executable, arguments)
    }

    private func answer(_ executable: String, _ arguments: [String]) -> ShellResult {
        let command = ([executable] + arguments).joined(separator: " ")
        let delay = lock.withLock {
            startedCommands.insert(command)
            running += 1
            mostRunningAtOnce = max(mostRunningAtOnce, running)
            return delays[command] ?? 0
        }
        onStart?(command)
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return lock.withLock {
            running -= 1
            recorded.append(command)
            if failing.contains(command) { return ShellResult(status: 1, output: "") }
            let output = command == "/usr/bin/sudo -n -l" ? listing : ""
            return ShellResult(status: 0, output: output)
        }
    }
}

final class FakePrivileged: PrivilegedRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var outcome = PrivilegedOutcome.success
    private var commands: [String] = []
    private var prompts: [String] = []

    var receivedCommands: [String] { lock.withLock { commands } }
    var receivedPrompts: [String] { lock.withLock { prompts } }

    func answer(with outcome: PrivilegedOutcome) {
        lock.withLock { self.outcome = outcome }
    }

    func run(command: String, prompt: String) async -> PrivilegedOutcome {
        lock.withLock {
            commands.append(command)
            prompts.append(prompt)
            return outcome
        }
    }
}

@MainActor
final class FakeWatchdog: LidWatchdogRunning {
    var running = false
    var starts = 0
    var stops = 0

    func start() {
        running = true
        starts += 1
    }

    func stop() {
        running = false
        stops += 1
    }
}

@MainActor
final class FakeClock {
    var now = Date(timeIntervalSince1970: 2_000_000_000)
}

/// A controller wired to fakes and a throwaway flag folder.
@MainActor
struct LidRig {
    let controller: LidController
    let shell = FakeShell()
    let privileged = FakePrivileged()
    let watchdog = FakeWatchdog()
    let clock = FakeClock()
    let flags: LidFlags
    let state: EnvironmentState

    @MainActor
    final class EnvironmentState {
        var hasLid = true
        var account = "tester"
        var systemLowPower = false
        var daemonPlistExists = true
        var lidClosed = false
    }

    init() {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbull-lid-\(UUID().uuidString)", isDirectory: true)
        flags = LidFlags(directory: folder)
        let state = EnvironmentState()
        self.state = state
        let clock = clock
        let environment = LidEnvironment(
            hasLid: { state.hasLid },
            accountName: { state.account },
            systemLowPowerOn: { state.systemLowPower },
            now: { clock.now },
            daemonPlistExists: { state.daemonPlistExists },
            lidClosed: { state.lidClosed }
        )
        controller = LidController(
            shell: shell, privileged: privileged, flags: flags, watchdog: watchdog, environment: environment
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: flags.directory)
    }

    func makeReady() async {
        controller.refreshSetup()
        await controller.waitUntilIdle()
    }

    func apply(
        hold: Bool = true, bag: Bool = false, battery: Bool = false, lowPower: Bool = true
    ) async {
        controller.apply(holdWanted: hold, closedInBag: bag, onBattery: battery, lowPowerWanted: lowPower)
        await controller.waitUntilIdle()
    }
}

enum Cmd {
    static let holdOn = "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1"
    static let holdOff = "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0"
    static let lowOn = "/usr/bin/sudo -n /usr/bin/pmset -b lowpowermode 1"
    static let lowOff = "/usr/bin/sudo -n /usr/bin/pmset -b lowpowermode 0"
    static let list = "/usr/bin/sudo -n -l"
    static let sleepNow = "/usr/bin/pmset sleepnow"
    static let displayOff = "/usr/bin/pmset displaysleepnow"
}
