import AppKit

/// Opens the Settings and Welcome windows. One of each; asking again reuses and fronts it.
@MainActor
final class WindowController: WindowPresenting {
    private let env: AppEnvironment
    private let hasLid: Bool
    private let agentNames: [String]
    private var settingsWindow: SettingsWindowController?
    private var welcomeWindow: WelcomeWindowController?

    /// - Parameters:
    ///   - hasLid: false hides the lid tab's controls and the lid step of the welcome flow.
    ///   - agentNames: display names of the catalogue agents, for "Works with".
    init(env: AppEnvironment, hasLid: Bool, agentNames: [String]) {
        self.env = env
        self.hasLid = hasLid
        self.agentNames = agentNames
    }

    func openSettings(_ tab: SettingsTab) {
        let controller = settingsWindow ?? SettingsWindowController(
            env: env, hasLid: hasLid, agentNames: agentNames,
            icon: NSApp.applicationIconImage ?? NSImage(),
            version: AppVersion.label(infoDictionary: Bundle.main.infoDictionary)
        )
        settingsWindow = controller
        controller.show(tab)
    }

    func openWelcome(_ step: WelcomeStep) {
        let controller = welcomeWindow ?? WelcomeWindowController(
            env: env, hasLid: hasLid, icon: NSApp.applicationIconImage ?? NSImage(), start: step
        )
        welcomeWindow = controller
        controller.show(step)
    }

    /// The windows, for tests.
    var settingsNSWindow: NSWindow? { settingsWindow?.window }
    var welcomeNSWindow: NSWindow? { welcomeWindow?.window }
}
