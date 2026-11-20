import Foundation
import ServiceManagement

/// Open at login, through the macOS login-item service for the main app.
@MainActor
protocol LoginItemControlling: AnyObject {
    func status() -> LoginItemStatus
    /// Register or unregister, then report the resulting status.
    func setEnabled(_ enabled: Bool) -> LoginItemStatus
}

@MainActor
final class SMAppLoginItem: LoginItemControlling {
    func status() -> LoginItemStatus {
        Self.map(SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) -> LoginItemStatus {
        let current = status()
        if enabled, current == .enabled || current == .needsApproval { return current }
        if !enabled, current == .disabled { return current }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.engine.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
        return status()
    }

    static func map(_ status: SMAppService.Status) -> LoginItemStatus {
        switch status {
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }
}
