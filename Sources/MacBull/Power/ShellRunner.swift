import Foundation

struct ShellResult: Equatable, Sendable {
    /// Exit status; -1 when the process could not be launched.
    var status: Int32
    /// Standard output as text. Standard error is discarded.
    var output: String

    var succeeded: Bool { status == 0 }
}

/// Runs a program by absolute path with an argument list. No shell, so no interpolation.
protocol ShellRunning: Sendable {
    /// Runs off the calling actor and returns when the program has finished.
    func run(_ executable: String, _ arguments: [String]) async -> ShellResult
    /// Blocks. Only for the quit path, where the app is about to exit.
    func runBlocking(_ executable: String, _ arguments: [String]) -> ShellResult
}

struct ProcessShellRunner: ShellRunning {
    func run(_ executable: String, _ arguments: [String]) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(executable, arguments))
            }
        }
    }

    func runBlocking(_ executable: String, _ arguments: [String]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            Log.lid.error("Cannot launch \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return ShellResult(status: -1, output: "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

/// Runs every command one after another on one queue, whatever the caller: the async path and the
/// blocking quit path share it. Without this a quit could send `disablesleep 0` while a slow
/// `disablesleep 1` was still running, and the enable would land last with no flag left to undo it.
final class SerialShellRunner: ShellRunning, @unchecked Sendable {
    private let inner: any ShellRunning
    private let queue = DispatchQueue(label: "app.macbull.shell.serial", qos: .userInitiated)

    init(_ inner: any ShellRunning) {
        self.inner = inner
    }

    func run(_ executable: String, _ arguments: [String]) async -> ShellResult {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.inner.runBlocking(executable, arguments))
            }
        }
    }

    func runBlocking(_ executable: String, _ arguments: [String]) -> ShellResult {
        queue.sync { inner.runBlocking(executable, arguments) }
    }
}
