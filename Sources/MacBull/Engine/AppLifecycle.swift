import AppKit
import Foundation

/// Single instance. Call before building anything that touches the Mac's sleep setting:
/// a second copy would fight the first over it.
enum SingleInstance {
    @MainActor
    static func exitIfAnotherInstanceRuns() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != me }
        guard let first = others.first else { return }
        first.activate()
        Log.engine.notice("Another copy is running, bringing it forward and exiting")
        exit(0)
    }
}

/// The hidden main menu: only so Cmd+Q, Cmd+W and the editing shortcuts work in Settings and Welcome.
enum MainMenu {
    @MainActor
    static func install() {
        let menu = NSMenu()
        menu.addItem(submenu(title: "MacBull", items: [
            item("Quit MacBull", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        menu.addItem(submenu(title: "File", items: [
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        menu.addItem(submenu(title: "Edit", items: [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ]))
        NSApp.mainMenu = menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        return holder
    }
}

/// The application delegate. main.swift builds the model, sets `panel` and `windows`, then
/// `app.delegate = AppLifecycle(model:)`.
@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate {
    private let model: AppModel
    private var signalSources: [any DispatchSourceSignal] = []
    private var activity: (any NSObjectProtocol)?

    /// Kill, logout and Activity Monitor Quit end in a normal quit, so sleep is never left disabled.
    static let quitSignals: [Int32] = [SIGTERM, SIGINT, SIGHUP]

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        MainMenu.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep timers and scans running while idle in the background (App Nap off), without blocking sleep.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "MacBull keeps its timers and scans running"
        )
        installSignalHandlers()
        model.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        model.handle(urls: urls)
    }

    /// Launching the app again while it runs opens Settings on General.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.openSettings(.general)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.prepareForQuit()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.prepareForQuit()
    }

    private func installSignalHandlers() {
        for number in Self.quitSignals {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.model.quit() }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
