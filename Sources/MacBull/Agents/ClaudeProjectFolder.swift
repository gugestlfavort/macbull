import Foundation

/// Where Claude Code keeps the logs of one working directory: `~/.claude/projects/<name>`.
enum ClaudeProjectFolder {
    /// Longer names are cut here and given a dash and a short hash.
    static let maxPlainLength = 200
    private static let dash: UInt16 = 0x2D

    /// The directory in composed Unicode form with every UTF-16 unit that is not an ASCII letter or digit as a dash.
    static func plainName(forDirectory directory: String) -> String {
        let units = directory.precomposedStringWithCanonicalMapping.utf16.map { unit -> UInt16 in
            isASCIILetterOrDigit(unit) ? unit : dash
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// The existing folder name for this directory, or nil when Claude has not made one yet.
    static func resolve(directory: String, existing: Set<String>) -> String? {
        let plain = plainName(forDirectory: directory)
        if existing.contains(plain) { return plain }
        guard plain.utf16.count > maxPlainLength else { return nil }
        let prefix = String(decoding: Array(plain.utf16.prefix(maxPlainLength)), as: UTF16.self) + "-"
        return existing.sorted().first { $0.hasPrefix(prefix) }
    }

    private static func isASCIILetterOrDigit(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: true
        default: false
        }
    }
}
