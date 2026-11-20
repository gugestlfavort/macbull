import Foundation

/// Carries a main-actor closure through the `void *` context of a C callback.
final class CallbackBox: @unchecked Sendable {
    private let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    /// Call from a C callback that is delivered on the main thread.
    func fire() {
        MainActor.assumeIsolated { handler() }
    }

    func retainedPointer() -> UnsafeMutableRawPointer {
        Unmanaged.passRetained(self).toOpaque()
    }

    static func box(from pointer: UnsafeMutableRawPointer?) -> CallbackBox? {
        guard let pointer else { return nil }
        return Unmanaged<CallbackBox>.fromOpaque(pointer).takeUnretainedValue()
    }

    static func release(_ pointer: UnsafeMutableRawPointer?) {
        guard let pointer else { return }
        Unmanaged<CallbackBox>.fromOpaque(pointer).release()
    }
}
