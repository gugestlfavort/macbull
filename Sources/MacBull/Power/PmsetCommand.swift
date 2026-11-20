import Foundation

/// The four pmset changes MacBull may make as root. The sudoers rule, the listing parser and
/// the commands the app runs all come from this one list, so they cannot drift apart.
enum PmsetCommand: CaseIterable, Sendable {
    case holdOn
    case holdOff
    case lowPowerOn
    case lowPowerOff

    static let pmsetPath = "/usr/bin/pmset"
    static let sudoPath = "/usr/bin/sudo"

    var arguments: [String] {
        switch self {
        case .holdOn: ["-a", "disablesleep", "1"]
        case .holdOff: ["-a", "disablesleep", "0"]
        case .lowPowerOn: ["-b", "lowpowermode", "1"]
        case .lowPowerOff: ["-b", "lowpowermode", "0"]
        }
    }

    /// The command as written in the sudoers rule and printed by `sudo -l`.
    var text: String {
        ([Self.pmsetPath] + arguments).joined(separator: " ")
    }

    /// Arguments for `/usr/bin/sudo`: non-interactive, so a missing rule fails instead of prompting.
    var sudoArguments: [String] {
        ["-n", Self.pmsetPath] + arguments
    }

    /// The full command line as it appears in scripts.
    var sudoText: String {
        ([Self.sudoPath] + sudoArguments).joined(separator: " ")
    }
}
