import Foundation
import IOKit

/// Tells the monitor something happened on the power management root domain (lid, sleep).
/// The monitor compares the lid state itself, so a message that changes nothing is harmless.
@MainActor
final class ClamshellWatcher {
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = IO_OBJECT_NULL
    private var context: UnsafeMutableRawPointer?

    func start(onChange: @escaping @MainActor () -> Void) {
        guard port == nil else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }
        guard let newPort = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(newPort, DispatchQueue.main)
        let box = CallbackBox(onChange).retainedPointer()
        let status = IOServiceAddInterestNotification(
            newPort, service, kIOGeneralInterest,
            { refcon, _, _, _ in CallbackBox.box(from: refcon)?.fire() },
            box, &notifier
        )
        guard status == KERN_SUCCESS else {
            Log.power.error("Lid notification failed: \(status)")
            CallbackBox.release(box)
            IONotificationPortDestroy(newPort)
            return
        }
        port = newPort
        context = box
    }

    func stop() {
        if notifier != IO_OBJECT_NULL { IOObjectRelease(notifier) }
        notifier = IO_OBJECT_NULL
        if let port { IONotificationPortDestroy(port) }
        port = nil
        CallbackBox.release(context)
        context = nil
    }
}
