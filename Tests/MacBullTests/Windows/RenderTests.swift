import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MacBull

/// Writes a PNG of every Settings tab and every Welcome step when MACBULL_RENDER_DIR is set:
///   MACBULL_RENDER_DIR=docs/renders swift test --filter Render
private let renderDirectory = ProcessInfo.processInfo.environment["MACBULL_RENDER_DIR"]

@MainActor
struct RenderTests {
    private func outputFolder() throws -> URL {
        let path = try #require(renderDirectory)
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path, isDirectory: true)
            : WindowsTestSupport.repoRoot.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func icon() throws -> NSImage {
        try #require(NSImage(contentsOf: WindowsTestSupport.iconFile))
    }

    /// A state with something to show on every tab.
    private func makeEnvironment(lid: LidSetup, populated: Bool) -> AppEnvironment {
        let env = WindowsTestSupport.makeEnvironment()
        env.state.lidSetup = lid
        guard populated else { return env }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        env.state.agents = [
            AgentSummary(name: "Claude Code", sessions: 2, isWorking: true, backgroundRuns: 0, isCustom: false, waitingForYou: 1, stalled: 0),
            AgentSummary(name: "Codex", sessions: 1, isWorking: true, backgroundRuns: 1, isCustom: false, waitingForYou: 0, stalled: 0),
            AgentSummary(name: "Aider", sessions: 1, isWorking: false, backgroundRuns: 0, isCustom: false, waitingForYou: 0, stalled: 0),
            AgentSummary(name: "my_agent.py", sessions: 1, isWorking: true, backgroundRuns: 0, isCustom: true, waitingForYou: 0, stalled: 0),
        ]
        env.settings.customAgents = ["my_agent.py"]
        env.state.hooksError = "settings.json is not valid JSON. It was left alone: fix it and turn hooks on again."
        env.state.receipts = [
            Receipt(
                id: UUID(), awayFrom: now, awayTo: now.addingTimeInterval(7 * 3600 + 12 * 60),
                lines: [
                    ReceiptLine(agent: "Claude Code", folder: "api", outcome: .finished(at: now, afterSeconds: 2_400)),
                    ReceiptLine(agent: "Codex", folder: "web", outcome: .finished(at: now, afterSeconds: 600)),
                    ReceiptLine(agent: "Aider", folder: "docs", outcome: .waitingForYou(since: now)),
                ],
                batteryStart: 84, batteryEnd: 61, pluggedIn: false, peakThermal: 1, sleptAt: [], safetyStop: nil, notRunningSince: nil
            ),
            Receipt(
                id: UUID(), awayFrom: now.addingTimeInterval(-86_400), awayTo: now.addingTimeInterval(-86_400 + 1_800),
                lines: [], batteryStart: 40, batteryEnd: 18, pluggedIn: false, peakThermal: 2, sleptAt: [],
                safetyStop: .battery, notRunningSince: nil
            ),
        ]
        return env
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    private func savePNG(of view: NSView, as name: String, to folder: URL) throws {
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// The whole window: title bar, tab strip and content, as the user sees it.
    private func write(_ window: NSWindow, as name: String, to folder: URL, dark: Bool = false) throws {
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settle()
        window.displayIfNeeded()
        try savePNG(of: try #require(window.contentView?.superview), as: name, to: folder)
        window.orderOut(nil)
    }

    /// A view at its natural size, drawn as in a key window (the test process is never the active app).
    private func writeContent(_ content: some View, as name: String, to folder: URL, dark: Bool = false) throws {
        let host = NSHostingView(rootView: content.environment(\.controlActiveState, .key))
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settle()
        window.displayIfNeeded()
        try savePNG(of: host, as: name, to: folder)
        window.orderOut(nil)
    }

    private func writeFullTab(_ tab: SettingsTab, env: AppEnvironment, icon: NSImage, to folder: URL, dark: Bool = false) throws {
        let content = SettingsTabContent(
            tab: tab, env: env, hasLid: true,
            agentNames: ["Claude Code", "Codex", "Gemini CLI", "Cursor Agent", "Copilot CLI", "OpenCode", "Amp", "Aider"],
            icon: icon, version: "dev"
        )
        try writeContent(content, as: "settings-\(tab.rawValue)\(dark ? "-dark" : "")", to: folder, dark: dark)
    }

    private func writeWelcome(_ step: WelcomeStep, env: AppEnvironment, hasLid: Bool, icon: NSImage, to folder: URL, name: String, dark: Bool = false) throws {
        let model = WelcomeModel(start: step, hasLid: hasLid)
        let view = WelcomeView(env: env, hasLid: hasLid, icon: icon, model: model, onFinish: { _ in })
        try writeContent(view, as: name, to: folder, dark: dark)
    }

    @Test(.enabled(if: renderDirectory != nil)) func renderSettingsTabs() throws {
        NSApplication.shared.setActivationPolicy(.regular)
        let folder = try outputFolder()
        let icon = try icon()
        for tab in SettingsTab.allCases {
            try writeFullTab(tab, env: makeEnvironment(lid: .notSetUp, populated: true), icon: icon, to: folder)
        }
        try writeFullTab(.general, env: makeEnvironment(lid: .notSetUp, populated: true), icon: icon, to: folder, dark: true)

        let ready = makeEnvironment(lid: .ready, populated: false)
        let lid = SettingsWindowController(env: ready, hasLid: true, agentNames: [], icon: icon, version: "dev")
        lid.show(.lid)
        try write(lid.window, as: "settings-lid-ready-window", to: folder)
        lid.window.close()

        let noLid = SettingsWindowController(env: makeEnvironment(lid: .noLid, populated: false), hasLid: false, agentNames: [], icon: icon, version: "dev")
        noLid.show(.lid)
        try write(noLid.window, as: "settings-lid-nolid-window", to: folder)
        noLid.window.close()

        let safety = SettingsWindowController(env: makeEnvironment(lid: .notSetUp, populated: true), hasLid: true, agentNames: [], icon: icon, version: "dev")
        safety.show(.safety)
        try write(safety.window, as: "settings-safety-window", to: folder)
        safety.window.close()
    }

    @Test(.enabled(if: renderDirectory != nil)) func renderWelcomeSteps() throws {
        NSApplication.shared.setActivationPolicy(.regular)
        let folder = try outputFolder()
        let icon = try icon()
        for step in WelcomeStep.allCases {
            let env = makeEnvironment(lid: .notSetUp, populated: step == .agents)
            try writeWelcome(step, env: env, hasLid: true, icon: icon, to: folder, name: "welcome-\(step.rawValue)")
        }
        let readyLid = makeEnvironment(lid: .ready, populated: true)
        try writeWelcome(.lid, env: readyLid, hasLid: true, icon: icon, to: folder, name: "welcome-lid-ready")
        try writeWelcome(.done, env: makeEnvironment(lid: .noLid, populated: false), hasLid: false, icon: icon, to: folder, name: "welcome-done-dark-nolid", dark: true)

        // The real window, with its transparent title bar.
        let controller = WelcomeWindowController(env: makeEnvironment(lid: .notSetUp, populated: false), hasLid: true, icon: icon, start: .hello)
        controller.show(.hello)
        try write(controller.window, as: "welcome-hello-window", to: folder)
        controller.window.close()
    }
}
