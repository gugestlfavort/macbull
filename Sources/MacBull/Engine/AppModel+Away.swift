import Foundation

/// System events, away windows and the Receipt.
extension AppModel {
    func handleSystemEvent(_ event: SystemEvent) {
        let t = now()
        switch event {
        case .willSleep:
            journal.record(.macSlept, at: t)
        case .didWake:
            memory.powerOffAnnouncedAt = nil
            journal.record(.macWoke, at: t)
            evaluate()
        case .thermalChanged, .powerSourceChanged, .displaysChanged, .lidChanged:
            evaluate()
        case .awayStarted:
            beginAway(at: t)
        case .awayEnded:
            // The user is back: the logout or shutdown that was announced did not happen.
            memory.powerOffAnnouncedAt = nil
            endAway(at: t)
        case .powerOff:
            memory.powerOffAnnouncedAt = t
        }
    }

    func beginAway(at t: Date) {
        guard memory.awayStartedAt == nil else { return }
        state.isAway = true
        memory.awayStartedAt = t
        journal.record(.awayStarted, at: t)
        retuneTick()
    }

    /// On return: a receipt when the window was long enough and something happened.
    func endAway(at t: Date) {
        guard let started = memory.awayStartedAt else { return }
        memory.awayStartedAt = nil
        state.isAway = false
        retuneTick()
        journal.record(.awayEnded, at: t)
        let minimum = Double(settings.receiptMinAwayMinutes) * EngineTiming.secondsPerMinute
        guard t.timeIntervalSince(started) >= minimum else { return }

        var receipt = journal.receipt(from: started, to: t)
        if receipt.notRunningSince == nil { receipt.notRunningSince = memory.crashedSince }
        memory.crashedSince = nil
        if !settings.showProjectNames {
            receipt.lines = receipt.lines.map { line in
                var hidden = line
                hidden.folder = nil
                return hidden
            }
        }
        guard receipt.isWorthShowing else { return }
        journal.save(receipt)
        state.latestReceipt = receipt
        state.receipts = Array(([receipt] + state.receipts).prefix(EngineTiming.maxSavedReceipts))
        deliver(NotificationText.receipt(receipt))
    }
}
