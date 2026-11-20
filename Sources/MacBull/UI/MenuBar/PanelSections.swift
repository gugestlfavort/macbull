import SwiftUI

// The parts of the panel under and around the hero: Your Turn, quick picks, the cutoff banner,
// the modes box with the agents list, and the footer.

// MARK: - Your Turn

struct PanelYourTurn: View {
    let env: AppEnvironment
    private static let maxRows = 6

    /// Sessions whose hosting app could not be reached, so the row says so.
    @State private var unreachable: Set<String> = []

    var body: some View {
        let rows = YourTurnRows.rows(from: env.state.sessions)
        if !rows.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your turn")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    ForEach(rows.prefix(Self.maxRows)) { session in
                        row(session, now: context.date)
                    }
                    if rows.count > Self.maxRows {
                        Text("+\(rows.count - Self.maxRows) more")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.box, style: .continuous)
                        .fill(Theme.electric.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.box, style: .continuous)
                        .strokeBorder(Theme.electric.opacity(0.35), lineWidth: 1)
                )
            }
        }
    }

    @ViewBuilder
    private func row(_ session: AgentSession, now: Date) -> some View {
        let isWaiting = session.activity == .waitingForYou
        let clickable = YourTurnRows.isClickable(session)
        let timing = isWaiting
            ? PanelFormat.waiting(since: session.since, now: now)
            : PanelFormat.stalled(lastSignOfLife: session.lastSignOfLife, now: now)
        let content = HStack(spacing: 9) {
            Image(systemName: isWaiting ? "hand.raised.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isWaiting ? Theme.electric : Color.orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(rowTitle(session))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(unreachable.contains(session.id) ? "\(timing), no window to open" : timing)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if clickable {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        if clickable {
            Button { open(session) } label: { content }
                .buttonStyle(PanelRowButtonStyle())
                .accessibilityHint("Brings the app hosting this session to the front")
        } else {
            content
        }
    }

    private func rowTitle(_ session: AgentSession) -> String {
        guard let folder = session.folder, !folder.isEmpty else { return session.agent }
        return "\(session.agent) in \(folder)"
    }

    private func open(_ session: AgentSession) {
        if env.actions.bringToFront(sessionID: session.id) {
            unreachable.remove(session.id)
        } else {
            unreachable.insert(session.id)
        }
    }
}

private struct PanelRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private func highlight(pressed: Bool) -> Double {
        if pressed { return 0.12 }
        return isHovering ? 0.07 : 0
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Color.primary.opacity(highlight(pressed: configuration.isPressed)))
            )
            .onHover { isHovering = $0 }
    }
}

// MARK: - Quick picks

struct PanelQuickPicks: View {
    let env: AppEnvironment

    var body: some View {
        let selected = env.state.manual?.minutes
        HStack(spacing: 6) {
            ForEach(QuickPick.all) { pick in
                chip(pick, isSelected: selected == pick.minutes)
            }
        }
    }

