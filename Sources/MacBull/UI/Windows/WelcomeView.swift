import SwiftUI

let welcomeWindowSize = CGSize(width: 560, height: 470)
private let welcomeHeaderHeight: CGFloat = 170

struct WelcomeView: View {
    let env: AppEnvironment
    let hasLid: Bool
    let icon: NSImage
    let model: WelcomeModel
    /// Called when the user finishes; `openPanel` is true for the last button.
    let onFinish: (_ openPanel: Bool) -> Void

    @State private var login: LoginItemModel
    @State private var lidRunner = LidSetupRunner()
    @Bindable private var settings: Settings
    @Bindable private var state: AppState

    init(
        env: AppEnvironment, hasLid: Bool, icon: NSImage, model: WelcomeModel,
        onFinish: @escaping (_ openPanel: Bool) -> Void
    ) {
        self.env = env
        self.hasLid = hasLid
        self.icon = icon
        self.model = model
        self.onFinish = onFinish
        settings = env.settings
        state = env.state
        _login = State(initialValue: LoginItemModel(actions: env.actions))
    }

    private var step: WelcomeStep { model.flow.current }
    private var lidReady: Bool { state.lidSetup == .ready }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .padding(.horizontal, 36)
                .padding(.top, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .frame(width: welcomeWindowSize.width, height: welcomeWindowSize.height)
        .background(.background)
        .onChange(of: step) { _, _ in login.refresh() }
    }

    // MARK: Header and footer

    private var header: some View {
        ZStack {
            LinearGradient(colors: [Theme.navy, Theme.navyDeep], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 16) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    .accessibilityHidden(true)
                ProgressDots(index: model.flow.index, count: model.flow.count)
            }
            .padding(.top, 22)
        }
        .frame(height: welcomeHeaderHeight)
        .ignoresSafeArea()
    }

    private var footer: some View {
        HStack {
            if !model.flow.isFirst {
                Button("Back") { model.flow.back() }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            Button(continueLabel) { advance() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.electric)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var continueLabel: String {
        switch step {
        case .hello: "Get started"
        case .login: LoginItemCopy.isOn(login.status) ? "Continue" : "Not now"
        case .lid: lidReady ? "Continue" : "Not now"
        case .agents: "Continue"
        case .done: "Open the panel"
        }
    }

    private func advance() {
        if step == .done {
            onFinish(true)
        } else {
            model.flow.next()
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .hello: helloStep
        case .login: loginStep
        case .lid: lidStep
        case .agents: agentsStep
        case .done: doneStep
        }
    }

    private func page(_ title: String, _ text: String, @ViewBuilder extra: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            extra().padding(.top, 8)
        }
    }

    private var helloStep: some View {
        page(
            "Meet MacBull",
            "MacBull keeps your Mac awake when you need it: for a while, with the lid closed, and while your AI agents work. A few quick steps and you are done."
        ) { EmptyView() }
    }

    private var loginStep: some View {
        page(
            "Start with your Mac",
            "Open MacBull at login so it is ready every time the Mac starts. You can change this later in Settings."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if login.status == .enabled {
                    SettingsStatusRow(text: "Opens at login", symbol: "checkmark.circle.fill", color: .green)
                } else {
                    Button("Open at login") { login.set(true) }
                }
                LoginItemNotes(model: login)
            }
        }
    }

    private var lidStep: some View {
        page(
            "Keep going with the lid closed",
            "Without an external display, a Mac sleeps when you close the lid. MacBull can stop that once you allow it with your password. It can only switch sleep and Low Power Mode on and off."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if lidReady {
                    SettingsStatusRow(text: "Ready", symbol: "checkmark.circle.fill", color: .green)
                } else {
                    HStack {
                        Button("Allow lid closed mode\u{2026}") { installLid() }
                            .disabled(lidRunner.isWorking)
                        if lidRunner.isWorking { ProgressView().controlSize(.small) }
                    }
                }
                if let message = lidRunner.errorText {
                    SettingsStatusRow(text: message, symbol: "exclamationmark.triangle.fill", color: .orange)
                }
            }
        }
    }

    private var agentsStep: some View {
        page(
            "Stay awake for AI agents",
            agentsText
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Stay awake while agents work", isOn: $settings.agentMode)
                    .toggleStyle(.switch)
                    .tint(Theme.volt)
                Text(WelcomeAgentsLine.text(agentMode: settings.agentMode, agents: state.agents))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var agentsText: String {
        let lid = hasLid && lidReady ? ", lid closed too" : ""
        return "When an agent is at work, the Mac stays awake by itself\(lid). Sessions that are only open and waiting do not count."
    }

    private var doneStep: some View {
        page(
            "You are all set",
            "MacBull lives in the menu bar. Click the can to open it, drag up on it to add time, or let your agents keep it going."
        ) {
            FakeMenuBar()
        }
    }

    private func installLid() {
        Task {
            let result = await lidRunner.run { await env.actions.installLid() }
            if result == .success { settings.lidHold = true }
        }
    }
}

/// Wide lime capsule for the current step, small frosted dots for the rest. One accessibility element.
struct ProgressDots: View {
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { position in
                Capsule()
                    .fill(position == index ? Theme.volt : Theme.frost.opacity(0.35))
                    .frame(width: position == index ? 22 : 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}
