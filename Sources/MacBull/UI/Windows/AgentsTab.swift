import SwiftUI

struct AgentsTab: View {
    let env: AppEnvironment
    let agentNames: [String]
    @Bindable private var settings: Settings
    @Bindable private var state: AppState
    @State private var newAgent = ""

    init(env: AppEnvironment, agentNames: [String]) {
        self.env = env
        self.agentNames = agentNames
        settings = env.settings
        state = env.state
    }

    var body: some View {
        Form {
            stayAwakeSection
            hooksSection
            yourTurnSection
            rightNowSection
            worksWithSection
            ownAgentsSection
        }
        .formStyle(.grouped)
    }

    private var stayAwakeSection: some View {
        Section {
            Toggle("Stay awake while AI agents work", isOn: $settings.agentMode)
            ChoicePicker(
                title: "Let go after they are quiet for",
                choices: SettingsOptions.including(settings.graceMinutes, in: SettingsOptions.graceMinutes) { "\($0) min" },
                selection: $settings.graceMinutes
            )
            .disabled(!settings.agentMode)
            Footnote("No setup needed. MacBull watches for agents that really work. Background runs such as claude -p or codex exec count until they end. With lid closed mode set up, they keep going with the lid shut.")
        }
    }

    private var hooksSection: some View {
        Section {
            Toggle("Use Claude Code hooks (exact)", isOn: $settings.claudeHooks)
            Footnote("Adds a small entry for each Claude Code event to ~/.claude/settings.json, so MacBull knows exactly when a session works or waits. Turning it off removes the entries. Sessions that are already open pick it up after Claude Code restarts.")
            if let error = state.hooksError {
                SettingsStatusRow(text: error, symbol: "xmark.octagon.fill", color: .red)
            }
            Toggle("Flag agents that look stuck", isOn: $settings.stallWatchdog)
            Footnote("Stall Watchdog: a session that claims to work but shows no sign of life for 10 minutes is marked as stuck. After 20 minutes it stops keeping the Mac awake. MacBull never touches the process.")
        }
    }

    private var yourTurnSection: some View {
        Section("Your turn") {
            Toggle("Show how many agents wait for you", isOn: $settings.showWaitingCount)
            Toggle("Light up the screen when one needs you", isOn: $settings.wakeScreenWhenWaiting)
            HStack {
                ChoicePicker(title: "Quiet hours from", choices: SettingsOptions.hours, selection: $settings.quietHoursStart)
                ChoicePicker(title: "to", choices: SettingsOptions.hours, selection: $settings.quietHoursEnd)
            }
            .disabled(!settings.wakeScreenWhenWaiting)
            ChoicePicker(title: "Remind me after", choices: SettingsOptions.remindAfter, selection: $settings.remindAfterMinutes)
            Footnote("Only agents with Claude Code hooks can say they are waiting. The screen only lights up with the lid open and outside quiet hours.")
        }
    }

    private var rightNowSection: some View {
        Section("Right now") {
            if !settings.agentMode {
                Text("Turned off").foregroundStyle(.secondary)
            } else if state.agents.isEmpty {
                Text("No agents running").foregroundStyle(.secondary)
            } else {
                ForEach(state.agents) { agent in
                    AgentRow(agent: agent)
                }
            }
        }
    }

    private var worksWithSection: some View {
        Section("Works with") {
            Text(agentNames.joined(separator: ", "))
                .foregroundStyle(.secondary)
        }
    }

    private var ownAgentsSection: some View {
        Section("Your own agents") {
            ForEach(settings.customAgents, id: \.self) { name in
                HStack {
                    Text(name).font(.system(.body, design: .monospaced))
                    Spacer()
                    Button("Remove") { settings.customAgents.removeAll { $0 == name } }
                        .buttonStyle(.link)
                }
            }
            HStack {
                TextField("Script or command", text: $newAgent, prompt: Text("Script or command, for example my_agent.py"))
                    .labelsHidden()
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(outcome.name == nil)
            }
            if case .rejected(let reason) = outcome, let hint = CustomAgentNames.hint(for: reason) {
                SettingsStatusRow(text: hint, symbol: "exclamationmark.triangle.fill", color: .orange)
            }
            Footnote("Type the script or command name. The Mac stays awake as long as it runs and is let go when it ends.")
        }
        .disabled(!settings.agentMode)
    }

    private var outcome: CustomAgentNames.Outcome {
        CustomAgentNames.evaluate(newAgent)
    }

    private func add() {
        guard let name = outcome.name else { return }
        if !settings.customAgents.contains(name) {
            settings.customAgents.append(name)
        }
        newAgent = ""
    }
}

/// One agent in "Right now": name, a dot and the status word.
struct AgentRow: View {
    let agent: AgentSummary

    var body: some View {
        HStack {
            Text(agent.sessions > 1 ? "\(agent.name) (\(agent.sessions) sessions)" : agent.name)
            Spacer()
            Circle()
                .fill(agent.isWorking ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(AgentStatusWord.text(for: agent))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

enum AgentStatusWord {
    static func text(for agent: AgentSummary) -> String {
        var word = "Idle"
        if agent.isCustom {
            word = "Running"
        } else if agent.backgroundRuns > 0 {
            word = "Background run"
        } else if agent.isWorking {
            word = "Working"
        }
        if agent.waitingForYou > 0 { word += ", waiting for you" }
        if agent.stalled > 0 { word += ", stuck" }
        return word
    }
}
