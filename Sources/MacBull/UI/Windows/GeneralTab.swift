import AppKit
import SwiftUI

struct GeneralTab: View {
    let env: AppEnvironment
    @Bindable private var settings: Settings
    @State private var login: LoginItemModel
    @State private var copiedURL: String?

    init(env: AppEnvironment) {
        self.env = env
        settings = env.settings
        _login = State(initialValue: LoginItemModel(actions: env.actions))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { LoginItemCopy.isOn(login.status) },
                    set: { login.set($0) }
                ))
                LoginItemNotes(model: login)
                Toggle("Turn on when MacBull opens", isOn: $settings.startOnLaunch)
                Toggle("Notify me when agents finish or a safety limit stops the work", isOn: $settings.notifications)
                ChoicePicker(
                    title: "Default duration",
                    choices: SettingsOptions.including(settings.defaultMinutes, in: SettingsOptions.durations) {
                        SettingsOptions.durationLabel(minutes: $0)
                    },
                    selection: $settings.defaultMinutes
                )
                Toggle("Keep the display on too", isOn: $settings.keepDisplayOn)
                Toggle("Clicking the can switches it on and off", isOn: $settings.clickToggles)
                Footnote(clickFootnote)
            }
            Section("Sound and feel") {
                Toggle("Sounds in the panel", isOn: $settings.sounds)
                LabeledContent("Volume") {
                    Slider(value: $settings.soundVolume, in: 0...1) { editing in
                        if !editing { env.feedback.play(.clink) }
                    }
                    .frame(width: 180)
                }
                .disabled(!settings.sounds)
                Toggle("Haptics on the trackpad", isOn: $settings.haptics)
                Toggle("Sounds in notifications", isOn: $settings.notificationSounds)
                Footnote("Panel sounds follow the system setting for interface sound effects.")
            }
            Section("Automation") {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(AutomationExamples.urls, id: \.self) { url in
                        HStack {
                            Text(url)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Button(copiedURL == url ? "Copied" : "Copy") { copy(url) }
                                .buttonStyle(.link)
                        }
                    }
                }
                Footnote("Run them from Terminal or a shortcut, for example: open -g \"macbull://on?minutes=30\"")
            }
        }
        .formStyle(.grouped)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }

    private var clickFootnote: String {
        settings.clickToggles
            ? "A right click opens the panel. Option click still switches it on and off."
            : "Option click on the can switches it on and off. A plain click opens the panel."
    }

    private func copy(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        copiedURL = url
    }
}
