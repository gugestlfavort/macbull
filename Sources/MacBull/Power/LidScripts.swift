import Foundation

/// The two root scripts behind the admin prompt, and the quoting that carries them there.
/// Untrusted text (the account name, file paths) never reaches a shell unquoted: file contents
/// travel base64-encoded, paths travel as positional parameters.
enum LidScripts {
    private static let setupName = "macbull-setup"
    private static let removeName = "macbull-remove"

    /// Steps run as root, stopping at the first error.
    static func installScript(rule: String, plist: String) -> String {
        let ruleData = Data((rule + "\n").utf8).base64EncodedString()
        let plistData = Data(plist.utf8).base64EncodedString()
        return """
        set -e
        rule_tmp=$(/usr/bin/mktemp /private/tmp/macbull-rule.XXXXXX)
        plist_tmp=$(/usr/bin/mktemp /private/tmp/macbull-plist.XXXXXX)
        trap '/bin/rm -f "$rule_tmp" "$plist_tmp"' EXIT
        printf '%s' '\(ruleData)' | /usr/bin/base64 -D > "$rule_tmp"
        /usr/sbin/visudo -cf "$rule_tmp"
        /bin/mkdir -p -m 0755 /private/etc/sudoers.d
        /usr/bin/install -m 0440 -o root -g wheel "$rule_tmp" \(SudoRule.filePath)
        /usr/sbin/visudo -c || { /bin/rm -f \(SudoRule.filePath); exit 1; }
        printf '%s' '\(plistData)' | /usr/bin/base64 -D > "$plist_tmp"
        /usr/bin/plutil -lint "$plist_tmp"
        /usr/bin/install -m 0644 -o root -g wheel "$plist_tmp" \(BootDaemon.plistPath)
        """
    }

    /// `$1` sleep flag, `$2` low power flag. Only undoes what MacBull changed. Stops at the
    /// first error so a failed undo never leaves the app without its permission.
    static let uninstallScript = """
    set -e
    if [ -e "$1" ]; then \(PmsetCommand.holdOff.text); fi
    if [ -e "$2" ]; then \(PmsetCommand.lowPowerOff.text); fi
    /bin/launchctl bootout system/\(BootDaemon.label) 2>/dev/null || true
    /bin/rm -f \(SudoRule.filePath) \(BootDaemon.plistPath)
    """

    static func installCommand(rule: String, plist: String) -> String {
        "/bin/sh -c \(shellQuote(installScript(rule: rule, plist: plist))) \(setupName)"
    }

    static func uninstallCommand(sleepFlag: String, lowPowerFlag: String) -> String {
        let arguments = [uninstallScript, removeName, sleepFlag, lowPowerFlag].map(shellQuote)
        return "/bin/sh -c " + arguments.joined(separator: " ")
    }

    /// POSIX single-quote quoting.
    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
