import Foundation

/// The rule file `/etc/sudoers.d/macbull`: exactly four commands, nothing else.
enum SudoRule {
    static let filePath = "/etc/sudoers.d/macbull"

    /// One line for the given short account name.
    static func text(forAccount account: String) -> String {
        let commands = PmsetCommand.allCases.map(\.text).joined(separator: ", ")
        return "\(account) ALL=(root) NOPASSWD: \(commands)"
    }
}
