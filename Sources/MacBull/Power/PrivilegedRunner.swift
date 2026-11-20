import Foundation

enum PrivilegedOutcome: Equatable, Sendable {
    case success
    /// The user dismissed the password dialog (error -128).
    case cancelled
    case failed(String)
}

/// Runs one shell command line as root behind the standard macOS administrator password dialog.
protocol PrivilegedRunning: Sendable {
    func run(command: String, prompt: String) async -> PrivilegedOutcome
}

struct AppleScriptPrivilegedRunner: PrivilegedRunning {
    /// AppleScript reports a dismissed authorisation dialog as -128 ("User canceled").
    static let cancelledErrorNumber = -128

    func run(command: String, prompt: String) async -> PrivilegedOutcome {
        let source = Self.source(command: command, prompt: prompt)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.execute(source))
            }
        }
    }

    static func source(command: String, prompt: String) -> String {
        "do shell script \(literal(command)) with prompt \(literal(prompt)) with administrator privileges"
    }

    /// An AppleScript string literal.
    static func literal(_ text: String) -> String {
        var escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        return "\"" + escaped + "\""
    }

    private static func execute(_ source: String) -> PrivilegedOutcome {
        guard let script = NSAppleScript(source: source) else {
            return .failed("The administrator request could not be built.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return .success }
        let number = errorInfo[NSAppleScript.errorNumber] as? Int
        if number == cancelledErrorNumber { return .cancelled }
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error"
        Log.lid.error("Administrator script failed (\(number ?? 0)): \(message, privacy: .public)")
        return .failed(message)
    }
}
