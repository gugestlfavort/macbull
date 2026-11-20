import Foundation
import Observation

/// Runs the one-time lid permission change (install or remove) and keeps what the UI shows about it.
@MainActor
@Observable
final class LidSetupRunner {
    private(set) var isWorking = false
    /// Shown in orange. Cancelling the password dialog never sets it.
    private(set) var errorText: String?

    /// The spinner needs a moment to appear before the password dialog takes over.
    private let spinnerLead: Duration

    init(spinnerLead: Duration = .milliseconds(50)) {
        self.spinnerLead = spinnerLead
    }

    @discardableResult
    func run(_ operation: @MainActor () async -> LidSetupResult) async -> LidSetupResult {
        guard !isWorking else { return .cancelled }
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await Task.sleep(for: spinnerLead)
        } catch {
            return .cancelled
        }
        let result = await operation()
        if case .failed(let message) = result {
            errorText = message
        }
        return result
    }
}
