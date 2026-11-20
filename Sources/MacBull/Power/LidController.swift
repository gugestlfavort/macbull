import Foundation

/// What the engine wants right now. `apply` stores the latest and reconciles towards it.
struct LidRequest: Equatable, Sendable {
    var holdWanted: Bool
    var closedInBag: Bool
    var onBattery: Bool
    var lowPowerWanted: Bool
}

/// Everything the controller reads from the machine, so tests can fake it.
struct LidEnvironment {
    var hasLid: @MainActor () -> Bool
    var accountName: @MainActor () -> String
    var systemLowPowerOn: @MainActor () -> Bool
    var now: @MainActor () -> Date
    var daemonPlistExists: @MainActor () -> Bool
    var lidClosed: @MainActor () -> Bool

    static let live = LidEnvironment(
        hasLid: { Clamshell.read() != .noLid },
        accountName: { NSUserName() },
        systemLowPowerOn: { ProcessInfo.processInfo.isLowPowerModeEnabled },
        now: { Date() },
        daemonPlistExists: { FileManager.default.fileExists(atPath: BootDaemon.plistPath) },
        lidClosed: { Clamshell.read() == .closed }
    )
}

/// Lid-closed mode: sudoers rule, boot-reset daemon, flags, watchdog and pmset.
@MainActor
final class LidController: LidControlling {
    private(set) var setup: LidSetup
    private(set) var isHeld = false
    private(set) var lastError: String?

    /// Every pmset and sudo call goes through one serial queue (see `SerialShellRunner`).
    private let shell: ShellRunning
    private let privileged: PrivilegedRunning
    private let flags: LidFlags
    private let watchdog: LidWatchdogRunning
    private let environment: LidEnvironment

    private var request: LidRequest?
    private var quitting = false
    private var lowPowerForced = false
    private var inBag = false
    private var sleepClock = RetryClock()
    private var lowPowerClock = RetryClock()
    private var sleepBusy = false
    private var lowPowerBusy = false
    private var privilegedBusy = false
    private var setupGeneration = 0
    private var pendingSetupChecks = 0
    private var pendingCommands = 0
    /// Sleep Now was asked while the hold was on or being switched: sleep once the release has gone through.
    private var sleepAfterRelease = false

    init(
        shell: ShellRunning = ProcessShellRunner(),
        privileged: PrivilegedRunning = AppleScriptPrivilegedRunner(),
        flags: LidFlags = .standard,
        watchdog: LidWatchdogRunning? = nil,
        environment: LidEnvironment = .live
    ) {
        self.shell = SerialShellRunner(shell)
        self.privileged = privileged
        self.flags = flags
        self.watchdog = watchdog ?? LidWatchdog(flags: flags)
        self.environment = environment
        setup = environment.hasLid() ? .notSetUp : .noLid
    }

    // MARK: - LidControlling

    func refreshSetup() {
        pendingSetupChecks += 1
        Task {
            await updateSetup()
            pendingSetupChecks -= 1
        }
    }

    /// Undo what a crash left behind. The flags say what MacBull changed.
    func restoreAtLaunch() {
        flags.clear(.heldInBag)
        isHeld = flags.exists(.sleepDisabled)
        lowPowerForced = flags.exists(.lowPowerForced)
        if isHeld {
            sleepBusy = true
            Task { await releaseHold() }
        }
        if lowPowerForced {
            lowPowerBusy = true
            Task { await releaseLowPower() }
        }
    }

    func apply(holdWanted: Bool, closedInBag: Bool, onBattery: Bool, lowPowerWanted: Bool) {
        request = LidRequest(
            holdWanted: holdWanted, closedInBag: closedInBag, onBattery: onBattery, lowPowerWanted: lowPowerWanted
        )
        // Turning the hold back on cancels a sleep that was waiting for the release.
        if holdWanted { sleepAfterRelease = false }
        reconcile()
    }

    /// `pmset sleepnow` does nothing while `disablesleep 1` is set, and the release is asynchronous: while the
    /// hold is on or being switched, the sleep waits for the release (`releaseHold` runs it). Otherwise it runs now.
    func sleepNow() {
        guard isHeld || sleepBusy else {
            runSleepNow()
            return
        }
        sleepAfterRelease = true
        reconcile()
    }

    private func runSleepNow() {
        run(PmsetCommand.pmsetPath, ["sleepnow"], label: "sleep now")
    }

    func install() async -> LidSetupResult {
        guard environment.hasLid() else { return .failed(LidCopy.noLid) }
        let account = environment.accountName()
        guard AccountName.isValid(account) else { return fail(LidCopy.badAccountName) }
        guard !privilegedBusy else { return .failed(LidCopy.busy) }
        privilegedBusy = true
        defer { privilegedBusy = false }

        let command = LidScripts.installCommand(
            rule: SudoRule.text(forAccount: account),
            plist: BootDaemon.plist(flagPaths: flags.orderedPaths)
        )
        let outcome = await privileged.run(command: command, prompt: LidCopy.installPrompt)
        return await finishInstall(outcome)
    }

