import AppKit
import SwiftUI
import Testing
@testable import MacBull

// Renders the panel content to PNGs when MACBULL_RENDER_DIR is set, for looking at while developing:
//   MACBULL_RENDER_DIR=docs/renders swift test --filter Render
// ImageRenderer cannot render an NSPanel, so the SwiftUI content is rendered at the panel's 340 pt width
// on a stand-in for the translucent material.

@MainActor
final class RenderActions: AppActions {
    var stats = NutritionStats.empty
    func turnOn(minutes: Int?) {}
    func turnOff() {}
    func toggle() {}
    func sleepNow() {}
    func installLid() async -> LidSetupResult { .success }
    func removeLid() async -> LidSetupResult { .success }
    func bringToFront(sessionID: String) -> Bool { true }
    func showPanel() {}
    func openSettings(_ tab: SettingsTab) {}
    func openWelcome(_ step: WelcomeStep) {}
    func dismissReceipt() {}
    func nutrition(_ range: StatsRange) -> NutritionStats { stats }
    func eraseHistory() {}
    func loginItemStatus() -> LoginItemStatus { .enabled }
    func setLoginItem(_ enabled: Bool) -> LoginItemStatus { .enabled }
    func quit() {}
}

@MainActor
final class RenderFeedback: FeedbackPlaying {
    func play(_ cue: SoundCue) {}
    func setFizz(_ level: Double?) {}
    func detent(strong: Bool) {}
}

@MainActor
struct PanelRenderTests {
    private func makeEnvironment(
        stats: NutritionStats = .empty,
        configure: (AppState, MacBull.Settings) -> Void = { _, _ in }
    ) -> AppEnvironment {
        let suite = "macbull.render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let settings = MacBull.Settings(defaults: defaults)
        let state = AppState()
        let actions = RenderActions()
        actions.stats = stats
        configure(state, settings)
        return AppEnvironment(state: state, settings: settings, actions: actions, feedback: RenderFeedback())
    }

