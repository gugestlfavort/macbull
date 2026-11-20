import SwiftUI

struct SafetyTab: View {
    @Bindable private var settings: Settings

    init(env: AppEnvironment) {
        settings = env.settings
    }

    var body: some View {
        Form {
            Section {
                Toggle("Turn off when the battery is low", isOn: $settings.batteryGuard)
                ChoicePicker(
                    title: "Low means",
                    choices: SettingsOptions.including(settings.batteryPercent, in: SettingsOptions.batteryPercents) { "\($0)% or less" },
                    selection: $settings.batteryPercent
                )
                .disabled(!settings.batteryGuard)
                Footnote("This only counts when the Mac is not plugged in.")
            }
            Section {
                Toggle("Turn off when the Mac gets hot", isOn: $settings.heatGuard)
                Footnote("With the lid closed, MacBull stops at the first warm level, because a closed Mac in a bag cannot cool down.")
            }
        }
        .formStyle(.grouped)
    }
}
