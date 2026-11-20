import AppKit
import SwiftUI

/// The single Settings window: a toolbar tab strip over one grouped form at a time.
@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate, NSWindowDelegate {
    let window: NSWindow
    private let env: AppEnvironment
    private let hasLid: Bool
    private let agentNames: [String]
    private let icon: NSImage
    private let version: String
    private let toolbar: NSToolbar
    private(set) var tab: SettingsTab = .general

    init(env: AppEnvironment, hasLid: Bool, agentNames: [String], icon: NSImage, version: String) {
        self.env = env
        self.hasLid = hasLid
        self.agentNames = agentNames
        self.icon = icon
        self.version = version
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: settingsContentWidth, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        toolbar = NSToolbar(identifier: "MacBullSettingsTabs")
        super.init()
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        window.delegate = self
        select(.general)
        window.center()
    }

    /// Opens the window on a tab and brings the app forward.
    func show(_ tab: SettingsTab) {
        let wasVisible = window.isVisible
        select(tab)
        if !wasVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func select(_ newTab: SettingsTab) {
        tab = newTab
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(newTab.rawValue)
        window.title = newTab.title
        let content = SettingsTabContent(
            tab: newTab, env: env, hasLid: hasLid, agentNames: agentNames, icon: icon, version: version
        )
        // The window follows the content's natural height; the hosting controller must not fight it.
        let wanted = NSHostingView(rootView: content).fittingSize.height
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = []
        let top = window.frame.maxY
        window.contentViewController = controller
        window.setContentSize(NSSize(width: settingsContentWidth, height: min(wanted, maxContentHeight())))
        keepTopEdge(top)
    }

    /// Tall tabs stop at the screen's edge and scroll.
    private func maxContentHeight() -> CGFloat {
        guard let screen = window.screen ?? NSScreen.main else { return 700 }
        let chrome = window.frame.height - window.contentLayoutRect.height
        return screen.visibleFrame.height * 0.9 - chrome
    }

    /// The window grows and shrinks downward, like the system's own Settings.
    private func keepTopEdge(_ top: CGFloat) {
        var frame = window.frame
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true)
    }

    // MARK: Toolbar

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(tabClicked(_:))
        return item
    }

    @objc private func tabClicked(_ sender: NSToolbarItem) {
        guard let clicked = SettingsTab(rawValue: sender.itemIdentifier.rawValue), clicked != tab else { return }
        select(clicked)
    }
}
