import Foundation

/// The evaluation loop: every rule that turns facts into state and commands.
extension AppModel {
    /// Runs on every tick, settings change, scan result, system event and wake.
    func evaluate() {
        guard !state.quitting else { return }
        if memory.evaluating {
            memory.reevaluate = true
            return
        }
        memory.evaluating = true
        defer { memory.evaluating = false }
        var passes = 0
        repeat {
            memory.reevaluate = false
            runEvaluation()
            passes += 1
        } while memory.reevaluate && passes < EngineTiming.maxEvaluationPasses
    }

    private func runEvaluation() {
        let t = now()
        readSystem(at: t)
        endExpiredManual(at: t)
        syncAgentMode()
        syncHooksError()
        let input = safetyInput()
        let stop = SafetyRules.stop(for: input)
        if state.isAwake, let stop { applyCutoff(stop, at: t) }
        updateAgentHold(at: t, safetyStop: stop)
        clearStaleCutoffNote(input)
        recordAwakeTransition(at: t)
        applyPower()
        armManualTimer(at: t)
        remindWaitingSessions(at: t)
        pruneIfDue(at: t)
        publishStatusLine(at: t)
        retuneTick()
    }

    /// Ticks every 5 s while something needs watching and every 30 s when the Mac is not awake, not away and
    /// no session waits for the user, so an idle MacBull wakes the CPU a sixth as often.
    func retuneTick() {
        guard memory.started, tickTask != nil, !state.quitting else { return }
        let busy = state.isAwake || state.isAway || state.waitingCount > 0
        let wanted = busy ? EngineTiming.tickSeconds : EngineTiming.idleTickSeconds
        guard wanted != memory.tickSeconds else { return }
        memory.tickSeconds = wanted
        tickTask?.cancel()
        tickTask = scheduler.every(wanted) { [weak self] in self?.evaluate() }
    }

    // MARK: - Facts

