import Foundation

/// Reads the output of `sudo -n -l` and answers one question: are our four pmset commands
/// allowed without a password? Rules: an entry starts with a parenthesised
/// run-as list, indented lines after it continue it, only entries that run as `root` or `ALL`
/// count, tags apply to themselves and later commands in the entry, and the last matching
/// rule wins (a company-wide "(ALL) ALL" listed after ours takes the permission away).
enum SudoListing {
    static func allowsWithoutPassword(
        _ listing: String,
        commands: [PmsetCommand] = PmsetCommand.allCases
    ) -> Bool {
        let rules = entries(in: listing).filter(\.runsAsRoot).flatMap(\.rules)
        return commands.allSatisfy { isAllowed($0.text, by: rules) }
    }

    /// One sudoers command grant with the tag state that was in force when it was listed.
    struct Rule: Equatable {
        var command: String
        var passwordFree: Bool
        var negated: Bool
    }

    struct Entry: Equatable {
        var runAs: String
        var body: String

        /// The user part of "(user : group)" names root or ALL.
        var runsAsRoot: Bool {
            let users = runAs.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            return users.split(separator: ",").contains { name in
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                return trimmed == "root" || trimmed == "ALL"
            }
        }

        var rules: [Rule] { SudoListing.rules(inBody: body) }
    }

    static func entries(in listing: String) -> [Entry] {
        var result: [Entry] = []
        var current: Entry?
        for rawLine in listing.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let start = entryStart(trimmed) {
                if let current { result.append(current) }
                current = start
            } else if line.first?.isWhitespace == true, current != nil {
                current?.body += " " + trimmed
            } else {
                if let current { result.append(current) }
                current = nil
            }
        }
        if let current { result.append(current) }
        return result
    }

    static func rules(inBody body: String) -> [Rule] {
        var passwordFree = false
        var rules: [Rule] = []
        for item in splitOnUnescapedCommas(body) {
            var rest = item.trimmingCharacters(in: .whitespaces)
            while let (tag, remainder) = leadingTag(of: rest) {
                if tag == "NOPASSWD" { passwordFree = true }
                if tag == "PASSWD" { passwordFree = false }
                rest = remainder
            }
            let negated = rest.hasPrefix("!")
            let command = normalise(negated ? String(rest.dropFirst()) : rest)
            if command.isEmpty { continue }
            rules.append(Rule(command: command, passwordFree: passwordFree, negated: negated))
        }
        return rules
    }

    // MARK: - Internals

    private static let knownTags: Set<String> = [
        "NOPASSWD", "PASSWD", "NOEXEC", "EXEC", "SETENV", "NOSETENV", "LOG_INPUT", "NOLOG_INPUT",
        "LOG_OUTPUT", "NOLOG_OUTPUT", "MAIL", "NOMAIL", "FOLLOW", "NOFOLLOW", "INTERCEPT", "NOINTERCEPT",
    ]

    private static func entryStart(_ trimmed: String) -> Entry? {
        guard trimmed.hasPrefix("("), let close = trimmed.firstIndex(of: ")") else { return nil }
        let runAs = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        let body = String(trimmed[trimmed.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        return Entry(runAs: runAs, body: body)
    }

    private static func leadingTag(of text: String) -> (String, String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let name = text[text.startIndex..<colon].trimmingCharacters(in: .whitespaces)
        guard knownTags.contains(name) else { return nil }
        let remainder = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (name, remainder)
    }

    private static func splitOnUnescapedCommas(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaped = false
        for character in text {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                current.append(character)
                escaped = true
            } else if character == "," {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    private static func normalise(_ command: String) -> String {
        command.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Last matching rule wins; a negated rule or one that asks for a password denies.
    private static func isAllowed(_ command: String, by rules: [Rule]) -> Bool {
        guard let last = rules.last(where: { covers($0.command, command) }) else { return false }
        return last.passwordFree && !last.negated
    }

    /// A rule covers a command when it is ALL, the command itself, the bare program (no
    /// arguments listed means any arguments), or a pattern ending in `*` that the command starts with.
    private static func covers(_ rule: String, _ command: String) -> Bool {
        if rule == "ALL" || rule == command || rule == PmsetCommand.pmsetPath { return true }
        guard rule.hasSuffix("*") else { return false }
        return command.hasPrefix(String(rule.dropLast()))
    }
}