    func uninstall() async -> LidSetupResult {
        guard !privilegedBusy else { return .failed(LidCopy.busy) }
        privilegedBusy = true
        defer { privilegedBusy = false }

        let command = LidScripts.uninstallCommand(
            sleepFlag: flags.path(.sleepDisabled), lowPowerFlag: flags.path(.lowPowerForced)
        )
        let outcome = await privileged.run(command: command, prompt: LidCopy.removePrompt)
        return await finishUninstall(outcome)
    }

    /// Undo everything at quit. Blocking on purpose: the app is about to exit.
    func cleanUpForQuit(systemPoweringOff: Bool) {
        quitting = true
        let wasBagged = isHeld && request?.closedInBag == true
        let holdReleased = releaseHoldBlocking()
        releaseLowPowerBlocking()
        if holdReleased {
            flags.clear(.heldInBag)
            inBag = false
        }
        stopWatchdogIfIdle()
        if wasBagged, holdReleased, !systemPoweringOff {
            let result = shell.runBlocking(PmsetCommand.pmsetPath, ["sleepnow"])
            Log.power.info("Sleep after quit in a bag, exit \(result.status)")
        }
    }

    /// Waits for every started command to finish. For tests.
    func waitUntilIdle() async {
        var spins = 0
        while isBusy, spins < 10_000 {
            await Task.yield()
            spins += 1
        }
    }

    private var isBusy: Bool {
        sleepBusy || lowPowerBusy || pendingSetupChecks > 0 || pendingCommands > 0
    }

    // MARK: - Reconcile

    private func reconcile() {
        guard !quitting, let request else { return }
        reconcileSleep(request)
        updateBagState(closedInBag: request.closedInBag)
        reconcileLowPower(request)
    }

    private func reconcileSleep(_ request: LidRequest) {
        guard !sleepBusy, sleepClock.canAttempt(at: environment.now()) else { return }
        let hold = request.holdWanted && setup == .ready
        if hold, !isHeld {
            sleepBusy = true
            Task { await holdSleepOff() }
        } else if !hold, isHeld {
            sleepBusy = true
            Task { await releaseHold() }
        }
    }

    private func reconcileLowPower(_ request: LidRequest) {
        guard !lowPowerBusy, lowPowerClock.canAttempt(at: environment.now()) else { return }
        let wanted = isHeld && request.closedInBag && request.lowPowerWanted && request.onBattery
        if wanted, !lowPowerForced, !environment.systemLowPowerOn() {
            lowPowerBusy = true
            Task { await forceLowPower() }
        } else if !wanted, lowPowerForced {
            lowPowerBusy = true
            Task { await releaseLowPower() }
        }
    }

    /// Transition only: when the Mac becomes held and shut in a bag, record it and turn the display off once.
    private func updateBagState(closedInBag: Bool) {
        let wanted = isHeld && closedInBag
        if wanted, !inBag {
            inBag = true
            if !flags.set(.heldInBag) { Log.lid.error("Cannot write the in-bag note") }
            run("/usr/bin/pmset", ["displaysleepnow"], label: "display off")
        } else if !wanted, inBag {
            inBag = false
            flags.clear(.heldInBag)
        }
    }

    // MARK: - pmset operations

    private func holdSleepOff() async {
        // A quit that came after this task was queued has already undone everything: do not switch sleep off again.
        guard !quitting else {
            finishSleepOperation()
            return
        }
        if await tryHoldOn() {
            // A quit during the call ran its `disablesleep 0` after our enable (one queue), so nothing is held now.
            isHeld = !quitting
            lastError = nil
            sleepClock.reset()
        } else {
            sleepClock.failed(at: environment.now(), retryAfter: LidRetry.enable)
            await updateSetup()
        }
        finishSleepOperation()
    }

    /// Flag and watchdog first, so a kill right after the call still gets undone.
    private func tryHoldOn() async -> Bool {
        guard flags.set(.sleepDisabled) else {
            lastError = LidCopy.flagFailed
            return false
        }
        watchdog.start()
        if await runSudo(.holdOn) { return true }
        flags.clear(.sleepDisabled)
        stopWatchdogIfIdle()
        lastError = LidCopy.enableFailed
        return false
    }

    private func releaseHold() async {
        guard await runSudo(.holdOff) else {
            sleepClock.failed(at: environment.now(), retryAfter: LidRetry.disable)
            lastError = LidCopy.disableFailed
            finishSleepOperation()
            return
        }
        isHeld = false
        flags.clear(.sleepDisabled)
        sleepClock.reset()
        lastError = nil
        let closedInBag = request?.closedInBag == true
        updateBagState(closedInBag: closedInBag)
        stopWatchdogIfIdle()
        let sleepWasAsked = sleepAfterRelease
        sleepAfterRelease = false
        if !quitting, sleepWasAsked || shouldSleepAfterRelease(closedInBag: closedInBag) { runSleepNow() }
        finishSleepOperation()
    }

