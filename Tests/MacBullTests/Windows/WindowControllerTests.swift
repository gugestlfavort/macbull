import AppKit
import Testing
@testable import MacBull

@MainActor
struct WindowControllerTests {
    private func makeController(hasLid: Bool = true, settings: Settings? = nil) -> (WindowController, AppEnvironment) {
        _ = NSApplication.shared
        let env = WindowsTestSupport.makeEnvironment(settings: settings)
        let controller = WindowController(env: env, hasLid: hasLid, agentNames: ["Claude Code", "Codex"])
        return (controller, env)
    }

    @Test func settingsIsOneReusedWindowTitledWithTheTab() throws {
        let (controller, _) = makeController()
        controller.openSettings(.general)
        let window = try #require(controller.settingsNSWindow)
        #expect(window.title == "General")
        controller.openSettings(.away)
        #expect(controller.settingsNSWindow === window)
        #expect(window.title == "Away")
        controller.openSettings(.about)
        #expect(window.title == "About")
        window.close()
    }

    @Test func everyTabHasTheFixedWidthAndAReasonableHeight() throws {
        let (controller, _) = makeController()
        for tab in SettingsTab.allCases {
            controller.openSettings(tab)
            let window = try #require(controller.settingsNSWindow)
            let content = window.contentRect(forFrameRect: window.frame)
            #expect(content.width == settingsContentWidth, "\(tab): width \(content.width)")
            let screenHeight = window.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 1_400
            #expect(content.height > 150 && content.height <= screenHeight, "\(tab): height \(content.height)")
        }
        controller.settingsNSWindow?.close()
    }

    @Test func settingsWindowHasOnlyACloseButton() throws {
        let (controller, _) = makeController()
        controller.openSettings(.general)
        let window = try #require(controller.settingsNSWindow)
        #expect(window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.resizable))
        #expect(!window.styleMask.contains(.miniaturizable))
        window.close()
    }

    @Test func welcomeHasTheSpecifiedSizeAndMarksDoneWhenClosed() throws {
        let (controller, env) = makeController()
        #expect(!env.settings.welcomeDone)
        controller.openWelcome(.hello)
        let window = try #require(controller.welcomeNSWindow)
        let content = window.contentRect(forFrameRect: window.frame)
        #expect(content.size == welcomeWindowSize)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titleVisibility == .hidden)
        window.close()
        #expect(env.settings.welcomeDone)
    }

    @Test func welcomeIsReusedAndRestartsAtTheRequestedStep() throws {
        let (controller, _) = makeController()
        controller.openWelcome(.hello)
        let window = try #require(controller.welcomeNSWindow)
        controller.openWelcome(.agents)
        #expect(controller.welcomeNSWindow === window)
        window.close()
    }
}
