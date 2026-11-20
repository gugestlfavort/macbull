import AppKit
import SwiftUI

/// Where the status item sits, in screen coordinates, so the panel can hang under it.
struct PanelAnchor {
    var frame: NSRect
    var screen: NSScreen?
}

/// Where the panel goes: centred under the item, kept inside the screen's visible area, top edge below the item.
enum PanelPlacement {
    static let width: CGFloat = PanelMetrics.width
    /// Distance kept from the screen's visible edges.
    static let screenMargin: CGFloat = 8
    /// Gap between the status item and the panel's top edge.
    static let gapBelowItem: CGFloat = 6

    static func origin(anchor: NSRect, size: CGSize, visible: NSRect) -> NSPoint {
        let minX = visible.minX + screenMargin
        let maxX = max(visible.maxX - screenMargin - size.width, minX)
        let x = min(max(anchor.midX - size.width / 2, minX), maxX)
        return NSPoint(x: x, y: anchor.minY - gapBelowItem - size.height)
    }

    /// The tallest the panel may be while its top edge stays put.
    static func maxHeight(top: CGFloat, visible: NSRect) -> CGFloat {
        max(top - (visible.minY + screenMargin), 120)
    }
}

/// The borderless panel. It takes keyboard focus (Esc) without activating the app.
private final class PanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The panel's rounded outline.
enum PanelShape {
    /// A stretchable rounded-rectangle mask for NSVisualEffectView.
    static func mask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// The panel's background. Its subviews (the content and the edge) always fill it exactly.
private final class PanelMaterialView: NSVisualEffectView {
    override func layout() {
        super.layout()
        for view in subviews where view.frame != bounds {
            view.frame = bounds
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }
}

/// The thin light edge drawn over the material. It never takes clicks.
private final class PanelBorderView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = Theme.Radius.panel - 0.5
        let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        path.lineWidth = 1
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.stroke()
    }
}

/// Owns the panel window while it is open. The content is created on open and destroyed on close, so
/// nothing animates in the background.
@MainActor
final class PanelController {
    private let environment: AppEnvironment
    private let anchor: @MainActor () -> PanelAnchor?
    private let onClose: @MainActor () -> Void

    private var panel: PanelWindow?
    private var screen: NSScreen?
    /// The panel's top edge, which stays put when the content grows or shrinks.
    private var topEdge: CGFloat = 0
    private var anchorFrame: NSRect = .zero
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    /// The latest content height not yet applied to the window.
    private var pendingHeight: CGFloat?

    var isShown: Bool { panel != nil }

    init(environment: AppEnvironment, anchor: @escaping @MainActor () -> PanelAnchor?, onClose: @escaping @MainActor () -> Void) {
        self.environment = environment
        self.anchor = anchor
        self.onClose = onClose
    }

    // MARK: - Open

