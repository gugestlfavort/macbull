import Foundation

extension CustomAgentNames {
    /// One line under the field when the typed text is refused.
    static func hint(for rejection: Rejection) -> String? {
        switch rejection {
        case .empty: nil
        case .interpreter: "That is a runtime that runs many things. Type the script name instead."
        case .shell: "That is a shell, not an agent. Type the script name instead."
        case .knownAgent: "MacBull already watches that one."
        }
    }
}
