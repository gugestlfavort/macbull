import Foundation
import IOKit.ps

struct PowerReading: Equatable, Sendable {
    /// The internal battery's charge, nil on a Mac without one.
    var percent: Int?
    var onBattery: Bool
}

/// One power-source lookup is shared by everything that asks within a second (the engine asks for the percent
/// and the source on every evaluation). A change notification clears it, so a plug-in is seen at once.
struct PowerReadingCache {
    static let lifetime: TimeInterval = 1

    private var stored: (reading: PowerReading, at: Date)?

    mutating func reading(at now: Date, read: () -> PowerReading) -> PowerReading {
        if let stored, now.timeIntervalSince(stored.at) < Self.lifetime, now >= stored.at { return stored.reading }
        let fresh = read()
        stored = (fresh, now)
        return fresh
    }

    mutating func invalidate() {
        stored = nil
    }
}

/// Battery and power source through IOPowerSources.
enum PowerSourceReader {
    /// Current capacity times 100 over maximum capacity, integer division.
    static func percent(current: Int, maximum: Int) -> Int? {
        guard maximum > 0, current >= 0 else { return nil }
        return current * 100 / maximum
    }

    static func read() -> PowerReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerReading(percent: nil, onBattery: false)
        }
        return PowerReading(percent: batteryPercent(info), onBattery: isOnBattery(info))
    }

    private static func isOnBattery(_ info: CFTypeRef) -> Bool {
        guard let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (source as String) == kIOPSBatteryPowerValue
    }

    private static func batteryPercent(_ info: CFTypeRef) -> Int? {
        guard let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int
            else { continue }
            return percent(current: current, maximum: maximum)
        }
        return nil
    }
}

/// A run loop source that fires when the power source or charge changes.
@MainActor
final class PowerSourceWatcher {
    private var source: CFRunLoopSource?
    private var context: UnsafeMutableRawPointer?

    func start(onChange: @escaping @MainActor () -> Void) {
        guard source == nil else { return }
        let box = CallbackBox(onChange).retainedPointer()
        guard let created = IOPSNotificationCreateRunLoopSource(
            { refcon in CallbackBox.box(from: refcon)?.fire() }, box
        )?.takeRetainedValue() else {
            CallbackBox.release(box)
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        source = created
        context = box
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        CallbackBox.release(context)
        context = nil
    }
}