    func show() {
        guard panel == nil, let anchor = anchor() else { return }
        anchorFrame = anchor.frame
        screen = anchor.screen ?? NSScreen.main

        let root = PanelView(env: environment, close: { [weak self] in self?.close() },
                             onHeightChange: { [weak self] height in self?.contentHeightChanged(height) })
        let hosting = NSHostingView(rootView: root)

        let material = PanelMaterialView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        // A mask image, not a layer corner radius: the window server then cuts the material and the window
        // shadow to the same rounded shape, so no square corners or ghost edges show around the panel.
        material.maskImage = PanelShape.mask(radius: Theme.Radius.panel)
        material.addSubview(hosting)
        material.addSubview(PanelBorderView())

        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Measure at the panel's width before anything is on screen, so the first frame is the final one.
        hosting.frame = NSRect(x: 0, y: 0, width: PanelPlacement.width, height: 1)
        let size = fittingSize(of: hosting, visible: visible, top: anchor.frame.minY - PanelPlacement.gapBelowItem)
        let origin = PanelPlacement.origin(anchor: anchor.frame, size: size, visible: visible)
        topEdge = origin.y + size.height
        let frame = NSRect(origin: origin, size: size)

        let window = PanelWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = material
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.setFrame(frame, display: false)
        material.layoutSubtreeIfNeeded()
        panel = window

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.alphaValue = reduceMotion ? 1 : 0
        window.makeKeyAndOrderFront(nil)
        window.invalidateShadow()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                window.animator().alphaValue = 1
            }
        }
        installDismissals()
    }

    // MARK: - Close

    func close() {
        guard let window = panel else { return }
        panel = nil
        removeDismissals()
        environment.feedback.setFizz(nil)
        window.orderOut(nil)
        // Destroy the content after the current event, since a button in it may have asked to close.
        Task { @MainActor in
            window.contentView = NSView(frame: .zero)
        }
        onClose()
    }

    // MARK: - Size

    private func fittingSize(of hosting: NSView, visible: NSRect, top: CGFloat) -> CGSize {
        hosting.layoutSubtreeIfNeeded()
        let height = min(hosting.fittingSize.height, PanelPlacement.maxHeight(top: top, visible: visible))
        return CGSize(width: PanelPlacement.width, height: height)
    }

    /// SwiftUI reports a new content height. The window follows on the next turn of the main loop, outside
    /// SwiftUI's update and any animation running in it; the content is pinned to the top meanwhile.
    private func contentHeightChanged(_ contentHeight: CGFloat) {
        let pending = pendingHeight != nil
        pendingHeight = contentHeight
        guard !pending else { return }
        // A run loop block, not a main-queue one: it also runs while the run loop is driven from inside
        // a main-queue job (tests).
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated { self?.applyPendingHeight() }
        }
    }

    private func applyPendingHeight() {
        guard let contentHeight = pendingHeight else { return }
        pendingHeight = nil
        guard let window = panel else { return }
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let height = min(contentHeight, PanelPlacement.maxHeight(top: topEdge, visible: visible))
        guard abs(height - window.frame.height) > 0.5 else { return }
        let frame = NSRect(x: window.frame.minX, y: topEdge - height, width: PanelPlacement.width, height: height)
        // A short slide instead of a snap; the content is pinned to the top, so only the bottom edge moves.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.setFrame(frame, display: true)
            window.invalidateShadow()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.resizeSeconds
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
        } completionHandler: {
            MainActor.assumeIsolated { window.invalidateShadow() }
        }
    }

    private static let resizeSeconds = 0.16

    // MARK: - Dismissal

    private func installDismissals() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeUnlessOnStatusItem() }
        }
        // Clicks in our own other windows, and Esc
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            // AppKit calls monitors on the main thread, one event at a time. Only plain values cross over.
            // keyCode exists only on key events: reading it from a mouse event throws, and AppKit then drops
            // the click before the panel sees it.
            let isKeyDown = event.type == .keyDown
            let keyCode = isKeyDown ? event.keyCode : 0
            let windowNumber = event.windowNumber
            let swallow = MainActor.assumeIsolated {
                self?.handleLocal(isKeyDown: isKeyDown, keyCode: keyCode, windowNumber: windowNumber) ?? false
            }
            return swallow ? nil : event
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func removeDismissals() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        globalMonitor = nil
        localMonitor = nil
        spaceObserver = nil
    }

    /// The click-away monitors leave the status item alone, so its own click can toggle the panel.
    private func closeUnlessOnStatusItem() {
        if anchorFrame.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation) { return }
        close()
    }

    /// Returns true when the event is used up (Esc closed the panel).
    private func handleLocal(isKeyDown: Bool, keyCode: UInt16, windowNumber: Int) -> Bool {
        guard let window = panel else { return false }
        let inPanel = windowNumber == window.windowNumber
        if isKeyDown {
            // Esc, only while the panel itself has the keyboard
            guard keyCode == Self.escapeKeyCode, inPanel else { return false }
            close()
            return true
        }
        if !inPanel { closeUnlessOnStatusItem() }
        return false
    }

    private static let escapeKeyCode: UInt16 = 53
}
