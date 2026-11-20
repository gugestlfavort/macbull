import Foundation

/// The choices offered by the pickers, and how they read.
enum SettingsOptions {
    struct Choice: Identifiable, Equatable {
        var value: Int
        var label: String
        var id: Int { value }
    }

    /// Default duration; 0 means until turned off.
    static let durations: [Choice] = [15, 30, 60, 120, 180, 300, 480, 0].map {
        Choice(value: $0, label: durationLabel(minutes: $0))
    }
    static let graceMinutes: [Choice] = [1, 2, 3, 5, 10].map {
        Choice(value: $0, label: "\($0) min")
    }
    static let batteryPercents: [Choice] = [10, 15, 20, 30, 50].map {
        Choice(value: $0, label: "\($0)% or less")
    }
    static let remindAfter: [Choice] = [0, 2, 5, 15].map {
        Choice(value: $0, label: $0 == 0 ? "Never" : "\($0) min")
    }
    static let minimumAway: [Choice] = [10, 20, 30, 60].map {
        Choice(value: $0, label: "\($0) min")
    }
    static let historyDays: [Choice] = [7, 30, 90].map {
        Choice(value: $0, label: "\($0) days")
    }
    static let hours: [Choice] = (0..<24).map {
        Choice(value: $0, label: hourLabel($0))
    }

    static func durationLabel(minutes: Int) -> String {
        switch minutes {
        case 0: "Until turned off"
        case ..<60: "\(minutes) minutes"
        case 60: "1 hour"
        default: minutes.isMultiple(of: 60) ? "\(minutes / 60) hours" : "\(minutes) minutes"
        }
    }

    static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    /// The stored value when it is not one of the choices (set by hand), so a picker never shows blank.
    static func including(_ value: Int, in choices: [Choice], label: (Int) -> String) -> [Choice] {
        choices.contains { $0.value == value } ? choices : choices + [Choice(value: value, label: label(value))]
    }
}

/// Automation examples shown in General.
enum AutomationExamples {
    static let urls = [
        "macbull://on",
        "macbull://on?minutes=30",
        "macbull://off",
        "macbull://toggle",
        "macbull://panel",
        "macbull://settings?tab=away",
    ]
}

enum AppVersion {
    /// "dev" when the app runs unbundled.
    static func label(infoDictionary: [String: Any]?) -> String {
        guard let version = infoDictionary?["CFBundleShortVersionString"] as? String, !version.isEmpty else {
            return "dev"
        }
        return version
    }
}

enum LoginItemCopy {
    static let loginItemsSettingsURL = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

    static let needsApproval = "macOS is waiting for your approval. Allow MacBull under Login Items."
    static let failed = "macOS did not accept that. Try moving MacBull to the Applications folder first."

    static func isOn(_ status: LoginItemStatus) -> Bool {
        switch status {
        case .enabled, .needsApproval: true
        case .disabled, .failed: false
        }
    }
}
