import SwiftUI

extension SettingsTab {
    var title: String {
        switch self {
        case .general: "General"
        case .lid: "Lid Closed"
        case .agents: "AI Agents"
        case .safety: "Safety"
        case .away: "Away"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .lid: "laptopcomputer"
        case .agents: "cpu"
        case .safety: "shield.lefthalf.filled"
        case .away: "moon.zzz"
        case .about: "info.circle"
        }
    }
}

/// Fixed width of every Settings tab.
let settingsContentWidth: CGFloat = 480

/// The content of one Settings tab.
struct SettingsTabContent: View {
    let tab: SettingsTab
    let env: AppEnvironment
    let hasLid: Bool
    let agentNames: [String]
    let icon: NSImage
    let version: String

    var body: some View {
        content.frame(width: settingsContentWidth)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general: GeneralTab(env: env)
        case .lid: LidTab(env: env, hasLid: hasLid)
        case .agents: AgentsTab(env: env, agentNames: agentNames)
        case .safety: SafetyTab(env: env)
        case .away: AwayTab(env: env)
        case .about: AboutTab(env: env, icon: icon, version: version)
        }
    }
}
