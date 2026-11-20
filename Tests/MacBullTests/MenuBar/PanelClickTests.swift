import AppKit
import Testing
@testable import MacBull

/// Clicks reach the panel's buttons when they go through the whole app event path, monitors included.
@MainActor
struct PanelClickTests {
    private func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func click(_ point: NSPoint, in window: NSWindow) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            // NSApp.sendEvent runs the local event monitors first, as a real click does.
            NSApp.sendEvent(event)
            pump(0.05)
        }
    }

    @Test func aClickOnQuitReachesTheButton() throws {
        _ = NSApplication.shared
        let actions = WindowsFakeActions()
        let env = WindowsTestSupport.makeEnvironment(actions: actions)
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let anchor = NSRect(x: visible.midX, y: visible.maxY + 2, width: 24, height: 22)
        let controller = PanelController(environment: env, anchor: { PanelAnchor(frame: anchor, screen: screen) }, onClose: {})
        controller.show()
        defer { controller.close() }
        pump(0.5)
        let window = try #require(NSApp.windows.first { $0.isVisible && $0.frame.width == PanelMetrics.width })

        // Quit sits at the bottom right of the footer.
        try click(NSPoint(x: window.frame.width - 32, y: 23), in: window)
        pump(0.2)

        #expect(actions.calls.contains("quit"))
    }

    /// The panel fits its content and follows it when the content grows (turning on adds lines).
    @Test func thePanelFollowsTheContentHeight() throws {
        _ = NSApplication.shared
        let env = WindowsTestSupport.makeEnvironment()
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let anchor = NSRect(x: visible.midX, y: visible.maxY + 2, width: 24, height: 22)
        let controller = PanelController(environment: env, anchor: { PanelAnchor(frame: anchor, screen: screen) }, onClose: {})
        controller.show()
        defer { controller.close() }
        pump(0.3)
        let window = try #require(NSApp.windows.first { $0.isVisible && $0.frame.width == PanelMetrics.width })
        let top = window.frame.maxY
        let material = try #require(window.contentView)
        let hosting = try #require(material.subviews.first)
        // Placed under the item on the first frame, and the content fills the panel exactly.
        #expect(abs(top - (anchor.minY - PanelPlacement.gapBelowItem)) < 0.5)
        #expect(hosting.frame == material.bounds)
        #expect(abs(window.frame.height - hosting.fittingSize.height) < 1)
        #expect(window.frame.height < visible.height)

        env.state.lidSetup = .ready
        env.state.lidHeld = true
        env.state.manual = ManualSession(minutes: 60, startedAt: Date(), endsAt: Date().addingTimeInterval(3600))
        pump(0.5)

        #expect(abs(window.frame.height - hosting.fittingSize.height) < 1)
        #expect(abs(window.frame.maxY - top) < 0.5)
        #expect(hosting.frame == material.bounds)
    }

    /// Pouring and turning off switch the lid hold on and off; the panel keeps its height.
    @Test func theLidHoldComingAndGoingKeepsTheHeight() throws {
        _ = NSApplication.shared
        let env = WindowsTestSupport.makeEnvironment()
        env.state.lidSetup = .ready
        env.state.lidHeld = true
        env.state.manual = ManualSession(minutes: 60, startedAt: Date(), endsAt: Date().addingTimeInterval(3600))
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let anchor = NSRect(x: visible.midX, y: visible.maxY + 2, width: 24, height: 22)
        let controller = PanelController(environment: env, anchor: { PanelAnchor(frame: anchor, screen: screen) }, onClose: {})
        controller.show()
        defer { controller.close() }
        pump(0.3)
        let window = try #require(NSApp.windows.first { $0.isVisible && $0.frame.width == PanelMetrics.width })
        let held = window.frame.height

        env.state.lidHeld = false
        pump(0.5)

        #expect(abs(window.frame.height - held) < 0.5)
    }
}