    private func framedPanel(_ environment: AppEnvironment, preview: PanelPreview, dark: Bool,
                             receiptExpanded: Bool) -> some View {
        let surface = dark ? Color(white: 0.17) : Color(white: 0.94)
        let backdrop = dark ? Color(white: 0.05) : Color(red: 0.55, green: 0.62, blue: 0.75)
        let view = PanelView(env: environment, close: {}, preview: preview)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).fill(surface))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .padding(20)
            .background(backdrop)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.receiptStartsExpanded, receiptExpanded)
        return view
    }

    /// ImageRenderer draws a ScrollView empty, so a scrolling panel is drawn from a real hosted view instead.
    private func renderHosted(_ environment: AppEnvironment, receiptExpanded: Bool, to name: String, in folder: URL) throws {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: framedPanel(environment, preview: PanelPreview(), dark: false, receiptExpanded: receiptExpanded))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        for _ in 0..<10 { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent("\(name).png"))
        window.orderOut(nil)
    }

    private func render(_ environment: AppEnvironment, preview: PanelPreview = PanelPreview(), dark: Bool = false,
                        to name: String, in folder: URL) throws {
        let view = framedPanel(environment, preview: preview, dark: dark, receiptExpanded: false)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "\(name) did not render")
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent("\(name).png"))
    }

    // MARK: Sample data

    private static let minute: TimeInterval = 60

    private func sampleReceipt() -> Receipt {
        let now = Date()
        return Receipt(
            id: UUID(), awayFrom: now.addingTimeInterval(-7.2 * 3600), awayTo: now,
            lines: [
                ReceiptLine(agent: "Claude Code", folder: "api", outcome: .finished(at: now.addingTimeInterval(-5 * 3600), afterSeconds: 63 * Self.minute)),
                ReceiptLine(agent: "Codex", folder: "docs-site", outcome: .finished(at: now.addingTimeInterval(-3 * 3600), afterSeconds: 22 * Self.minute)),
                ReceiptLine(agent: "Claude Code", folder: "web", outcome: .waitingForYou(since: now.addingTimeInterval(-90 * Self.minute))),
            ],
            batteryStart: 84, batteryEnd: 61, pluggedIn: false, peakThermal: 1,
            sleptAt: [now.addingTimeInterval(-4 * 3600), now.addingTimeInterval(-2 * 3600)],
            safetyStop: nil, notRunningSince: nil)
    }

    /// The owner's night: 25 turns over 6 folders, one session still waiting. `extraFolders` adds more mid-sized ones.
    private func longNightReceipt(extraFolders: Int = 0) -> Receipt {
        let now = Date()
        func night(_ folder: String, turns: Int, minutes: Double, lastHoursAgo: Double) -> ReceiptLine {
            ReceiptLine(
                agent: "Claude Code", folder: folder,
                outcome: .finished(at: now.addingTimeInterval(-lastHoursAgo * 3600), afterSeconds: 60),
                turns: turns, workSeconds: minutes * Self.minute)
        }
        let extra = (0..<extraFolders).map { night("project-\($0 + 1)", turns: 2, minutes: 10 + Double($0), lastHoursAgo: 3) }
        return Receipt(
            id: UUID(), awayFrom: now.addingTimeInterval(-9 * 3600), awayTo: now,
            lines: extra + [
                night("notes-app", turns: 10, minutes: 112, lastHoursAgo: 1.5),
                night("web", turns: 7, minutes: 41, lastHoursAgo: 2),
                ReceiptLine(agent: "Claude Code", folder: "web", outcome: .waitingForYou(since: now.addingTimeInterval(-2.2 * 3600)), turns: 1, workSeconds: 4 * Self.minute),
                night("MacBull", turns: 2, minutes: 9, lastHoursAgo: 4),
                night("blog", turns: 2, minutes: 5, lastHoursAgo: 5),
                night("dotfiles", turns: 2, minutes: 3, lastHoursAgo: 6),
                night("scratch", turns: 1, minutes: 0.4, lastHoursAgo: 7),
            ],
            batteryStart: 91, batteryEnd: 64, pluggedIn: false, peakThermal: 1,
            sleptAt: [now.addingTimeInterval(-4 * 3600)], safetyStop: nil, notRunningSince: nil)
    }

    private func sampleStats() -> NutritionStats {
        NutritionStats(
            cansOpened: 7, awakeSeconds: 5 * 3600 + 20 * 60, agentSeconds: 9.5 * 3600, longestRunSeconds: 95 * 60,
            sessionsFinished: 14, waitedForYouSeconds: 38 * 60, waitedForYouMedianSeconds: 4 * 60,
            batterySpentAway: 23, safetyStops: 1,
            agentMix: [AgentShare(agent: "Claude Code", share: 0.62), AgentShare(agent: "Codex", share: 0.30), AgentShare(agent: "Aider", share: 0.08)],
            emptiesToday: 14)
    }

    private func configureAgents(_ state: AppState, settings: MacBull.Settings) {
        let now = Date()
        state.agentHold = true
        state.agentHoldSince = now.addingTimeInterval(-12 * Self.minute)
        state.lidSetup = .ready
        state.lidHeld = true
        state.toolPulses = 4
        state.agents = [
            AgentSummary(name: "Claude Code", sessions: 2, isWorking: true, backgroundRuns: 0, isCustom: false, waitingForYou: 0, stalled: 0),
            AgentSummary(name: "Codex", sessions: 1, isWorking: false, backgroundRuns: 0, isCustom: false, waitingForYou: 0, stalled: 0),
        ]
        state.sessions = [
            AgentSession(id: "a", agent: "Claude Code", folder: "api", activity: .working, since: now, lastSignOfLife: now, isExact: true, pid: 10),
            AgentSession(id: "b", agent: "Claude Code", folder: "web", activity: .working, since: now, lastSignOfLife: now, isExact: true, pid: 11),
            AgentSession(id: "c", agent: "Codex", folder: nil, activity: .idle, since: now, lastSignOfLife: now, isExact: false, pid: 12),
        ]
    }

    private func configureWaiting(_ state: AppState, settings: MacBull.Settings) {
        let now = Date()
        state.manual = ManualSession(minutes: 120, startedAt: now.addingTimeInterval(-25 * Self.minute), endsAt: now.addingTimeInterval(95 * Self.minute))
        state.lidSetup = .notSetUp
        state.agents = [
            AgentSummary(name: "Claude Code", sessions: 2, isWorking: false, backgroundRuns: 0, isCustom: false, waitingForYou: 1, stalled: 0),
            AgentSummary(name: "Codex", sessions: 1, isWorking: false, backgroundRuns: 0, isCustom: false, waitingForYou: 0, stalled: 1),
        ]
        state.sessions = [
            AgentSession(id: "a", agent: "Claude Code", folder: "api", activity: .waitingForYou, since: now.addingTimeInterval(-6 * Self.minute), lastSignOfLife: now, isExact: true, pid: 10),
            AgentSession(id: "b", agent: "Claude Code", folder: "web", activity: .turnDone, since: now.addingTimeInterval(-2 * Self.minute), lastSignOfLife: now, isExact: true, pid: 11),
            AgentSession(id: "c", agent: "Codex", folder: "worker", activity: .stalled, since: now.addingTimeInterval(-12 * Self.minute), lastSignOfLife: now.addingTimeInterval(-12 * Self.minute), isExact: false, pid: 12),
        ]
    }

    // MARK: The renders

    @Test func renderPanelStates() throws {
        guard let directory = ProcessInfo.processInfo.environment["MACBULL_RENDER_DIR"], !directory.isEmpty else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try render(makeEnvironment { state, _ in state.lidSetup = .ready }, to: "panel-off", in: folder)
        try render(makeEnvironment { state, _ in state.lidSetup = .ready },
                   preview: PanelPreview(dragStop: .h1), to: "panel-pouring", in: folder)
        try render(makeEnvironment(configure: configureAgents), to: "panel-agents", in: folder)
        try render(makeEnvironment(configure: configureAgents), dark: true, to: "panel-agents-dark", in: folder)
        try render(makeEnvironment(configure: configureWaiting), to: "panel-waiting", in: folder)
        try render(makeEnvironment(configure: configureWaiting), dark: true, to: "panel-waiting-dark", in: folder)
        try render(makeEnvironment { state, _ in
            state.lidSetup = .ready
            state.latestReceipt = sampleReceipt()
            state.receipts = [sampleReceipt()]
        }, to: "panel-receipt", in: folder)
        let longNight = { (state: AppState, _: MacBull.Settings) in
            state.lidSetup = .ready
            state.latestReceipt = longNightReceipt()
            state.receipts = [longNightReceipt()]
        }
        try render(makeEnvironment(configure: longNight), to: "panel-receipt-long", in: folder)
        try renderHosted(makeEnvironment(configure: longNight), receiptExpanded: true, to: "panel-receipt-long-expanded", in: folder)
        try renderHosted(makeEnvironment { state, _ in
            state.lidSetup = .ready
            state.latestReceipt = longNightReceipt(extraFolders: 10)
        }, receiptExpanded: true, to: "panel-receipt-long-scrolling", in: folder)
        try render(makeEnvironment(stats: sampleStats()), preview: PanelPreview(face: .nutrition),
                   to: "panel-nutrition", in: folder)
        try render(makeEnvironment(stats: sampleStats()), preview: PanelPreview(face: .nutrition), dark: true,
                   to: "panel-nutrition-dark", in: folder)
        try render(makeEnvironment(), preview: PanelPreview(face: .nutrition), to: "panel-nutrition-empty", in: folder)
        try render(makeEnvironment { state, _ in
            state.cutoff = .heat
            state.lidSetup = .noLid
        }, to: "panel-cutoff", in: folder)
        try render(makeEnvironment { state, settings in
            configureAgents(state, settings: settings)
            state.thermal = .serious
        }, to: "panel-amber", in: folder)
        try render(makeEnvironment { state, _ in
            state.manual = ManualSession(minutes: 0, startedAt: Date(), endsAt: nil)
        }, preview: PanelPreview(dragStop: .untilOff, foam: 1), to: "panel-foam", in: folder)
        try render(makeEnvironment { state, _ in
            state.receipts = [sampleReceipt(), sampleReceipt()]
        }, preview: PanelPreview(face: .receipts), to: "panel-receipts", in: folder)
    }
}