    func set<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppState, Value>, _ value: Value) {
        if state[keyPath: keyPath] != value { state[keyPath: keyPath] = value }
    }

    private func readSystem(at t: Date) {
        // The power source is read once per evaluation and the two numbers are passed on.
        let onBattery = system.onBattery
        let percent = system.batteryPercent
        set(\.onBattery, onBattery)
        set(\.batteryPercent, percent)
        set(\.thermal, system.thermal)
        set(\.closedInBag, system.hasLid && system.lidClosed && !system.hasExternalDisplay)
        syncLidState()
        recordBatteryIfChanged(percent: percent, onBattery: onBattery, at: t)
        recordThermalIfChanged(at: t)
    }

    /// The lid controller updates `setup` and `lastError` on its own schedule, so they are read again
    /// after install and remove and on every evaluation (the 5 s tick among them).
    func syncLidState() {
        set(\.lidSetup, lid.setup)
        set(\.lidError, lid.lastError)
    }

    /// Read after the watcher was configured: configuring is what sets or clears the error.
    func syncHooksError() {
        set(\.hooksError, agents.hooksError)
    }

    private func recordBatteryIfChanged(percent: Int?, onBattery: Bool, at t: Date) {
        guard let percent else { return }
        let onAC = !onBattery
        if let last = memory.lastBattery, last.percent == percent, last.onAC == onAC { return }
        memory.lastBattery = (percent, onAC)
        journal.record(.battery(percent: percent, onAC: onAC), at: t)
    }

    private func recordThermalIfChanged(at t: Date) {
        let level = system.thermal.level
        guard memory.lastThermalLevel != level else { return }
        memory.lastThermalLevel = level
        journal.record(.thermal(level: level), at: t)
    }

    func safetyInput() -> SafetyInput {
        SafetyInput(
            batteryGuard: settings.batteryGuard,
            batteryThresholdPercent: settings.batteryPercent,
            heatGuard: settings.heatGuard,
            onBattery: state.onBattery,
            batteryPercent: state.batteryPercent,
            thermal: state.thermal,
            lidHoldPossible: state.lidSetup == .ready && settings.lidHold,
            closedInBag: state.closedInBag
        )
    }

    // MARK: - Manual session

    /// Timers do not count sleep, so the end time is checked on every tick and wake too.
    private func endExpiredManual(at t: Date) {
        guard let manual = state.manual, let end = manual.endsAt, t >= end else { return }
        state.manual = nil
        memory.pendingEndReason = "timer"
        Log.engine.info("Time is up")
    }

    func armManualTimer(at t: Date) {
        let end = state.manual?.endsAt
        guard end != memory.armedEnd else { return }
        endTask?.cancel()
        endTask = nil
        memory.armedEnd = end
        guard let end else { return }
        endTask = scheduler.after(max(end.timeIntervalSince(t), 0)) { [weak self] in self?.evaluate() }
    }

    // MARK: - Agent mode, hold, pause

    /// Agent mode off: stop scanning, clear the list, the hold and the pause.
    private func syncAgentMode() {
        if settings.agentMode {
            agents.configure(
                enabled: true,
                customAgents: settings.customAgents,
                claudeHooks: settings.claudeHooks,
                stallWatchdog: settings.stallWatchdog
            )
            return
        }
        agents.configure(enabled: false, customAgents: [], claudeHooks: false, stallWatchdog: false)
        if state.agentHold { memory.pendingEndReason = "agentsDone" }
        endKnownSessions(at: now())
        set(\.agents, [])
        set(\.sessions, [])
        state.agentHold = false
        state.agentHoldSince = nil
        state.paused = false
        memory.agentsWorking = false
        memory.lastWorkingSeen = nil
        endAllTurnEpisodes()
    }

    private func updateAgentHold(at t: Date, safetyStop: SafetyStop?) {
        guard settings.agentMode else { return }
        let grace = Double(max(settings.graceMinutes, 1)) * EngineTiming.secondsPerMinute
        let quietLongEnough = memory.lastWorkingSeen.map { t.timeIntervalSince($0) >= grace } ?? true
        if state.paused, !memory.agentsWorking, quietLongEnough {
            state.paused = false
            Log.engine.info("Pause cleared, agents are quiet")
        }
        if state.agentHold {
            if !memory.agentsWorking, quietLongEnough { endHoldNormally(at: t) }
        } else if memory.agentsWorking, !state.paused, safetyStop == nil {
            state.agentHold = true
            state.agentHoldSince = t
            state.cutoff = nil
            Log.engine.info("Agent hold started")
        }
    }

    private func endHoldNormally(at t: Date) {
        let heldFor = state.agentHoldSince.map { t.timeIntervalSince($0) } ?? 0
        state.agentHold = false
        state.agentHoldSince = nil
        memory.pendingEndReason = "agentsDone"
        Log.engine.info("Agent hold ended after the grace period")
        if state.manual == nil { notifyAgentsDone(heldFor: heldFor) }
    }

    // MARK: - Safety cutoff

    private func applyCutoff(_ stop: SafetyStop, at t: Date) {
        let hadHold = state.agentHold
        state.cutoff = stop
        state.manual = nil
        if hadHold {
            state.agentHold = false
            state.agentHoldSince = nil
            state.paused = true
        }
        memory.pendingEndReason = "cutoff"
        journal.record(.safetyStop(stop), at: t)
        Log.engine.notice("Safety cutoff: \(stop.rawValue, privacy: .public)")
        notifySafetyStop(stop, agentsWereWorking: hadHold)
    }

    /// The note shows only while not awake, and goes when its reason is gone.
    private func clearStaleCutoffNote(_ input: SafetyInput) {
        guard let stop = state.cutoff, !state.isAwake else { return }
        if !SafetyRules.noteStillApplies(stop, input) { state.cutoff = nil }
    }

    // MARK: - Journal and housekeeping

    private func recordAwakeTransition(at t: Date) {
        let awake = state.isAwake
        guard awake != memory.journalAwake else { return }
        memory.journalAwake = awake
        if awake {
            journal.record(.awakeStarted(reason: state.manual != nil ? "manual" : "agents"), at: t)
        } else {
            journal.record(.awakeEnded(reason: memory.pendingEndReason ?? "agentsDone"), at: t)
        }
        memory.pendingEndReason = nil
    }

    private func pruneIfDue(at t: Date) {
        if let last = memory.lastPrune, t.timeIntervalSince(last) < EngineTiming.pruneIntervalSeconds { return }
        memory.lastPrune = t
        journal.prune(keepDays: settings.historyDays, now: t)
    }

    private func publishStatusLine(at t: Date) {
        let line = StatusLine.text(state: state, now: t)
        guard line != memory.lastStatusLine else { return }
        memory.lastStatusLine = line
        onStatusLineChange?(line)
    }

    // MARK: - Assertions and lid

    private func applyPower() {
        let plan = PowerPlan.make(
            PowerPlan.Facts(
                isAwake: state.isAwake,
                manualActive: state.manual != nil,
                keepDisplayOn: settings.keepDisplayOn,
                lidReady: state.lidSetup == .ready,
                lidSetting: settings.lidHold,
                lowPowerSetting: settings.lowPowerInBag,
                closedInBag: state.closedInBag,
                onBattery: state.onBattery,
                quitting: state.quitting
            )
        )
        // Every evaluation, not only on a change: setting what is already held does nothing, and a
        // create that the system refused is tried again on the next tick.
        power.set(preventSystemSleep: plan.preventSystemSleep, preventDisplaySleep: plan.preventDisplaySleep)
        lid.apply(
            holdWanted: plan.lidHoldWanted,
            closedInBag: state.closedInBag,
            onBattery: state.onBattery,
            lowPowerWanted: plan.lowPowerWanted
        )
        set(\.lidHeld, lid.isHeld)
        syncLidState()
    }
}
