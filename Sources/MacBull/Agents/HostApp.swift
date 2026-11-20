import AppKit

/// Finds the app that hosts a session: the first process above it that is a regular GUI app
/// (Terminal, iTerm, VS Code, Cursor). In tmux or over SSH there is none.
enum HostApp {
    /// Pids walked at most, so a broken parent chain cannot loop.
    static let maxSteps = 64

    /// Walks up from `pid` (included) through parents; returns the first pid for which `isRegularApp` is true.
    static func find(from pid: pid_t, parentOf: (pid_t) -> pid_t?, isRegularApp: (pid_t) -> Bool) -> pid_t? {
        var current = pid
        for _ in 0..<maxSteps {
            if current > 1, isRegularApp(current) { return current }
            guard let parent = parentOf(current), parent > 1, parent != current else { return nil }
            current = parent
        }
        return nil
    }

    @MainActor
    static func bringToFront(sessionPID: pid_t) -> Bool {
        let hostPID = find(
            from: sessionPID,
            parentOf: ProcessScanner.parent(of:),
            isRegularApp: { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular }
        )
        guard let hostPID, let app = NSRunningApplication(processIdentifier: hostPID) else { return false }
        if !app.activate(from: NSRunningApplication.current, options: [.activateAllWindows]) {
            return app.activate(options: [.activateAllWindows])
        }
        return true
    }
}
