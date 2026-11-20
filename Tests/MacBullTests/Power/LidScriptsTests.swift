import Foundation
import Testing
@testable import MacBull

struct LidScriptsTests {
    private static let rule = SudoRule.text(forAccount: "tester")
    private static let flags = ["/Users/a b/Library/Application Support/MacBull/sleep-disabled", "/x/low", "/x/bag"]
    private static let plist = BootDaemon.plist(flagPaths: flags)

    /// Runs `sh -n`, which only parses the script.
    private func syntaxErrors(of script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", "-c", script]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? "" : String(decoding: data, as: UTF8.self)
    }

    /// The text a quoted string turns back into when `sh` reads it.
    private func shellRoundTrip(_ text: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf %s \(LidScripts.shellQuote(text))"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test func installScriptParses() throws {
        let script = LidScripts.installScript(rule: Self.rule, plist: Self.plist)
        #expect(try syntaxErrors(of: script).isEmpty)
    }

    @Test func installScriptFollowsTheSpecSteps() {
        let script = LidScripts.installScript(rule: Self.rule, plist: Self.plist)
        let steps = [
            "set -e",
            "/usr/sbin/visudo -cf \"$rule_tmp\"",
            "/bin/mkdir -p -m 0755 /private/etc/sudoers.d",
            "/usr/bin/install -m 0440 -o root -g wheel \"$rule_tmp\" /etc/sudoers.d/macbull",
            "/usr/sbin/visudo -c",
            "/usr/bin/plutil -lint \"$plist_tmp\"",
            "/usr/bin/install -m 0644 -o root -g wheel \"$plist_tmp\" /Library/LaunchDaemons/app.macbull.boot-reset.plist",
        ]
        var searchFrom = script.startIndex
        for step in steps {
            guard let range = script.range(of: step, range: searchFrom..<script.endIndex) else {
                Issue.record("Missing or out of order: \(step)")
                return
            }
            searchFrom = range.upperBound
        }
        #expect(script.contains("trap '/bin/rm -f \"$rule_tmp\" \"$plist_tmp\"' EXIT"))
    }

    @Test func installScriptDoesNotBootstrapTheDaemon() {
        let script = LidScripts.installScript(rule: Self.rule, plist: Self.plist)
        #expect(!script.contains("bootstrap"))
        #expect(!script.contains("launchctl"))
    }

    @Test func embeddedPayloadsDecodeToTheOriginalContent() throws {
        let script = LidScripts.installScript(rule: Self.rule, plist: Self.plist)
        let pattern = try Regex("printf '%s' '([A-Za-z0-9+/=]+)'")
        let payloads = script.matches(of: pattern).compactMap { $0.output[1].substring.map(String.init) }
        #expect(payloads.count == 2)
        let decoded = payloads.compactMap { Data(base64Encoded: $0) }.map { String(decoding: $0, as: UTF8.self) }
        #expect(decoded.first == Self.rule + "\n")
        #expect(decoded.last == Self.plist)
    }

    @Test func installCommandKeepsTheScriptInOneQuotedArgument() throws {
        let command = LidScripts.installCommand(rule: Self.rule, plist: Self.plist)
        #expect(command.hasPrefix("/bin/sh -c '"))
        #expect(command.hasSuffix(" macbull-setup"))
        let script = LidScripts.installScript(rule: Self.rule, plist: Self.plist)
        #expect(try shellRoundTrip(script) == script)
    }

    @Test func uninstallScriptParsesAndOnlyUndoesWhatWeChanged() throws {
        let script = LidScripts.uninstallScript
        #expect(try syntaxErrors(of: script).isEmpty)
        #expect(script.contains("if [ -e \"$1\" ]; then /usr/bin/pmset -a disablesleep 0; fi"))
        #expect(script.contains("if [ -e \"$2\" ]; then /usr/bin/pmset -b lowpowermode 0; fi"))
        #expect(script.contains("/bin/launchctl bootout system/app.macbull.boot-reset 2>/dev/null || true"))
        #expect(script.contains("/bin/rm -f /etc/sudoers.d/macbull /Library/LaunchDaemons/app.macbull.boot-reset.plist"))
    }

    @Test func uninstallCommandPassesFlagPathsAsQuotedParameters() {
        let command = LidScripts.uninstallCommand(sleepFlag: "/a b/it's", lowPowerFlag: "/c")
        #expect(command.hasSuffix("'macbull-remove' '/a b/it'\\''s' '/c'"))
    }

    @Test func shellQuoteSurvivesAwkwardText() throws {
        for text in ["plain", "with space", "it's", "a\"b", "$HOME `id` $(id)", "line\nbreak", "a;b|c&d", "*", ""] {
            #expect(try shellRoundTrip(text) == text)
        }
    }

    @Test func appleScriptLiteralEscapes() {
        #expect(AppleScriptPrivilegedRunner.literal("a\"b") == "\"a\\\"b\"")
        #expect(AppleScriptPrivilegedRunner.literal("a\\b") == "\"a\\\\b\"")
        #expect(AppleScriptPrivilegedRunner.literal("a\nb\tc") == "\"a\\nb\\tc\"")
    }

    @Test func appleScriptSourceNamesPromptAndPrivileges() {
        let source = AppleScriptPrivilegedRunner.source(command: "/bin/true", prompt: "Needs \"you\"")
        #expect(source == "do shell script \"/bin/true\" with prompt \"Needs \\\"you\\\"\" with administrator privileges")
    }

    @Test func watchdogScriptParsesAndFollowsTheSpec() throws {
        let script = LidWatchdog.script
        #expect(try syntaxErrors(of: script).isEmpty)
        #expect(script.contains("while kill -0 \"$1\" 2>/dev/null; do /bin/sleep 2; done"))
        #expect(script.contains("/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 && /bin/rm -f \"$2\""))
        #expect(script.contains("/usr/bin/sudo -n /usr/bin/pmset -b lowpowermode 0 && /bin/rm -f \"$3\""))
        #expect(script.contains("/usr/sbin/ioreg -r -k AppleClamshellState -d 1"))
        #expect(script.contains("/usr/bin/pmset sleepnow"))
    }
}
