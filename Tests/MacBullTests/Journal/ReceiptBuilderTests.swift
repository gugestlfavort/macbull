import Foundation
import Testing

@testable import MacBull

struct ReceiptBuilderTests {
    private typealias Fix = JournalFixtures

    private func build(_ events: [JournalEvent], from: Date, to: Date) -> Receipt {
        ReceiptBuilder.build(events: events, from: from, to: to, id: UUID())
    }

    @Test func overnightRunFinished() {
        let events = [
            Fix.event(Fix.date(11, 18, 18), .appLaunched),
            Fix.session(Fix.date(11, 18, 22, 10), "a", .working),
            Fix.event(Fix.date(11, 18, 22, 15), .battery(percent: 84, onAC: false)),
            Fix.event(Fix.date(11, 18, 22, 20), .awayStarted),
            Fix.event(Fix.date(11, 19, 1, 0), .battery(percent: 70, onAC: false)),
            Fix.session(Fix.date(11, 19, 3, 12), "a", .turnDone),
            Fix.event(Fix.date(11, 19, 5, 0), .battery(percent: 61, onAC: false)),
            Fix.event(Fix.date(11, 19, 5, 30), .thermal(level: 2)),
            Fix.event(Fix.date(11, 19, 6, 0), .thermal(level: 0)),
            Fix.event(Fix.date(11, 19, 6, 5), .macSlept),
            Fix.event(Fix.date(11, 19, 8, 0), .macWoke),
            Fix.event(Fix.date(11, 19, 9, 32), .awayEnded),
        ]
        let receipt = build(events, from: Fix.date(11, 18, 22, 20), to: Fix.date(11, 19, 9, 32))
        let finish = Fix.date(11, 19, 3, 12)
        #expect(receipt.lines == [
            ReceiptLine(agent: "Claude Code", folder: "api", outcome: .finished(at: finish, afterSeconds: 5 * 3600 + 2 * 60), turns: 1, workSeconds: 5 * 3600 + 2 * 60),
        ])
        #expect(receipt.batteryStart == 84)
        #expect(receipt.batteryEnd == 61)
        #expect(receipt.pluggedIn == false)
        #expect(receipt.peakThermal == 2)
        #expect(receipt.sleptAt == [Fix.date(11, 19, 6, 5)])
        #expect(receipt.safetyStop == nil)
        #expect(receipt.notRunningSince == nil)
        #expect(receipt.isWorthShowing)
    }

    @Test func waitingForYouStalledAndStillWorking() {
        let from = Fix.date(11, 19, 12)
        let to = Fix.date(11, 19, 14)
        let events = [
            Fix.session(Fix.date(11, 19, 11), "w", .working, folder: "web"),
            Fix.session(Fix.date(11, 19, 12, 30), "w", .waitingForYou, folder: "web"),
            Fix.session(Fix.date(11, 19, 11, 30), "s", .working, agent: "Codex", folder: "infra"),
            Fix.session(Fix.date(11, 19, 13, 0), "s", .stalled, agent: "Codex", folder: "infra"),
            Fix.session(Fix.date(11, 19, 11, 45), "k", .working, agent: "Aider", folder: nil),
            Fix.session(Fix.date(11, 19, 12, 40), "i", .idle, folder: "notes"),
        ]
        let receipt = build(events, from: from, to: to)
        #expect(receipt.lines.map(\.outcome) == [
            .waitingForYou(since: Fix.date(11, 19, 12, 30)),
            .stalled(since: Fix.date(11, 19, 13, 0)),
            .stillWorking,
        ])
        #expect(receipt.lines.map(\.agent) == ["Claude Code", "Codex", "Aider"])
        #expect(receipt.lines[2].folder == nil)
    }

    @Test func aSessionThatWaitedAndThenEndedIsEnded() {
        let events = [
            Fix.session(Fix.date(11, 19, 11), "w", .working),
            Fix.session(Fix.date(11, 19, 12, 10), "w", .waitingForYou),
            Fix.session(Fix.date(11, 19, 13, 0), "w", .ended),
        ]
        let receipt = build(events, from: Fix.date(11, 19, 12), to: Fix.date(11, 19, 14))
        #expect(receipt.lines.map(\.outcome) == [.ended(at: Fix.date(11, 19, 13, 0))])
    }

    @Test func runThatStartedBeforeTheWindowCountsItsWholeDuration() {
        let events = [
            Fix.session(Fix.date(11, 18, 9), "a", .working),
            Fix.session(Fix.date(11, 19, 1), "a", .waitingForYou),
            Fix.session(Fix.date(11, 19, 1, 30), "a", .working),
            Fix.session(Fix.date(11, 19, 3), "a", .ended),
        ]
        let receipt = build(events, from: Fix.date(11, 19, 0), to: Fix.date(11, 19, 8))
        #expect(receipt.lines.map(\.outcome) == [.finished(at: Fix.date(11, 19, 3), afterSeconds: 18 * 3600)])
    }

    @Test func idleThroughoutAndAlreadyFinishedAreLeftOut() {
        let events = [
            Fix.session(Fix.date(11, 18, 9), "idle", .idle),
            Fix.session(Fix.date(11, 18, 9), "done", .working),
            Fix.session(Fix.date(11, 18, 10), "done", .turnDone),
            Fix.session(Fix.date(11, 18, 18), "gone", .turnDone, folder: "old"),
            Fix.session(Fix.date(11, 19, 3), "gone", .ended, folder: "old"),
        ]
        let receipt = build(events, from: Fix.date(11, 19, 0), to: Fix.date(11, 19, 8))
        #expect(receipt.lines.isEmpty)
    }

    @Test func heuristicAgentFinishesWhenItGoesIdleAfterRealWork() {
        let events = [
            Fix.session(Fix.date(11, 19, 1, 0), "x", .working, agent: "Codex"),
            Fix.session(Fix.date(11, 19, 2, 0), "x", .idle, agent: "Codex"),
            Fix.session(Fix.date(11, 19, 3, 0), "blip", .working, agent: "Aider"),
            Fix.session(Fix.date(11, 19, 3, 1), "blip", .idle, agent: "Aider"),
        ]
        let receipt = build(events, from: Fix.date(11, 19, 0), to: Fix.date(11, 19, 8))
        #expect(receipt.lines.map(\.agent) == ["Codex"])
        #expect(receipt.lines.first?.outcome == .finished(at: Fix.date(11, 19, 2), afterSeconds: 3600))
    }

    @Test func crashGapIsReported() {
        let events = [
            Fix.event(Fix.date(11, 18, 18), .appLaunched),
            Fix.session(Fix.date(11, 18, 22, 0), "a", .working),
            Fix.event(Fix.date(11, 18, 23, 0), .battery(percent: 55, onAC: false)),
            // No appQuit: power loss. Launch again in the morning.
            Fix.event(Fix.date(11, 19, 7, 0), .appLaunched),
        ]
        let receipt = build(events, from: Fix.date(11, 18, 22, 30), to: Fix.date(11, 19, 7, 5))
        #expect(receipt.notRunningSince == Fix.date(11, 18, 23, 0))
        #expect(receipt.lines.map(\.outcome) == [.ended(at: Fix.date(11, 18, 23, 0))])
        #expect(receipt.batteryStart == 55)
        #expect(receipt.isWorthShowing)
    }

    @Test func cleanQuitIsNotACrash() {
        let events = [
            Fix.event(Fix.date(11, 18, 18), .appLaunched),
            Fix.event(Fix.date(11, 18, 23, 0), .appQuit),
            Fix.event(Fix.date(11, 19, 7, 0), .appLaunched),
        ]
        let receipt = build(events, from: Fix.date(11, 18, 22, 30), to: Fix.date(11, 19, 7, 5))
        #expect(receipt.notRunningSince == nil)
        #expect(!receipt.isWorthShowing)
    }

    @Test func nothingHappenedIsNotWorthShowing() {
        let events = [
            Fix.event(Fix.date(11, 18, 18), .appLaunched),
            Fix.event(Fix.date(11, 18, 22, 0), .battery(percent: 90, onAC: true)),
            Fix.event(Fix.date(11, 18, 22, 1), .awayStarted),
            Fix.event(Fix.date(11, 19, 7, 0), .awayEnded),
        ]
        let receipt = build(events, from: Fix.date(11, 18, 22, 1), to: Fix.date(11, 19, 7, 0))
        #expect(receipt.lines.isEmpty)
        #expect(receipt.pluggedIn)
        #expect(receipt.batteryStart == 90)
        #expect(!receipt.isWorthShowing)
    }

    @Test func safetyStopIsKeptAndEventsAfterTheWindowAreIgnored() {
        let events = [
            Fix.event(Fix.date(11, 19, 2, 0), .safetyStop(.battery)),
            Fix.event(Fix.date(11, 19, 9, 0), .safetyStop(.heat)),
            Fix.session(Fix.date(11, 19, 9, 30), "late", .waitingForYou),
        ]
        let receipt = build(events, from: Fix.date(11, 19, 0), to: Fix.date(11, 19, 8))
        #expect(receipt.safetyStop == .battery)
        #expect(receipt.lines.isEmpty)
        #expect(receipt.isWorthShowing)
    }

    @Test func twelveSessionsGetTwelveLines() {
        var events: [JournalEvent] = []
        for index in 0..<12 {
            let id = "s\(index)"
            events.append(Fix.session(Fix.date(11, 19, 1, index), id, .working, folder: "p\(index)"))
            events.append(Fix.session(Fix.date(11, 19, 2, index), id, .turnDone, folder: "p\(index)"))
        }
        let receipt = build(events, from: Fix.date(11, 19, 0), to: Fix.date(11, 19, 8))
        #expect(receipt.lines.count == 12)
        // Newest finish first.
        #expect(receipt.lines.first?.folder == "p11")
        #expect(receipt.lines.last?.folder == "p0")
    }

    @Test func severalTurnsOfOneSessionAreOneLineWithTurnsAndWork() {
        let events = [
            Fix.session(Fix.date(11, 19, 1, 0), "a", .working, folder: "brain"),
            Fix.session(Fix.date(11, 19, 1, 10), "a", .turnDone, folder: "brain"),
            Fix.session(Fix.date(11, 19, 2, 0), "a", .working, folder: "brain"),
            Fix.session(Fix.date(11, 19, 2, 30), "a", .turnDone, folder: "brain"),
            Fix.session(Fix.date(11, 19, 3, 0), "a", .working, folder: "brain"),
            Fix.session(Fix.date(11, 19, 3, 5), "a", .turnDone, folder: "brain"),
        ]
        let receipt = build(events, from: Fix.date(11, 19, 0), to: Fix.date(11, 19, 8))
        #expect(receipt.lines == [
            ReceiptLine(agent: "Claude Code", folder: "brain", outcome: .finished(at: Fix.date(11, 19, 3, 5), afterSeconds: 5 * 60),
                        turns: 3, workSeconds: 45 * 60),
        ])
    }

    @Test func turnsBeforeTheWindowAreNotCountedAndALiveStateWinsTheOutcome() {
        let events = [
            Fix.session(Fix.date(11, 18, 20, 0), "a", .working),
            Fix.session(Fix.date(11, 18, 20, 30), "a", .turnDone),
            Fix.session(Fix.date(11, 19, 1, 0), "a", .working),
            Fix.session(Fix.date(11, 19, 1, 20), "a", .turnDone),
            Fix.session(Fix.date(11, 19, 2, 0), "a", .waitingForYou),
        ]
        let receipt = build(events, from: Fix.date(11, 19, 0), to: Fix.date(11, 19, 8))
        #expect(receipt.lines == [
            ReceiptLine(agent: "Claude Code", folder: "api", outcome: .waitingForYou(since: Fix.date(11, 19, 2, 0)),
                        turns: 1, workSeconds: 20 * 60),
        ])
    }

    @Test func pluggedInFollowsTheLastBatteryState() {
        let events = [
            Fix.event(Fix.date(11, 19, 0, 0), .battery(percent: 40, onAC: false)),
            Fix.event(Fix.date(11, 19, 4, 0), .battery(percent: 45, onAC: true)),
        ]
        let receipt = build(events, from: Fix.date(11, 19, 1), to: Fix.date(11, 19, 8))
        #expect(receipt.pluggedIn)
        #expect(receipt.batteryStart == 40)
        #expect(receipt.batteryEnd == 45)
    }
}
