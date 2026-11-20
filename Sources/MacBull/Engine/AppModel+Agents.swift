import Foundation

/// Scan results: state, journal, Your Turn and Stall Watchdog.
extension AppModel {
    func handleScan(_ result: AgentScanResult) {
        // A result that arrives after agent mode was switched off is thrown away.
        guard settings.agentMode, !state.quitting else { return }
        let t = now()
        state.agents = result.agents
        state.sessions = result.sessions
        state.toolPulses += result.toolEvents
        state.hooksError = agents.hooksError
        memory.agentsWorking = result.anyWorking
        if result.anyWorking { memory.lastWorkingSeen = t }
        recordSessionChanges(result.sessions, at: t)
        updateTurnEpisodes(result.sessions, at: t)
        notifyStalls(result.sessions, at: t)
        evaluate()
    }

    private func recordSessionChanges(_ sessions: [AgentSession], at t: Date) {
        var current: [String: AgentSession] = [:]
        for session in sessions.sorted(by: { $0.id < $1.id }) {
            current[session.id] = session
            if memory.knownSessions[session.id]?.activity != session.activity {
                journal.record(
                    .sessionChanged(id: session.id, agent: session.agent, folder: session.folder, activity: session.activity),
                    at: t
                )
            }
        }
        for (id, old) in memory.knownSessions.sorted(by: { $0.key < $1.key }) where current[id] == nil && old.activity != .ended {
            journal.record(.sessionChanged(id: id, agent: old.agent, folder: old.folder, activity: .ended), at: t)
        }
        memory.knownSessions = current
    }

    /// Agent mode off: every session we knew about is gone, which the journal learns from `.ended`.
    func endKnownSessions(at t: Date) {
        for (id, old) in memory.knownSessions.sorted(by: { $0.key < $1.key }) where old.activity != .ended {
            journal.record(.sessionChanged(id: id, agent: old.agent, folder: old.folder, activity: .ended), at: t)
        }
        memory.knownSessions = [:]
    }

    // MARK: - Your Turn

    /// One episode per waiting spell: notify and maybe light the screen once, end it when the session moves on.
    private func updateTurnEpisodes(_ sessions: [AgentSession], at t: Date) {
        let waiting = sessions.filter { $0.activity == .waitingForYou }.sorted { $0.id < $1.id }
        let waitingIDs = Set(waiting.map(\.id))
        for id in memory.turnEpisodes.keys.sorted() where !waitingIDs.contains(id) {
            endTurnEpisode(id)
        }
        for session in waiting where memory.turnEpisodes[session.id] == nil {
            memory.turnEpisodes[session.id] = TurnEpisode(since: session.since)
            deliver(NotificationText.yourTurn(session, soundFile: sound(NotificationSound.waitingForYou)))
            wakeScreenIfNeeded(at: t)
        }
    }

    func endAllTurnEpisodes() {
        for id in memory.turnEpisodes.keys.sorted() { endTurnEpisode(id) }
    }

    private func endTurnEpisode(_ id: String) {
        memory.turnEpisodes[id] = nil
        notifier.withdraw(identifier: NotificationText.yourTurnIdentifier(sessionID: id))
    }

    /// Display asleep (the user is away), lid open, outside quiet hours.
    private func wakeScreenIfNeeded(at t: Date) {
        guard settings.wakeScreenWhenWaiting, system.isAway, !system.lidClosed else { return }
        let hour = calendar.component(.hour, from: t)
        guard !QuietHours.contains(hour: hour, start: settings.quietHoursStart, end: settings.quietHoursEnd) else { return }
        system.wakeScreen()
    }

    /// One reminder per episode, when the user is at the Mac and the session still waits.
    func remindWaitingSessions(at t: Date) {
        let after = Double(settings.remindAfterMinutes) * EngineTiming.secondsPerMinute
        guard after > 0, system.secondsSinceInput < EngineTiming.userAtMacWindowSeconds else { return }
        for (id, episode) in memory.turnEpisodes.sorted(by: { $0.key < $1.key }) where !episode.reminded {
            guard t.timeIntervalSince(episode.since) >= after, let session = memory.knownSessions[id] else { continue }
            memory.turnEpisodes[id]?.reminded = true
            deliver(NotificationText.reminder(session, soundFile: sound(NotificationSound.waitingForYou)))
        }
    }

    // MARK: - Stall Watchdog

    private func notifyStalls(_ sessions: [AgentSession], at t: Date) {
        let stalled = sessions.filter { $0.activity == .stalled }.sorted { $0.id < $1.id }
        memory.stalledNotified.formIntersection(stalled.map(\.id))
        guard settings.stallWatchdog else { return }
        for session in stalled where !memory.stalledNotified.contains(session.id) {
            memory.stalledNotified.insert(session.id)
            let minutes = max(1, Int(t.timeIntervalSince(session.lastSignOfLife) / EngineTiming.secondsPerMinute))
            deliver(NotificationText.stalled(session, minutes: minutes))
        }
    }
}
