import Foundation
import Observation

/// Where the welcome flow is. Pure, so the step rules can be tested.
struct WelcomeFlow: Equatable {
    let steps: [WelcomeStep]
    private(set) var current: WelcomeStep

    /// Macs without a lid skip the lid step; asking for it starts at the agents step.
    init(start: WelcomeStep, hasLid: Bool) {
        let all = WelcomeStep.allCases.filter { hasLid || $0 != .lid }
        steps = all
        current = all.contains(start) ? start : .agents
    }

    var index: Int { steps.firstIndex(of: current) ?? 0 }
    var count: Int { steps.count }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == steps.count - 1 }
    var progressLabel: String { "Step \(index + 1) of \(count)" }

    mutating func next() {
        guard !isLast else { return }
        current = steps[index + 1]
    }

    mutating func back() {
        guard !isFirst else { return }
        current = steps[index - 1]
    }
}

/// What the agents step says under the switch.
enum WelcomeAgentsLine {
    static func text(agentMode: Bool, agents: [AgentSummary]) -> String {
        if !agentMode { return "Off for now. You can turn it on later from the panel." }
        if agents.isEmpty { return "None open right now. MacBull starts by itself when one does." }
        let names = agents.map { $0.sessions > 1 ? "\($0.name) (\($0.sessions) open)" : $0.name }
        return "Right now: \(names.joined(separator: ", "))"
    }
}

@MainActor
@Observable
final class WelcomeModel {
    var flow: WelcomeFlow
    private let hasLid: Bool

    init(start: WelcomeStep, hasLid: Bool) {
        self.hasLid = hasLid
        flow = WelcomeFlow(start: start, hasLid: hasLid)
    }

    func restart(at step: WelcomeStep) {
        flow = WelcomeFlow(start: step, hasLid: hasLid)
    }
}
