import SwiftUI

struct LidTab: View {
    let env: AppEnvironment
    let hasLid: Bool
    @Bindable private var settings: Settings
    @Bindable private var state: AppState
    @State private var runner = LidSetupRunner()

    init(env: AppEnvironment, hasLid: Bool) {
        self.env = env
        self.hasLid = hasLid
        settings = env.settings
        state = env.state
    }

    private var isReady: Bool { state.lidSetup == .ready }

    var body: some View {
        Form {
            if hasLid {
                permissionSection
                switchesSection
            } else {
                Section {
                    Text("This Mac has no lid, so there is nothing to set up here.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var permissionSection: some View {
        Section("Permission") {
            if isReady {
                HStack {
                    SettingsStatusRow(text: "Ready", symbol: "checkmark.circle.fill", color: .green)
                    Spacer()
                    removeButton
                }
            } else {
                Text("Without an external display, a Mac goes to sleep when you close the lid. MacBull can stop that, but it needs your password once.")
                Footnote("It adds one rule to the sudoers folder. The rule lets MacBull switch sleep and Low Power Mode on and off, and nothing else.")
                HStack {
                    Button("Allow lid closed mode\u{2026}") { install() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.electric)
                        .disabled(runner.isWorking)
                    if runner.isWorking { ProgressView().controlSize(.small) }
                }
            }
            if let message = runner.errorText ?? state.lidError {
                SettingsStatusRow(text: message, symbol: "exclamationmark.triangle.fill", color: .orange)
            }
        }
    }

    private var removeButton: some View {
        HStack {
            if runner.isWorking { ProgressView().controlSize(.small) }
            Button("Remove permission\u{2026}") { remove() }
                .disabled(runner.isWorking)
        }
    }

    private var switchesSection: some View {
        Section {
            Toggle("Keep working with the lid closed", isOn: Binding(
                get: { isReady && settings.lidHold },
                set: { settings.lidHold = $0 }
            ))
            .disabled(!isReady)
            Toggle("Use Low Power Mode while the lid is closed", isOn: $settings.lowPowerInBag)
                .disabled(!isReady)
            Footnote("Works for timed sessions and for agents. With the lid closed the display goes dark at once, and the Mac is put to sleep when the work is done. While it is held, the Apple menu's Sleep does nothing: use Sleep Now in the panel. With an external display connected, a closed lid is a normal desk setup and these rules step aside.")
        }
    }

    private func install() {
        Task { await runner.run { await env.actions.installLid() } }
    }

    private func remove() {
        Task { await runner.run { await env.actions.removeLid() } }
    }
}