// MARK: - The real window (only when MACBULL_RENDER_DIR is set, since it needs a window server)

@MainActor
struct PanelWindowRenderTests {
    /// Lets both the run loop (SwiftUI updates, animations) and the main actor's queue (our tasks) work.
    private func spin(_ seconds: TimeInterval) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            runLoopOnce()
            await Task.yield()
        }
    }

    private func runLoopOnce() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    @Test func windowRenderOpensPlacesAndClosesThePanel() async throws {
        guard let directory = ProcessInfo.processInfo.environment["MACBULL_RENDER_DIR"], !directory.isEmpty else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = NSApplication.shared

        let state = AppState()
        state.agentHold = true
        state.lidSetup = .ready
        state.agents = [AgentSummary(name: "Claude Code", sessions: 1, isWorking: true, backgroundRuns: 0, isCustom: false, waitingForYou: 0, stalled: 0)]
        let settings = MacBull.Settings(defaults: try #require(UserDefaults(suiteName: "macbull.window.\(UUID().uuidString)")))
        let environment = AppEnvironment(state: state, settings: settings, actions: RenderActions(), feedback: RenderFeedback())
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        // Where the status item would be: top right, just above the visible area
        let anchor = NSRect(x: visible.maxX - 120, y: visible.maxY, width: 24, height: 24)
        var closedCount = 0
        let controller = PanelController(environment: environment, anchor: { PanelAnchor(frame: anchor, screen: screen) }, onClose: { closedCount += 1 })

        #expect(!controller.isShown)
        controller.show()
        controller.show()
        await spin(0.6)
        #expect(controller.isShown)
        let panel = try #require(NSApp.windows.first { $0 is NSPanel && $0.isVisible })
        #expect(panel.frame.width == PanelMetrics.width)
        #expect(panel.frame.maxY == anchor.minY - 6, "top edge 6 pt below the item")
        #expect(panel.frame.height > 300)
        #expect(panel.level == .popUpMenu)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.styleMask.contains(.borderless))
        let heightBefore = panel.frame.height
        let topBefore = panel.frame.maxY

        // More content: the top edge stays, the panel grows downwards
        state.cutoff = .heat
        state.agentHold = false
        state.agents = []
        state.sessions = [AgentSession(id: "a", agent: "Claude Code", folder: "api", activity: .waitingForYou, since: Date(), lastSignOfLife: Date(), isExact: true, pid: 1)]
        await spin(0.6)
        #expect(panel.frame.maxY == topBefore)
        #expect(panel.frame.height != heightBefore)

        if let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("panel-window.png"))
        }

        controller.close()
        await spin(0.2)
        #expect(!controller.isShown)
        #expect(!panel.isVisible)
        #expect(closedCount == 1)
        #expect(panel.contentView?.subviews.isEmpty == true, "the content is destroyed on close")
        controller.close()
        #expect(closedCount == 1)

        // The menu bar item itself: created, toggled, closed
        let item = StatusItemController(environment: environment, statusLine: { "Awake while Claude Code works" })
        #expect(!item.isPanelShown)
        item.showPanel()
        await spin(0.3)
        #expect(item.isPanelShown)
        item.closePanel()
        #expect(!item.isPanelShown)

        // The tooltip follows the engine's status line (no timer of its own)
        item.statusLineChanged("Awake for 12 min more")
        #expect(item.toolTip == "Awake for 12 min more")
        item.statusLineChanged("Off, the Mac sleeps as usual")
        #expect(item.toolTip == "Off, the Mac sleeps as usual")
    }
}
