import Foundation

@MainActor
protocol LidWatchdogRunning: AnyObject {
    /// Start the watchdog unless it already runs.
    func start()
    func stop()
}

/// One small shell process that outlives the app. It polls the app's pid every 2 seconds and,
/// once the app is gone, undoes what MacBull changed.
@MainActor
final class LidWatchdog: LidWatchdogRunning {
    /// `$1` app pid, `$2` sleep flag, `$3` low power flag, `$4` in-bag flag.
    nonisolated static let script = """
    trap '' HUP
    while kill -0 "$1" 2>/dev/null; do /bin/sleep 2; done
    if [ -e "$2" ]; then \(PmsetCommand.holdOff.sudoText) && /bin/rm -f "$2"; fi
    if [ -e "$3" ]; then \(PmsetCommand.lowPowerOff.sudoText) && /bin/rm -f "$3"; fi
    if [ -e "$4" ]; then
        /bin/rm -f "$4"
        if /usr/sbin/ioreg -r -k AppleClamshellState -d 1 | /usr/bin/grep -q '"AppleClamshellState" = Yes'; then
            /usr/bin/pmset sleepnow
        fi
    fi
    exit 0
    """

    private let flags: LidFlags
    private let appPid: Int32
    private var process: Process?

    init(flags: LidFlags, appPid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.flags = flags
        self.appPid = appPid
    }

    func start() {
        if process?.isRunning == true { return }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", Self.script, "macbull-watchdog", String(appPid)] + flags.orderedPaths
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do {
            try child.run()
            process = child
            Log.lid.info("Watchdog started")
        } catch {
            Log.lid.error("Watchdog could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        guard let process else { return }
        if process.isRunning { process.terminate() }
        self.process = nil
        Log.lid.info("Watchdog stopped")
    }
}
