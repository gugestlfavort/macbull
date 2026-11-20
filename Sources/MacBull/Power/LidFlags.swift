import Foundation

/// Empty files whose presence records what MacBull changed, so a crash can be undone.
struct LidFlags: Sendable {
    enum Flag: String, CaseIterable, Sendable {
        /// disablesleep 1 is on because of MacBull.
        case sleepDisabled = "sleep-disabled"
        /// MacBull forced Low Power Mode on (battery profile).
        case lowPowerForced = "low-power-forced"
        /// The Mac is held awake with the lid shut and no external display.
        case heldInBag = "held-in-bag"
    }

    let directory: URL

    /// `~/Library/Application Support/MacBull/`.
    static var standard: LidFlags {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LidFlags(directory: support.appendingPathComponent("MacBull", isDirectory: true))
    }

    func path(_ flag: Flag) -> String {
        directory.appendingPathComponent(flag.rawValue).path
    }

    /// The three absolute paths in the order the boot-reset daemon and watchdog expect:
    /// sleep, low power, in bag.
    var orderedPaths: [String] {
        [path(.sleepDisabled), path(.lowPowerForced), path(.heldInBag)]
    }

    func exists(_ flag: Flag) -> Bool {
        FileManager.default.fileExists(atPath: path(flag))
    }

    /// Creates the folder on demand. Returns false when the flag could not be written.
    func set(_ flag: Flag) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Log.lid.error("Cannot create flag folder: \(error.localizedDescription, privacy: .public)")
            return false
        }
        if exists(flag) { return true }
        return FileManager.default.createFile(atPath: path(flag), contents: Data())
    }

    func clear(_ flag: Flag) {
        guard exists(flag) else { return }
        do {
            try FileManager.default.removeItem(atPath: path(flag))
        } catch {
            Log.lid.error("Cannot remove flag \(flag.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearAll() {
        for flag in Flag.allCases { clear(flag) }
    }
}