    private func chip(_ pick: QuickPick, isSelected: Bool) -> some View {
        Button {
            press(pick, isSelected: isSelected)
        } label: {
            Text(pick.label)
                .font(.system(size: pick.minutes == 0 ? 16 : 13, weight: .medium))
                .foregroundStyle(isSelected ? Theme.navyDeep : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(isSelected ? Theme.volt : Color.primary.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pick.spokenName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func press(_ pick: QuickPick, isSelected: Bool) {
        if isSelected {
            env.actions.turnOff()
            env.feedback.play(.clink)
        } else {
            env.actions.turnOn(minutes: pick.minutes)
            env.feedback.play(.crack)
        }
    }
}

// MARK: - Cutoff banner

struct PanelCutoffBanner: View {
    let stop: SafetyStop

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: stop == .heat ? "thermometer.high" : "battery.25")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text(stop == .heat
                 ? "Your Mac got too warm, so MacBull let it rest."
                 : "The battery got low, so MacBull let your Mac sleep.")
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.banner, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Modes box

struct PanelModesBox: View {
    let env: AppEnvironment
    let closePanel: () -> Void
    private static let maxSessionsPerAgent = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if env.state.lidSetup != .noLid {
                lidRow
            }
            agentsRow
            if env.settings.agentMode, !env.state.agents.isEmpty {
                agentsList
                    .padding(.leading, 40)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.box, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: Lid row

    private var lidRow: some View {
        let setup = env.state.lidSetup
        let isOn = ModesCopy.lidEffectivelyOn(setup: setup, lidHold: env.settings.lidHold)
        return HStack(spacing: 10) {
            PanelModeSymbol(systemName: "laptopcomputer", isOn: isOn)
            VStack(alignment: .leading, spacing: 1) {
                Text("Lid closed")
                    .font(.system(size: 13, weight: .semibold))
                Text(ModesCopy.lidDetail(setup: setup, lidHold: env.settings.lidHold, isAwake: env.state.isAwake))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if setup == .notSetUp {
                Button("Set up") {
                    closePanel()
                    env.actions.openSettings(.lid)
                }
                .buttonStyle(PanelProminentButtonStyle())
            } else {
                PanelSwitch(isOn: Binding(get: { env.settings.lidHold }, set: { env.settings.lidHold = $0 }),
                            label: "Keep working with the lid closed")
            }
        }
    }

    // MARK: Agents row

    private var agentsRow: some View {
        let facts = ModesCopy.AgentsFacts(
            agentMode: env.settings.agentMode,
            agents: env.state.agents,
            isAwake: env.state.isAwake,
            cutoff: env.state.cutoff,
            paused: env.state.paused,
            agentHold: env.state.agentHold,
            lidEffectivelyOn: ModesCopy.lidEffectivelyOn(setup: env.state.lidSetup, lidHold: env.settings.lidHold))
        return HStack(spacing: 10) {
            PanelModeSymbol(systemName: "sparkles", isOn: env.settings.agentMode)
            VStack(alignment: .leading, spacing: 1) {
                Text("AI agents")
                    .font(.system(size: 13, weight: .semibold))
                Text(ModesCopy.agentsDetail(facts))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PanelSwitch(isOn: Binding(get: { env.settings.agentMode }, set: { env.settings.agentMode = $0 }),
                        label: "Keep awake while AI agents work")
        }
    }

    // MARK: Agents list

    private var agentsList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(env.state.agents) { agent in
                agentLine(agent)
                let sessions = ModesCopy.detailedSessions(of: agent, in: env.state.sessions)
                ForEach(sessions.prefix(Self.maxSessionsPerAgent)) { session in
                    sessionLine(session)
                }
                if sessions.count > Self.maxSessionsPerAgent {
                    Text("+\(sessions.count - Self.maxSessionsPerAgent) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 17)
                }
            }
        }
    }

    private func agentLine(_ agent: AgentSummary) -> some View {
        let status = ModesCopy.status(of: agent)
        return HStack(spacing: 8) {
            PanelStatusDot(isWorking: agent.isWorking && status != .waiting)
            Text(agent.name)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            if agent.sessions > 1 {
                Text("x \(agent.sessions)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(status.word)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(statusColor(status))
        }
        .accessibilityElement(children: .combine)
    }

    private func sessionLine(_ session: AgentSession) -> some View {
        HStack(spacing: 6) {
            Text(session.folder ?? "")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(ModesCopy.word(for: session.activity))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.leading, 17)
        .accessibilityElement(children: .combine)
    }

    private func statusColor(_ status: ModesCopy.AgentStatus) -> Color {
        switch status {
        case .running, .working: Color.green
        case .backgroundRun: Theme.voltInk
        case .waiting: Theme.electric
        case .stalled: Color.orange
        case .idle: Color.secondary
        }
    }
}

/// Green and pulsing while working, dim grey otherwise.
struct PanelStatusDot: View {
    var isWorking: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            if isWorking, !reduceMotion {
                Circle()
                    .stroke(Color.green.opacity(0.6), lineWidth: 1)
                    .frame(width: 7, height: 7)
                    .scaleEffect(pulsing ? 2.6 : 1)
                    .opacity(pulsing ? 0 : 0.8)
            }
            Circle()
                .fill(isWorking ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
        }
        .frame(width: 9, height: 9)
        .onAppear {
            guard isWorking, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Footer

struct PanelFooter: View {
    let env: AppEnvironment
    let closePanel: () -> Void
    let showNutrition: () -> Void
    let showReceipts: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                leading
                Spacer(minLength: 4)
                trailing
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) { leading }
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
    }

    @ViewBuilder
    private var leading: some View {
        Button("Settings") {
            closePanel()
            env.actions.openSettings(.general)
        }
        .buttonStyle(PanelQuietButtonStyle())
        Button("Nutrition facts", action: showNutrition)
            .buttonStyle(PanelQuietButtonStyle())
        if !env.state.receipts.isEmpty {
            Button("Receipts", action: showReceipts)
                .buttonStyle(PanelQuietButtonStyle())
        }
    }

    @ViewBuilder
    private var trailing: some View {
        // Always shown, so the footer does not change height when the lid hold comes and goes.
        Button("Sleep Now") {
            closePanel()
            env.actions.sleepNow()
        }
        .buttonStyle(PanelQuietButtonStyle())
        .help("Turns everything off and puts the Mac to sleep")
        Button("Quit") {
            env.actions.quit()
        }
        .buttonStyle(PanelQuietButtonStyle())
    }
}