    /// Releasing `disablesleep` with the lid shut does not sleep the Mac by itself. In a bag that is always wanted; on
    /// battery a shut lid at a desk (an external display) also gets it, so a dock that was left does not drain the battery.
    private func shouldSleepAfterRelease(closedInBag: Bool) -> Bool {
        closedInBag || (request?.onBattery == true && environment.lidClosed())
    }

    private func finishSleepOperation() {
        sleepBusy = false
        reconcile()
    }

    private func forceLowPower() async {
        guard !quitting else {
            finishLowPowerOperation()
            return
        }
        if await tryLowPowerOn() {
            lowPowerForced = true
            lowPowerClock.reset()
        } else {
            lowPowerClock.failed(at: environment.now(), retryAfter: LidRetry.lowPower)
        }
        finishLowPowerOperation()
    }

    private func tryLowPowerOn() async -> Bool {
        guard flags.set(.lowPowerForced) else { return false }
        watchdog.start()
        if await runSudo(.lowPowerOn) { return true }
        flags.clear(.lowPowerForced)
        stopWatchdogIfIdle()
        return false
    }

    private func releaseLowPower() async {
        if await runSudo(.lowPowerOff) {
            lowPowerForced = false
            flags.clear(.lowPowerForced)
            stopWatchdogIfIdle()
            lowPowerClock.reset()
        } else {
            lowPowerClock.failed(at: environment.now(), retryAfter: LidRetry.lowPower)
        }
        finishLowPowerOperation()
    }

    private func finishLowPowerOperation() {
        lowPowerBusy = false
        reconcile()
    }

    private func runSudo(_ command: PmsetCommand) async -> Bool {
        let result = await shell.run(PmsetCommand.sudoPath, command.sudoArguments)
        Log.lid.info("pmset \(command.text, privacy: .public) exit \(result.status)")
        return result.succeeded
    }

    private func run(_ executable: String, _ arguments: [String], label: String) {
        pendingCommands += 1
        Task {
            let result = await shell.run(executable, arguments)
            Log.power.info("\(label, privacy: .public) exit \(result.status)")
            pendingCommands -= 1
        }
    }

    private func stopWatchdogIfIdle() {
        if !flags.exists(.sleepDisabled), !flags.exists(.lowPowerForced) { watchdog.stop() }
    }

    // MARK: - Quit path

    private func releaseHoldBlocking() -> Bool {
        guard isHeld || flags.exists(.sleepDisabled) else { return true }
        let result = shell.runBlocking(PmsetCommand.sudoPath, PmsetCommand.holdOff.sudoArguments)
        Log.lid.info("Quit: disablesleep 0 exit \(result.status)")
        guard result.succeeded else { return false }
        isHeld = false
        flags.clear(.sleepDisabled)
        return true
    }

    private func releaseLowPowerBlocking() {
        guard lowPowerForced || flags.exists(.lowPowerForced) else { return }
        let result = shell.runBlocking(PmsetCommand.sudoPath, PmsetCommand.lowPowerOff.sudoArguments)
        Log.lid.info("Quit: lowpowermode 0 exit \(result.status)")
        guard result.succeeded else { return }
        lowPowerForced = false
        flags.clear(.lowPowerForced)
    }

    // MARK: - Setup

    private func updateSetup() async {
        setupGeneration += 1
        let generation = setupGeneration
        let detected = await detectSetup()
        if generation == setupGeneration { setup = detected }
    }

    private func detectSetup() async -> LidSetup {
        guard environment.hasLid() else { return .noLid }
        guard environment.daemonPlistExists() else { return .notSetUp }
        let result = await shell.run(PmsetCommand.sudoPath, ["-n", "-l"])
        guard result.succeeded else { return .notSetUp }
        return SudoListing.allowsWithoutPassword(result.output) ? .ready : .notSetUp
    }

    private func finishInstall(_ outcome: PrivilegedOutcome) async -> LidSetupResult {
        switch outcome {
        case .cancelled:
            lastError = nil
            await updateSetup()
            return .cancelled
        case .failed:
            await updateSetup()
            return fail(LidCopy.macOSRefused)
        case .success:
            resetClocks()
            await updateSetup()
            guard setup == .ready else { return fail(LidCopy.sudoersNotIncluded) }
            lastError = nil
            return .success
        }
    }

    private func finishUninstall(_ outcome: PrivilegedOutcome) async -> LidSetupResult {
        switch outcome {
        case .cancelled:
            lastError = nil
            await updateSetup()
            return .cancelled
        case .failed:
            await updateSetup()
            return fail(LidCopy.removeFailed)
        case .success:
            flags.clearAll()
            isHeld = false
            lowPowerForced = false
            inBag = false
            watchdog.stop()
            resetClocks()
            lastError = nil
            await updateSetup()
            return .success
        }
    }

    private func resetClocks() {
        sleepClock.reset()
        lowPowerClock.reset()
    }

    private func fail(_ message: String) -> LidSetupResult {
        lastError = message
        return .failed(message)
    }
}
