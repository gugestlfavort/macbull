import AppKit

// Wiring: build every module once and hand each the others through the contracts. The engine (AppModel)
// owns the rules; the other pieces report facts and carry out commands.
//
// These are top-level constants of main.swift, so they live as long as the process does. NSApplication
// holds its delegate weakly, and the menu bar item and the windows must outlive this file's last line.

// A second copy would fight the first over the Mac's sleep setting: leave before building anything.
SingleInstance.exitIfAnotherInstanceRuns()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let state = AppState()
let settings = Settings.shared
let power = IOKitPowerAssertions()
let lid = LidController()
let system = SystemMonitor()
let agents = AgentWatcher()
let journal = Journal()

let model = AppModel(
    state: state, settings: settings, power: power, lid: lid, system: system, agents: agents, journal: journal
)

let feedback = Feedback(settings: settings)
let environment = AppEnvironment(state: state, settings: settings, actions: model, feedback: feedback)

let statusItem = StatusItemController(environment: environment, statusLine: { model.statusLine })
let windows = WindowController(
    env: environment, hasLid: system.hasLid, agentNames: AgentCatalogue.builtIn.map(\.name)
)
model.panel = statusItem
model.onStatusLineChange = { statusItem.statusLineChanged($0) }
model.windows = windows

let lifecycle = AppLifecycle(model: model)
app.delegate = lifecycle
app.run()
