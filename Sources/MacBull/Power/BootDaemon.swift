import Foundation

/// The launchd daemon that undoes our pmset changes at every boot. After a dead battery or a
/// hard shutdown neither the watchdog nor the launch-time cleanup has run, and both settings persist.
enum BootDaemon {
    static let label = "app.macbull.boot-reset"
    static let plistPath = "/Library/LaunchDaemons/app.macbull.boot-reset.plist"
    /// The script's own name as `$0`.
    static let scriptName = "macbull-boot-reset"

    /// Runs as root at boot. `$1` sleep flag, `$2` low power flag, `$3` in-bag flag. Every step is
    /// independent and the exit status is always 0. A flag stays when its pmset call fails.
    static let script = """
    if [ -e "$1" ]; then /usr/bin/pmset -a disablesleep 0 && /bin/rm -f "$1"; fi
    if [ -e "$2" ]; then /usr/bin/pmset -b lowpowermode 0 && /bin/rm -f "$2"; fi
    /bin/rm -f "$3"
    exit 0
    """

    /// The plist: Label, ProgramArguments, RunAtLoad, nothing else. `flagPaths` is sleep, low power, in bag.
    static func plist(flagPaths: [String]) -> String {
        let arguments = ["/bin/sh", "-c", script, scriptName] + flagPaths
        let items = arguments.map { "        <string>\(xmlEscape($0))</string>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
        \(items)
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>

        """
    }

    static func xmlEscape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }
}
