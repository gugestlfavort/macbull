import AppKit
import Foundation
@testable import MacBull

/// Stand-in for the engine's actions: records calls, answers with canned values.
@MainActor
final class WindowsFakeActions: AppActions {
    var calls: [String] = []
    var loginStatus: LoginItemStatus = .disabled
    /// What `setLoginItem(true)` answers.
    var loginAnswer: LoginItemStatus = .enabled
    var installResult: LidSetupResult = .success
    var removeResult: LidSetupResult = .success
    var onInstall: (@MainActor () -> Void)?

    func turnOn(minutes: Int?) { calls.append("turnOn") }
    func turnOff() { calls.append("turnOff") }
    func toggle() { calls.append("toggle") }
    func sleepNow() { calls.append("sleepNow") }

    func installLid() async -> LidSetupResult {
        calls.append("installLid")
        onInstall?()
        return installResult
    }

    func removeLid() async -> LidSetupResult {
        calls.append("removeLid")
        return removeResult
    }

    func bringToFront(sessionID: String) -> Bool { false }
    func showPanel() { calls.append("showPanel") }
    func openSettings(_ tab: SettingsTab) { calls.append("openSettings:\(tab.rawValue)") }
    func openWelcome(_ step: WelcomeStep) { calls.append("openWelcome:\(step.rawValue)") }
    func dismissReceipt() { calls.append("dismissReceipt") }
    func nutrition(_ range: StatsRange) -> NutritionStats { .empty }
    func eraseHistory() { calls.append("eraseHistory") }
    func loginItemStatus() -> LoginItemStatus { loginStatus }

    func setLoginItem(_ enabled: Bool) -> LoginItemStatus {
        calls.append("setLoginItem:\(enabled)")
        loginStatus = enabled ? loginAnswer : .disabled
        return loginStatus
    }

    func quit() { calls.append("quit") }
}

@MainActor
final class WindowsFakeFeedback: FeedbackPlaying {
    var cues: [SoundCue] = []
    func play(_ cue: SoundCue) { cues.append(cue) }
    func setFizz(_ level: Double?) {}
    func detent(strong: Bool) {}
}

@MainActor
final class WindowsFakeHaptics: HapticPerforming {
    var patterns: [NSHapticFeedbackManager.FeedbackPattern] = []
    func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) { patterns.append(pattern) }
}

enum WindowsTestSupport {
    /// The repo root, found from this file's path.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let soundsFolder = repoRoot.appendingPathComponent("Resources/Sounds")
    static let iconFile = repoRoot.appendingPathComponent("Resources/AppIcon.png")

    @MainActor
    static func makeSettings() -> Settings {
        let name = "macbull.windows.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return Settings(defaults: defaults)
    }

    @MainActor
    static func makeEnvironment(
        actions: WindowsFakeActions = WindowsFakeActions(),
        feedback: FeedbackPlaying = WindowsFakeFeedback(),
        settings: Settings? = nil
    ) -> AppEnvironment {
        AppEnvironment(state: AppState(), settings: settings ?? makeSettings(), actions: actions, feedback: feedback)
    }
}
