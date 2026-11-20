import SwiftUI

/// What a preview or a render can force: a stop being dragged, a foam in progress, the opening face.
struct PanelPreview {
    var dragStop: PourStop?
    var foam: Double = 0
    var face: PanelFace?
    var statsRange: StatsRange = .today
}

/// The hero card: the pour scene with its drag control, the big title, the sentence and the lid badge.
struct PanelHero: View {
    let env: AppEnvironment
    var preview = PanelPreview()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragStop: PourStop?
    /// The stop before the one now under the pointer, for the pour table.
    @State private var previousStop: PourStop?
    @State private var foam: Double
    @State private var isFoaming = false
    @State private var pulses: [PourPulse] = []
    @State private var seenToolPulses: Int
    @State private var nextPulseID = 0

    static let sceneHeight: CGFloat = 150
    /// How long the foam stays over the laptop before it settles.
    private static let foamDuration = 2.4
    private static let levelSpring = Animation.spring(duration: 0.9, bounce: 0.12)
    private static let pourSpring = Animation.spring(duration: 0.5, bounce: 0.2)

    init(env: AppEnvironment, preview: PanelPreview = PanelPreview()) {
        self.env = env
        self.preview = preview
        _dragStop = State(initialValue: preview.dragStop)
        _foam = State(initialValue: preview.foam)
        _seenToolPulses = State(initialValue: env.state.toolPulses)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(facts: HeroFacts.make(state: env.state, settings: env.settings, drag: dragStop, now: context.date))
        }
        .task(id: dragStop == .untilOff) {
            await holdAtTop()
        }
        .onChange(of: env.state.toolPulses) { _, newValue in
            addPulses(upTo: newValue)
        }
        .onDisappear {
            env.feedback.setFizz(nil)
        }
    }

    // MARK: - Content

    private func content(facts: HeroFacts) -> some View {
        let title = HeroCopy.title(facts)
        let sentence = HeroCopy.sentence(facts)
        return VStack(alignment: .leading, spacing: 4) {
            scene(facts: facts)
            VStack(alignment: .leading, spacing: 4) {
                titleView(title)
                Text(sentence)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.frost.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                // The badge keeps its place while the lid feature is on, and only fades in and out as the
                // hold comes and goes, so the panel does not change height when you pour or turn off.
                if env.state.lidSetup == .ready, env.settings.lidHold {
                    lidBadge
                        .padding(.top, 4)
                        .opacity(env.state.lidHeld ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: env.state.lidHeld)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .fill(LinearGradient(colors: [Theme.navy, Theme.navyDeep], startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func titleView(_ title: HeroTitle) -> some View {
        switch title {
        case .text(let text):
            Text(text)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.frost)
        case .infinity:
            Image(systemName: "infinity")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.frost)
                .frame(height: 46, alignment: .center)
        }
    }

    private var lidBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 11, weight: .semibold))
            Text("Safe to close the lid")
                .font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(Theme.volt)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.volt.opacity(0.16)))
    }

    // MARK: - Scene

    private func scene(facts: HeroFacts) -> some View {
        let level = HeroCopy.level(facts)
        let pour = dragPour
        let working = LiveCarbonation.workingSessions(env.state.sessions)
        let dragging = dragStop != nil
        let animated = !reduceMotion
        let amber = LiveCarbonation.isAmber(
            thermal: env.state.thermal, onBattery: env.state.onBattery, batteryPercent: env.state.batteryPercent,
            batteryGuard: env.settings.batteryGuard, batteryLimit: env.settings.batteryPercent)
        // Each driver carries its own animation: level, pour and foam use different springs.
        return PanelScalarDriver(value: level) { shownLevel in
            PanelScalarDriver(value: pour) { shownPour in
                PanelScalarDriver(value: foam) { shownFoam in
                    PourScene(
                        level: shownLevel, pour: shownPour,
                        isBubbling: env.state.agentHold && !dragging,
                        label: dragStop?.label, isAnimated: animated, isAmber: amber,
                        bubbleCount: LiveCarbonation.bubbleCount(workingSessions: working),
                        pulses: pulses, foam: shownFoam)
                }
                .animation(animated ? .easeOut(duration: 0.5) : nil, value: foam)
            }
            .animation(animated ? Self.pourSpring : nil, value: pour)
        }
        .animation(animated ? Self.levelSpring : nil, value: level)
        .frame(height: Self.sceneHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onTapGesture { tap() }
        .help("Drag up to pour in time, click to switch")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("time left")
        .accessibilityValue(HeroCopy.spokenValue(facts))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tap() }
        .accessibilityAdjustableAction { direction in
            adjust(direction)
        }
    }

    private var dragPour: Double {
        guard let dragStop else { return 0 }
        return PourRules.pour(stop: dragStop, previous: previousStop)
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: PourRules.dragMinimum)
            .onChanged { value in
                dragMoved(to: PourRules.stop(atY: value.location.y, height: Self.sceneHeight))
            }
            .onEnded { _ in
                dragEnded()
            }
    }

    private func dragMoved(to stop: PourStop) {
        guard stop != dragStop else { return }
        let old = dragStop
        previousStop = old
        dragStop = stop
        if old != nil {
            env.feedback.detent(strong: stop == .untilOff)
        }
        env.feedback.setFizz(PourRules.level(for: stop))
    }

    private func dragEnded() {
        let stop = dragStop
        dragStop = nil
        previousStop = nil
        env.feedback.setFizz(nil)
        if let stop { commit(stop) }
    }

    private func commit(_ stop: PourStop) {
        guard let minutes = stop.minutes else {
            let wasAwake = env.state.isAwake
            env.actions.turnOff()
            if wasAwake { env.feedback.play(.clink) }
            return
        }
        env.actions.turnOn(minutes: minutes)
        env.feedback.play(.crack)
    }

    private func tap() {
        let wasAwake = env.state.isAwake
        env.actions.toggle()
        env.feedback.play(wasAwake ? .clink : .crack)
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let current = PourRules.currentStop(manual: env.state.manual)
        switch direction {
        case .increment: commit(PourRules.stepped(current, by: 1))
        case .decrement: commit(PourRules.stepped(current, by: -1))
        @unknown default: break
        }
    }

    // MARK: - Live Carbonation and the easter egg

    private func addPulses(upTo total: Int) {
        let added = LiveCarbonation.pulsesAdded(from: seenToolPulses, to: total)
        seenToolPulses = total
        let now = Date().timeIntervalSinceReferenceDate
        var kept = pulses.filter { now - $0.born < PourPulse.lifetime }
        for offset in 0..<added {
            let id = nextPulseID
            nextPulseID += 1
            // A spread that never repeats back to back, from the id alone
            let x = 0.1 + 0.8 * ((Double(id) * 0.618_033_988).truncatingRemainder(dividingBy: 1))
            kept.append(PourPulse(id: id, born: now + Double(offset) * 0.12, x: x))
        }
        pulses = Array(kept.suffix(LiveCarbonation.maxPulses))
    }

    /// Hold at until-off for two seconds and the laptop foams over, once a day.
    private func holdAtTop() async {
        guard dragStop == .untilOff else { return }
        do {
            try await Task.sleep(for: .seconds(FoamRule.holdSeconds))
        } catch {
            return
        }
        let store = FoamStore()
        let now = Date()
        guard !isFoaming,
              FoamRule.isAllowed(lastFoam: store.lastFoam, now: now, reduceMotion: reduceMotion) else { return }
        store.record(now)
        env.feedback.play(.burp)
        isFoaming = true
        // Unstructured on purpose: letting go of the can must not leave the foam half drawn.
        Task { @MainActor in
            foam = 1
            defer {
                foam = 0
                isFoaming = false
            }
            do {
                try await Task.sleep(for: .seconds(Self.foamDuration))
            } catch {
                Log.ui.debug("Foam cut short: \(error.localizedDescription)")
            }
        }
    }
}
