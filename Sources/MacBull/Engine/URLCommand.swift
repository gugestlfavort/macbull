import Foundation

/// What a `macbull://` URL asks for.
enum URLCommand: Equatable {
    /// nil uses the default duration; 0 means until turned off.
    case on(minutes: Int?)
    case off
    case toggle
    case panel
    case settings(SettingsTab)
    case welcome(WelcomeStep)

    static let scheme = "macbull"
    static let maxMinutes = 10_080

    /// nil for another scheme or an unknown command.
    static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let command = commandName(url: url, components: components) else { return nil }
        let items = components?.queryItems ?? []
        switch command {
        case "on":
            return .on(minutes: minutes(items.first { $0.name == "minutes" }?.value))
        case "off":
            return .off
        case "toggle":
            return .toggle
        case "panel":
            return .panel
        case "settings":
            let tab = items.first { $0.name == "tab" }?.value.flatMap { SettingsTab(rawValue: $0.lowercased()) }
            return .settings(tab ?? .general)
        case "welcome":
            let step = items.first { $0.name == "step" }?.value.flatMap { WelcomeStep(rawValue: $0.lowercased()) }
            return .welcome(step ?? .hello)
        default:
            return nil
        }
    }

    /// The command is the host. `macbull:on` (no slashes) is read from the path.
    private static func commandName(url: URL, components: URLComponents?) -> String? {
        if let host = components?.host, !host.isEmpty { return host.lowercased() }
        let path = components?.path.split(separator: "/").first.map(String.init)
        return path?.lowercased()
    }

    /// Whole number 1...10080 is that many minutes. Any other number means until turned off.
    /// Missing or not a number means the default duration (nil).
    private static func minutes(_ raw: String?) -> Int? {
        guard let raw, let value = Int(raw) else { return nil }
        return (1...maxMinutes).contains(value) ? value : 0
    }
}
