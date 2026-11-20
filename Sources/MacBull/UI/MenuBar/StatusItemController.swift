import AppKit
import Observation

/// What a click on the menu bar can does.
enum StatusClick: Equatable {
    case togglePanel
    /// Switch awake on or off with the default duration.
    case quickToggle

    /// Option: quick toggle with either button. Right click and Control + click: the panel. A plain left click:
    /// the panel, or a quick toggle when "clicking the can switches it" is on.
    static func action(isRightButton: Bool, modifiers: NSEvent.ModifierFlags, clickToggles: Bool) -> StatusClick {
        if modifiers.contains(.option) { return .quickToggle }
        if isRightButton || modifiers.contains(.control) { return .togglePanel }
        return clickToggles ? .quickToggle : .togglePanel
    }
}

/// The menu bar item: the can icon with its transitions and Your Turn badge, the tooltip, and the panel.
@MainActor
final class StatusItemController: PanelPresenting {
    private let environment: AppEnvironment
    private let statusLine: @MainActor () -> String
    private let statusItem: NSStatusItem
    private var panelController: PanelController?

    // Icon state
    private var shownState: MenuBarIcon.State?
    private var currentLook = MenuBarIcon.look(for: .off)
    private var shownBadge: MenuBarIcon.Badge?
    private var transitionTimer: Timer?
    private var shownLine = ""

    init(environment: AppEnvironment, statusLine: @escaping @MainActor () -> String) {
        self.environment = environment
        self.statusLine = statusLine
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.image(.off)
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        panelController = PanelController(
            environment: environment,
            anchor: { [weak self] in self?.anchor() },
            onClose: { [weak self] in self?.statusItem.button?.highlight(false) })
        refresh()
    }

    // MARK: - PanelPresenting

    var isPanelShown: Bool { panelController?.isShown ?? false }

    func showPanel() {
        guard let panelController, !panelController.isShown else { return }
        panelController.show()
        if panelController.isShown {
            statusItem.button?.highlight(true)
        }
    }

    func closePanel() {
        panelController?.close()
    }

    // MARK: - Clicks

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let action = StatusClick.action(
            isRightButton: event?.type == .rightMouseUp,
            modifiers: event?.modifierFlags ?? [],
            clickToggles: environment.settings.clickToggles)
        switch action {
        case .togglePanel:
            if isPanelShown { closePanel() } else { showPanel() }
        case .quickToggle:
            if isPanelShown { closePanel() }
            environment.actions.toggle()
        }
    }

    private func anchor() -> PanelAnchor? {
        guard let window = statusItem.button?.window else { return nil }
        return PanelAnchor(frame: window.frame, screen: window.screen)
    }

    // MARK: - Icon and tooltip

    /// What the icon and tooltip show, read inside the observation so a change to any of it comes back here.
    private struct Snapshot {
        var base: MenuIconBase
        var waiting: Int
        var showCount: Bool
        var line: String
    }

    /// Reads the state, shows it, and asks to be called again at the next change.
    private func refresh() {
        let snapshot = withObservationTracking {
            Snapshot(base: environment.state.menuIconBase, waiting: environment.state.waitingCount,
                     showCount: environment.settings.showWaitingCount, line: statusLine())
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        apply(snapshot)
    }

    private func apply(_ snapshot: Snapshot) {
        setLine(snapshot.line)
        let state = MenuBarIcon.State(snapshot.base)
        let badge = MenuBarIcon.badge(base: snapshot.base, waiting: snapshot.waiting, showCount: snapshot.showCount)
        let badgeChanged = badge != shownBadge
        shownBadge = badge
        if state != shownState {
            transition(to: state)
        } else if badgeChanged, transitionTimer == nil {
            // The badge only redraws; it never starts a transition
            draw()
        }
    }

    private func setLine(_ line: String) {
        guard line != shownLine, let button = statusItem.button else { return }
        shownLine = line
        button.toolTip = line
        button.setAccessibilityLabel("MacBull, \(line)")
    }

    /// The engine calls this when the status line text changes, a ticking countdown included, so the tooltip
    /// needs no timer of its own.
    func statusLineChanged(_ line: String) {
        guard statusItem.isVisible else { return }
        setLine(line)
    }

    /// The tooltip as shown now.
    var toolTip: String? { statusItem.button?.toolTip }

    // MARK: - Transition

    private func transition(to state: MenuBarIcon.State) {
        transitionTimer?.invalidate()
        transitionTimer = nil
        let isFirst = shownState == nil
        shownState = state
        let target = MenuBarIcon.look(for: state)
        guard !isFirst, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            currentLook = target
            draw()
            return
        }
        // From wherever the icon is now, which may be mid-transition
        let frames = MenuBarIcon.frames(from: currentLook, to: target)
        currentLook = frames[0]
        draw()
        guard frames.count > 1 else { return }
        var next = 1
        let interval = MenuBarIcon.Metrics.transitionDuration / Double(frames.count - 1)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentLook = frames[next]
                self.draw()
                next += 1
                if next >= frames.count {
                    self.transitionTimer?.invalidate()
                    self.transitionTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        transitionTimer = timer
    }

    private func draw() {
        statusItem.button?.image = MenuBarIcon.image(currentLook, badge: shownBadge)
    }
}
