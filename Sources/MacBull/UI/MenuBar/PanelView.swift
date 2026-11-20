import SwiftUI

enum PanelFace: Equatable {
    case main
    case nutrition
    case receipts
}

/// A card that turns over: the front until half way, then the back. With Reduce Motion it fades through
/// nothing instead of turning. Only the face being shown is built.
struct PanelFlip<Front: View, Back: View>: View, @preconcurrency Animatable {
    /// 0 shows the front, 180 the back.
    var angle: Double
    var fades: Bool
    var front: () -> Front
    var back: () -> Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        if angle < 90 {
            face(front(), turn: angle)
        } else {
            face(back(), turn: angle - 180)
        }
    }

    @ViewBuilder
    private func face<Content: View>(_ content: Content, turn: Double) -> some View {
        if fades {
            content.opacity(abs(cos(angle * .pi / 180)))
        } else {
            content.rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
    }
}

enum PanelMetrics {
    /// The panel is 340 pt wide.
    static let width: CGFloat = 340
}

/// The whole panel content, 340 pt wide, as the window shows it.
struct PanelView: View {
    static let padding: CGFloat = 12

    let env: AppEnvironment
    let close: () -> Void
    var preview = PanelPreview()
    /// Called with the content's height whenever it changes, so the window can follow.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backFace: PanelFace
    @State private var angle: Double

    init(env: AppEnvironment, close: @escaping () -> Void, preview: PanelPreview = PanelPreview(),
         onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.env = env
        self.close = close
        self.preview = preview
        self.onHeightChange = onHeightChange
        let face = preview.face ?? .main
        _backFace = State(initialValue: face == .main ? .nutrition : face)
        _angle = State(initialValue: face == .main ? 0 : 180)
    }

    var body: some View {
        PanelFlip(angle: angle, fades: reduceMotion, front: { mainFace }, back: { backContent })
            .padding(Self.padding)
            .frame(width: PanelMetrics.width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
            // Pinned to the top: when the content changes height, the window follows a moment later. Until it
            // does, the content must not be centred in the old frame, or everything jumps by half the change.
            .frame(maxHeight: .infinity, alignment: .top)
            .onChange(of: env.state.cutoff) { old, new in
                // A safety stop while the panel is open
                if old == nil, new != nil { env.feedback.play(.crumple) }
            }
    }

    // MARK: Faces

    private var mainFace: some View {
        VStack(spacing: 10) {
            if let receipt = env.state.latestReceipt {
                PanelReceiptCard(receipt: receipt) { env.actions.dismissReceipt() }
            }
            if !YourTurnRows.rows(from: env.state.sessions).isEmpty {
                PanelYourTurn(env: env)
            }
            PanelHero(env: env, preview: preview)
            PanelQuickPicks(env: env)
            if let stop = env.state.cutoff, !env.state.isAwake {
                PanelCutoffBanner(stop: stop)
            }
            PanelModesBox(env: env, closePanel: close)
            PanelFooter(env: env, closePanel: close,
                        showNutrition: { flip(to: .nutrition) },
                        showReceipts: { flip(to: .receipts) })
        }
    }

    @ViewBuilder
    private var backContent: some View {
        switch backFace {
        case .receipts:
            PanelReceiptHistory(receipts: env.state.receipts) { flip(to: .main) }
        default:
            PanelNutrition(env: env, initialRange: preview.statsRange) { flip(to: .main) }
        }
    }

    private func flip(to face: PanelFace) {
        if face != .main { backFace = face }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.4)) {
            angle = face == .main ? 0 : 180
        }
    }
}
