import Foundation
import IOKit

/// Lid state from the power management registry entry. A Mac without a lid has no such property.
enum Clamshell {
    enum State: Equatable, Sendable {
        case noLid
        case open
        case closed
    }

    static let propertyName = "AppleClamshellState"

    static func read() -> State {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return .noLid }
        defer { IOObjectRelease(service) }
        let property = IORegistryEntryCreateCFProperty(service, propertyName as CFString, kCFAllocatorDefault, 0)
        guard let value = property?.takeRetainedValue() as? NSNumber else { return .noLid }
        return value.boolValue ? .closed : .open
    }
}
