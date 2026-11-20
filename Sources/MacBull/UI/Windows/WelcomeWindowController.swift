import AppKit
import SwiftUI

/// The welcome window. Closing it by any means counts as done.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let env: AppEnvironment
    private let hasLid: Bool
    private let model: WelcomeModel

    init(env: AppEnvironment, hasLid: Bool, icon: NSImage, start: WelcomeStep) {
        self.env = env
        self.hasLid = hasLid
        model = WelcomeModel(start: start, hasLid: hasLid)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: welcomeWindowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.contentView = NSHostingView(rootView: WelcomeView(
            env: env, hasLid: hasLid, icon: icon, model: model,
            onFinish: { [weak self] openPanel in self?.finish(openPanel: openPanel) }
        ))
        window.setContentSize(welcomeWindowSize)
        window.center()
    }

    /// Shows the window at a step and brings the app forward.
    func show(_ step: WelcomeStep) {
        model.restart(at: step)
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish(openPanel: Bool) {
        env.settings.welcomeDone = true
        window.close()
        if openPanel { env.actions.showPanel() }
    }

    func windowWillClose(_ notification: Notification) {
        env.settings.welcomeDone = true
    }
}
