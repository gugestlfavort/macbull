import SwiftUI

/// One extra bubble, born from a Claude Code tool call (Live Carbonation).
struct PourPulse: Identifiable, Equatable, Sendable {
    let id: Int
    /// `Date.timeIntervalSinceReferenceDate` at birth.
    let born: TimeInterval
    /// Where across the screen it rises, 0...1.
    let x: Double

    /// Seconds a pulse bubble takes to rise.
    static let lifetime: TimeInterval = 2.4
}

/// The hero of the panel: an energy drink can pours lime drink into a laptop. The liquid level on the
/// laptop's screen is the keep-awake time, and the more the can tips, the higher the level is being set.
/// Everything is drawn in code in a 288 x 150 design space, scaled to fit the view.
/// The scene itself does not animate its numbers: the panel feeds it level and pour already eased.
struct PourScene: View {
    /// 0 empty ... 1 full. The height of the liquid on the screen.
    var level: Double
    /// 0 the can stands at rest, 1 it is fully tipped over the screen.
    var pour: Double
    /// Bubbles rise in the liquid while agents work.
    var isBubbling = false
    /// Shown on the liquid while a duration is being set, like "1h".
    var label: String?
    /// Off with Reduce Motion: no waves, no bubbles, one still frame.
    var isAnimated = true
    /// Level fractions that get a tick on the screen's right edge. These match the stops the panel title shows:
    /// 15m, 1h, 5h and until-off (indices 1, 3, 6 and 8 of the eight steps).
    var marks: [Double] = PourScene.defaultMarks
    /// The liquid shifts toward amber when the Mac runs hot or the battery is low (Live Carbonation).
    var isAmber = false
    /// How many of the resting bubbles are drawn: more with more working sessions.
    var bubbleCount = LiveCarbonation.maxBubbles
    /// One extra bubble per tool call.
    var pulses: [PourPulse] = []
    /// 0...1: the laptop foams over (easter egg).
    var foam: Double = 0

    /// The stops 15m, 1h, 5h and until-off, as fractions of the screen.
    static let defaultMarks: [Double] = [0.125, 0.375, 0.75, 1]

    /// The pour value above which a stream leaves the can.
    static let streamThreshold = 0.15

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !needsMotion)) { context in
            let time = isAnimated ? context.date.timeIntervalSinceReferenceDate : 0
            Canvas { canvas, size in
                let scale = min(size.width / Spec.design.width, size.height / Spec.design.height)
                var scene = canvas
                scene.translateBy(x: (size.width - Spec.design.width * scale) / 2,
                                  y: (size.height - Spec.design.height * scale) / 2)
                scene.scaleBy(x: scale, y: scale)
                draw(in: &scene, time: time)
            }
        }
    }

    private var needsMotion: Bool {
        isAnimated && (pour > 0 || isBubbling || level > 0 || foam > 0)
    }

    private var clampedLevel: Double { min(max(level, 0), 1) }
    private var clampedPour: Double { min(max(pour, 0), 1) }
    private var clampedFoam: Double { min(max(foam, 0), 1) }
    private var isPouring: Bool { clampedPour > Self.streamThreshold }

    // MARK: - Layout

    /// Fixed positions in the 288 x 150 design space.
    private enum Spec {
        static let design = CGSize(width: 288, height: 150)
        static let screen = CGRect(x: 124, y: 70, width: 112, height: 61)
        static let lid = CGRect(x: 118, y: 63, width: 124, height: 74)
        static let base = CGRect(x: 104, y: 137, width: 152, height: 7)
        static let canSize = CGSize(width: 26, height: 56)
        /// Where the can's bottom right corner is, standing on the ground and tipped over the screen.
        static let restPivot = CGPoint(x: 66, y: 141)
        static let pourPivot = CGPoint(x: 91, y: 20)
        /// Tilt in degrees: the can is already past horizontal when the stream starts, and fully tipped
        /// the mouth points down toward the screen.
        static let pouringTilt = 100.0
        static let maxTilt = 132.0
        /// The can gets to its lifted position by this pour value.
        static let liftEnd = 0.4
        /// Where across the lid the opening sits (the pull tab is on the other side), as a fraction of the can's width.
        static let mouthU: CGFloat = 0.66
        static let navyInk = Color(red: 0.03, green: 0.05, blue: 0.10)
        static let dropLight = Color(red: 0.93, green: 1.0, blue: 0.45)
        static let dropDark = Color(red: 0.55, green: 0.80, blue: 0.08)
        static let amberLight = Color(red: 1.0, green: 0.84, blue: 0.48)
        static let amberDark = Color(red: 0.78, green: 0.47, blue: 0.04)
    }

    /// Up to the stream threshold the can tips to just past horizontal, then the rest of the pour opens it
    /// out toward the screen, so it is never near horizontal for long while it pours.
    private var tilt: Angle {
        if clampedPour <= Self.streamThreshold {
            return .degrees(Spec.pouringTilt * clampedPour / Self.streamThreshold)
        }
        let rest = (clampedPour - Self.streamThreshold) / (1 - Self.streamThreshold)
        return .degrees(Spec.pouringTilt + (Spec.maxTilt - Spec.pouringTilt) * rest)
    }

    private var lift: Double {
        let progress = min(clampedPour / Spec.liftEnd, 1)
        return progress * progress * (3 - 2 * progress)
    }

    private var pivot: CGPoint {
        CGPoint(x: Self.mix(Spec.restPivot.x, Spec.pourPivot.x, lift),
                y: Self.mix(Spec.restPivot.y, Spec.pourPivot.y, lift))
    }

    private static func mix(_ from: CGFloat, _ to: CGFloat, _ amount: Double) -> CGFloat {
        from + (to - from) * CGFloat(amount)
    }

    /// A point in the can's own frame (origin at its bottom right corner, up is negative y) in the scene.
    private func scenePoint(_ local: CGPoint) -> CGPoint {
        let radians = tilt.radians
        return CGPoint(x: pivot.x + local.x * cos(radians) - local.y * sin(radians),
                       y: pivot.y + local.x * sin(radians) + local.y * cos(radians))
    }

    /// The can's opening on the lid, in the can's own frame.
    private var mouthLocal: CGPoint {
        CGPoint(x: -Spec.canSize.width * (1 - Spec.mouthU), y: -Spec.canSize.height)
    }

    /// Where the drink leaves the can.
    private var lip: CGPoint { scenePoint(mouthLocal) }

    private var liquidTop: CGFloat {
        Spec.screen.maxY - Spec.screen.height * clampedLevel
    }

    // MARK: - Scene

    private func draw(in canvas: inout GraphicsContext, time: TimeInterval) {
        drawGround(in: &canvas)
        drawLaptop(in: &canvas)
        drawScreenContents(in: &canvas, time: time)
        if isPouring {
            drawStream(in: &canvas, time: time)
        }
        if clampedFoam > 0.01 {
            drawFoam(in: &canvas, time: time)
        }
        drawCan(in: &canvas)
    }

    private func drawGround(in canvas: inout GraphicsContext) {
        canvas.fill(Path(ellipseIn: CGRect(x: Spec.base.minX - 4, y: Spec.base.maxY - 2, width: Spec.base.width + 8, height: 6)),
                    with: .color(.black.opacity(0.28)))
        let standing = 1 - lift
        guard standing > 0.01 else { return }
        let shadow = CGRect(x: Spec.restPivot.x - Spec.canSize.width - 2, y: Spec.restPivot.y - 2,
                            width: Spec.canSize.width + 4, height: 6)
        canvas.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(0.28 * standing)))
    }

    // MARK: - Laptop

    private func drawLaptop(in canvas: inout GraphicsContext) {
        let silver = Gradient(colors: [Color(red: 0.88, green: 0.90, blue: 0.94), Color(red: 0.52, green: 0.56, blue: 0.63)])
        // Base with a thumb notch
        let base = Spec.base
        let basePath = Path(roundedRect: base, cornerRadii: RectangleCornerRadii(topLeading: 1, bottomLeading: 4, bottomTrailing: 4, topTrailing: 1))
        canvas.fill(basePath, with: .linearGradient(silver, startPoint: CGPoint(x: 0, y: base.minY), endPoint: CGPoint(x: 0, y: base.maxY)))
        canvas.fill(Path(roundedRect: CGRect(x: base.midX - 12, y: base.minY, width: 24, height: 2.4),
                         cornerRadii: RectangleCornerRadii(bottomLeading: 2, bottomTrailing: 2)),
                    with: .color(Color(red: 0.36, green: 0.40, blue: 0.47)))
        canvas.stroke(basePath, with: .color(.black.opacity(0.35)), lineWidth: 0.6)

        // Lid: silver shell, dark bezel, dark navy screen
        let lid = Spec.lid
        let shell = Path(roundedRect: lid, cornerRadii: RectangleCornerRadii(topLeading: 6, bottomLeading: 1, bottomTrailing: 1, topTrailing: 6))
        canvas.fill(shell, with: .linearGradient(silver, startPoint: CGPoint(x: lid.minX, y: lid.minY), endPoint: CGPoint(x: lid.maxX, y: lid.maxY)))
        let bezel = lid.insetBy(dx: 1.6, dy: 1.6)
        canvas.fill(Path(roundedRect: bezel, cornerRadii: RectangleCornerRadii(topLeading: 4.6, bottomLeading: 0.5, bottomTrailing: 0.5, topTrailing: 4.6)),
                    with: .color(Spec.navyInk))
        canvas.fill(Path(ellipseIn: CGRect(x: lid.midX - 1.2, y: lid.minY + 3.2, width: 2.4, height: 2.4)),
                    with: .color(.white.opacity(0.18)))
        canvas.stroke(shell, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
    }

    // MARK: - Screen

    private func screenPath() -> Path {
        Path(roundedRect: Spec.screen, cornerRadius: 2)
    }

    private func drawScreenContents(in canvas: inout GraphicsContext, time: TimeInterval) {
        let screen = Spec.screen
        canvas.fill(screenPath(), with: .linearGradient(
            Gradient(colors: [Theme.navy, Theme.navyDeep]),
            startPoint: CGPoint(x: 0, y: screen.minY), endPoint: CGPoint(x: 0, y: screen.maxY)))

        var glass = canvas
        glass.clip(to: screenPath())
        if clampedLevel > 0.001 {
            drawLiquid(in: &glass, time: time)
        }
        drawMarks(in: &glass)
        drawSheen(in: &glass)
        if let label {
            drawLabel(label, in: &glass)
        }
    }

    /// Waves are small near the top so a full screen has no dark gap, and livelier while pouring.
    private func waveAmplitude() -> CGFloat {
        let calm = min(max((1.02 - clampedLevel) * 10, 0.25), 1)
        return (0.9 + (isPouring ? 1.4 * clampedPour : 0)) * calm
    }

    private func surfaceY(at x: CGFloat, time: TimeInterval) -> CGFloat {
        let screen = Spec.screen
        let progress = (x - screen.minX) / screen.width
        let amplitude = waveAmplitude()
        let main = sin(progress * .pi * 2 + time * 2.4) * amplitude
        let ripple = sin(progress * .pi * 5 - time * 3.1) * amplitude * 0.35
        return liquidTop + main + ripple
    }

    private func wavePath(time: TimeInterval) -> Path {
        let screen = Spec.screen
        var path = Path()
        path.move(to: CGPoint(x: screen.minX, y: screen.maxY))
        var x = screen.minX
        while x < screen.maxX {
            path.addLine(to: CGPoint(x: x, y: surfaceY(at: x, time: time)))
            x += 2
        }
        path.addLine(to: CGPoint(x: screen.maxX, y: surfaceY(at: screen.maxX, time: time)))
        path.addLine(to: CGPoint(x: screen.maxX, y: screen.maxY))
        path.closeSubpath()
        return path
    }

    private var liquidColors: [Color] {
        isAmber ? [Spec.amberLight, Theme.amber, Spec.amberDark] : [Spec.dropLight, Theme.volt, Spec.dropDark]
    }

    private var streamColor: Color { isAmber ? Theme.amber : Theme.volt }

    private func drawLiquid(in canvas: inout GraphicsContext, time: TimeInterval) {
        let screen = Spec.screen
        let wave = wavePath(time: time)
        canvas.fill(wave, with: .linearGradient(
            Gradient(colors: liquidColors),
            startPoint: CGPoint(x: 0, y: liquidTop), endPoint: CGPoint(x: 0, y: screen.maxY)))
        var drink = canvas
        drink.clip(to: wave)
        // A lighter band under the surface and a bright line on it
        drink.fill(Path(CGRect(x: screen.minX, y: liquidTop - 2, width: screen.width, height: 7)),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]),
                                         startPoint: CGPoint(x: 0, y: liquidTop - 2), endPoint: CGPoint(x: 0, y: liquidTop + 5)))
        drink.fill(Path(CGRect(x: screen.minX, y: liquidTop - 1.2, width: screen.width, height: 1.8)), with: .color(.white.opacity(0.7)))
        if isAnimated, isBubbling || isPouring {
            drawBubbles(in: &drink, time: time)
        }
    }

    /// Position across the screen, radius, rises per second and a head start, per bubble.
    private static let bubbles: [(x: CGFloat, radius: CGFloat, speed: Double, phase: Double)] = [
        (0.12, 1.4, 0.30, 0.00), (0.27, 1.0, 0.22, 0.31), (0.41, 1.8, 0.18, 0.57), (0.55, 0.9, 0.28, 0.78),
        (0.66, 1.5, 0.21, 0.12), (0.79, 1.0, 0.33, 0.44), (0.90, 1.3, 0.25, 0.66),
        (0.20, 1.2, 0.26, 0.90), (0.48, 1.6, 0.23, 0.05), (0.72, 0.9, 0.31, 0.52), (0.35, 1.1, 0.27, 0.25),
        (0.84, 1.7, 0.19, 0.38),
    ]

    private func drawBubbles(in canvas: inout GraphicsContext, time: TimeInterval) {
        let screen = Spec.screen
        let travel = screen.maxY - liquidTop
        for bubble in Self.bubbles.prefix(bubbleCount) {
            let cycle = (time * bubble.speed + bubble.phase).truncatingRemainder(dividingBy: 1)
            let y = screen.maxY - 2 - travel * cycle
            let x = screen.minX + screen.width * bubble.x + sin(cycle * .pi * 4 + bubble.phase * 9) * 1.2
            drawBubble(in: &canvas, centre: CGPoint(x: x, y: y), radius: bubble.radius, opacity: 0.70 + 0.25 * (1 - cycle))
        }
        for pulse in pulses {
            let progress = (time - pulse.born) / PourPulse.lifetime
            guard progress >= 0, progress <= 1 else { continue }
            let eased = 1 - (1 - progress) * (1 - progress)
            let y = screen.maxY - 2 - travel * eased
            let x = screen.minX + screen.width * pulse.x + sin(progress * .pi * 3 + pulse.x * 9) * 1.4
            drawBubble(in: &canvas, centre: CGPoint(x: x, y: y), radius: 1.9, opacity: 0.95)
        }
    }

    private func drawBubble(in canvas: inout GraphicsContext, centre: CGPoint, radius: CGFloat, opacity: Double) {
        let dot = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
        canvas.fill(Path(ellipseIn: dot), with: .color(.white.opacity(opacity)))
        canvas.stroke(Path(ellipseIn: dot), with: .color(Theme.navyDeep.opacity(0.35)), lineWidth: 0.5)
    }

    /// Small ticks inside the screen's right edge, one per stop; the top one is longer.
    private func drawMarks(in canvas: inout GraphicsContext) {
        let screen = Spec.screen
        for mark in marks {
            let isTop = mark >= 0.999
            let length: CGFloat = isTop ? 7 : 4.5
            let y = min(max(screen.maxY - screen.height * mark, screen.minY + 1.2), screen.maxY)
            let tick = CGRect(x: screen.maxX - length, y: y - 0.6, width: length, height: 1.2)
            canvas.fill(Path(tick.insetBy(dx: -0.5, dy: -0.5)), with: .color(Theme.navyDeep.opacity(0.35)))
            canvas.fill(Path(tick), with: .color(Theme.frost.opacity(0.6)))
        }
    }

    private func drawSheen(in canvas: inout GraphicsContext) {
        let screen = Spec.screen
        var sheen = Path()
        sheen.move(to: CGPoint(x: screen.minX, y: screen.minY))
        sheen.addLine(to: CGPoint(x: screen.minX + screen.width * 0.42, y: screen.minY))
        sheen.addLine(to: CGPoint(x: screen.minX + screen.width * 0.14, y: screen.maxY))
        sheen.addLine(to: CGPoint(x: screen.minX, y: screen.maxY))
        sheen.closeSubpath()
        canvas.fill(sheen, with: .color(.white.opacity(0.06)))
    }

    private func drawLabel(_ text: String, in canvas: inout GraphicsContext) {
        let screen = Spec.screen
        let y = min(max(liquidTop + 12, screen.minY + 11), screen.maxY - 11)
        let center = CGPoint(x: screen.midX + 10, y: y)
        let resolved = canvas.resolve(Text(text).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.frost))
        let size = resolved.measure(in: CGSize(width: 80, height: 30))
        let capsule = CGRect(x: center.x - size.width / 2 - 6, y: center.y - size.height / 2 - 2, width: size.width + 12, height: size.height + 4)
        canvas.fill(Path(roundedRect: capsule, cornerRadius: capsule.height / 2), with: .color(Theme.navyDeep.opacity(0.88)))
        canvas.draw(resolved, at: center, anchor: .center)
    }

    // MARK: - Stream

    private func impactPoint(time: TimeInterval) -> CGPoint {
        let screen = Spec.screen
        let x = min(max(lip.x + 2 + 4 * clampedPour, screen.minX + 8), screen.maxX - 12)
        let floor = screen.maxY - 2
        let surface = clampedLevel > 0.001 ? min(surfaceY(at: x, time: time), floor) : floor
        return CGPoint(x: x, y: max(surface, lip.y + 2))
    }

    private func drawStream(in canvas: inout GraphicsContext, time: TimeInterval) {
        let start = lip
        let end = impactPoint(time: time)
        var path = Path()
        path.move(to: start)
        // Leaves the mouth sideways and down, then falls straight; a short drop bends less
        let bend = min(0.12 * (end.y - start.y), 6)
        path.addQuadCurve(to: end, control: CGPoint(x: end.x, y: start.y + bend))

        let width = 1.4 + 4.2 * clampedPour
        canvas.stroke(path, with: .color(streamColor), style: StrokeStyle(lineWidth: width, lineCap: .round))
        canvas.stroke(path, with: .color((isAmber ? Spec.amberLight : Spec.dropLight).opacity(0.9)), style: StrokeStyle(lineWidth: width * 0.45, lineCap: .round))
        if isAnimated {
            let dash = StrokeStyle(lineWidth: width * 0.3, lineCap: .round, dash: [5, 9], dashPhase: -time * 36)
            canvas.stroke(path, with: .color(.white.opacity(0.55)), style: dash)
        }
        drawSplash(in: &canvas, at: end, time: time)
    }

    /// Droplets as a position along their arc: sideways speed, upward speed and a head start.
    private static let droplets: [(side: CGFloat, up: CGFloat, phase: Double)] = [
        (-1.0, 0.9, 0.00), (0.8, 1.0, 0.22), (-0.5, 0.6, 0.47), (1.2, 0.7, 0.68), (0.2, 1.1, 0.85),
    ]

    private func drawSplash(in canvas: inout GraphicsContext, at impact: CGPoint, time: TimeInterval) {
        var splash = canvas
        splash.clip(to: screenPath())
        let reach = 0.6 + 0.6 * clampedPour
        let foam = 3 + 5 * clampedPour
        splash.fill(Path(ellipseIn: CGRect(x: impact.x - foam, y: impact.y - 1.6, width: foam * 2, height: 3.2)),
                    with: .color(.white.opacity(0.6)))
        for drop in Self.droplets {
            let progress = isAnimated ? (time * 1.6 + drop.phase).truncatingRemainder(dividingBy: 1) : 0.3 + drop.phase * 0.2
            let rise = 22 * Double(drop.up) * progress - 30 * progress * progress
            guard rise > 0 else { continue }
            let center = CGPoint(x: impact.x + drop.side * 15 * CGFloat(progress),
                                 y: impact.y - CGFloat(rise) * CGFloat(reach))
            let radius = 1.3 - 0.5 * CGFloat(progress)
            splash.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(Spec.dropLight))
        }
    }

    // MARK: - Foam (easter egg)

    /// Foam heaps on the laptop's top edge: position across the lid, radius and how far it climbs.
    private static let foamHeaps: [(x: CGFloat, radius: CGFloat, climb: CGFloat)] = [
        (0.06, 5.0, 3), (0.16, 7.0, 8), (0.27, 6.0, 4), (0.38, 8.0, 11), (0.50, 6.5, 6),
        (0.61, 8.5, 12), (0.72, 6.0, 5), (0.83, 7.5, 9), (0.94, 5.5, 3),
    ]
    /// Runs down the outside of the lid: side (-1 left, 1 right), offset in from the edge, length.
    private static let foamDrips: [(side: CGFloat, inset: CGFloat, length: CGFloat)] = [
        (-1, -1.5, 40), (-1, 5, 22), (1, -1.5, 34), (1, 5, 50),
    ]

    private func drawFoam(in canvas: inout GraphicsContext, time: TimeInterval) {
        let lid = Spec.lid
        let grown = CGFloat(clampedFoam)
        let foamFill = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [.white, Spec.dropLight.opacity(0.9)]),
            startPoint: CGPoint(x: 0, y: lid.minY - 14), endPoint: CGPoint(x: 0, y: lid.minY + 8))
        for drip in Self.foamDrips {
            let x = drip.side < 0 ? lid.minX + drip.inset : lid.maxX - drip.inset - 3
            let length = drip.length * grown
            let rect = CGRect(x: x, y: lid.minY + 4, width: 3.4, height: length)
            canvas.fill(Path(roundedRect: rect, cornerRadius: 1.7), with: .color(Spec.dropLight))
            let tip = CGRect(x: x - 0.9, y: rect.maxY - 3, width: 5.2, height: 5.2)
            canvas.fill(Path(ellipseIn: tip), with: .color(Spec.dropLight))
            canvas.fill(Path(ellipseIn: tip.insetBy(dx: 1.4, dy: 1.4).offsetBy(dx: -0.4, dy: -0.4)), with: .color(.white.opacity(0.85)))
        }
        for (index, heap) in Self.foamHeaps.enumerated() {
            let wobble = isAnimated ? sin(time * 3.2 + Double(index) * 1.7) * 0.7 : 0
            let radius = heap.radius * grown
            let centre = CGPoint(x: lid.minX + lid.width * heap.x, y: lid.minY + 1.5 - heap.climb * grown + CGFloat(wobble))
            let blob = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
            canvas.fill(Path(ellipseIn: blob), with: foamFill)
            canvas.stroke(Path(ellipseIn: blob), with: .color(streamColor.opacity(0.7)), lineWidth: 0.6)
            let glint = CGRect(x: centre.x - radius * 0.45, y: centre.y - radius * 0.55, width: radius * 0.4, height: radius * 0.3)
            canvas.fill(Path(ellipseIn: glint), with: .color(.white.opacity(0.9)))
        }
    }

    // MARK: - Can

    /// Fractions of the can's width and height: a lid about 76% of the body's width on a very short neck,
    /// short shoulders, a straight body and a slightly rounded, wider base.
    private func canSilhouette(_ size: CGSize) -> Path {
        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: -size.width + u * size.width, y: -size.height + v * size.height)
        }
        var path = Path()
        path.move(to: point(0.12, 0))
        path.addLine(to: point(0.88, 0))
        path.addLine(to: point(0.88, 0.02))
        path.addLine(to: point(0.92, 0.035))
        path.addCurve(to: point(1, 0.10), control1: point(0.99, 0.05), control2: point(1, 0.07))
        path.addLine(to: point(1, 0.93))
        path.addCurve(to: point(0.91, 1), control1: point(1, 0.98), control2: point(0.97, 1))
        path.addLine(to: point(0.09, 1))
        path.addCurve(to: point(0, 0.93), control1: point(0.03, 1), control2: point(0, 0.98))
        path.addLine(to: point(0, 0.10))
        path.addCurve(to: point(0.08, 0.035), control1: point(0, 0.07), control2: point(0.01, 0.05))
        path.addLine(to: point(0.12, 0.02))
        path.closeSubpath()
        return path
    }

    private func drawCan(in canvas: inout GraphicsContext) {
        let size = Spec.canSize
        var can = canvas
        can.translateBy(x: pivot.x, y: pivot.y)
        can.rotate(by: tilt)

        let body = canSilhouette(size)
        let rect = CGRect(x: -size.width, y: -size.height, width: size.width, height: size.height)
        var clipped = can
        clipped.clip(to: body)
        // Aluminium on the neck, shoulders and thin base rim; the navy sleeve between
        clipped.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.55, green: 0.59, blue: 0.64), location: 0),
                .init(color: Color(red: 0.91, green: 0.93, blue: 0.95), location: 0.25),
                .init(color: Color(red: 0.66, green: 0.70, blue: 0.75), location: 0.7),
                .init(color: Color(red: 0.43, green: 0.47, blue: 0.53), location: 1),
            ]),
            startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
        let sleeve = CGRect(x: rect.minX, y: rect.minY + size.height * 0.11, width: size.width, height: size.height * 0.835)
        clipped.fill(Path(sleeve), with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.13, green: 0.33, blue: 0.78), location: 0),
                .init(color: Theme.navy, location: 0.5),
                .init(color: Theme.navyDeep, location: 1),
            ]),
            startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
        clipped.fill(Path(CGRect(x: rect.minX, y: sleeve.minY, width: size.width, height: 1.2)), with: .color(Theme.volt))
        drawBolt(in: &clipped, sleeve: sleeve)
        // Cylinder shading, a thin bright stripe down the left and a faint one on the right
        clipped.fill(Path(rect), with: .linearGradient(
            Gradient(stops: [
                .init(color: .black.opacity(0.28), location: 0),
                .init(color: .clear, location: 0.18),
                .init(color: .clear, location: 0.72),
                .init(color: .black.opacity(0.34), location: 1),
            ]),
            startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
        let stripe = CGRect(x: rect.minX + size.width * 0.17, y: rect.minY + size.height * 0.14, width: size.width * 0.05, height: size.height * 0.78)
        clipped.fill(Path(roundedRect: stripe, cornerRadius: 1), with: .color(.white.opacity(0.55)))
        clipped.fill(Path(roundedRect: stripe.offsetBy(dx: size.width * 0.66, dy: 0).insetBy(dx: 0.3, dy: 6), cornerRadius: 1),
                     with: .color(.white.opacity(0.14)))
        can.stroke(body, with: .color(.black.opacity(0.4)), lineWidth: 0.7)
        drawLid(in: &can, size: size)
    }

    /// The lightning bolt of the can's emblem, as points in a unit box (y down).
    private static let boltUnit: [(CGFloat, CGFloat)] = [(0.62, 0), (0.12, 0.56), (0.45, 0.56), (0.36, 1), (0.90, 0.38), (0.55, 0.38)]

    private static func boltPath(in box: CGRect) -> Path {
        var path = Path()
        for (index, point) in boltUnit.enumerated() {
            let mapped = CGPoint(x: box.minX + point.0 * box.width, y: box.minY + point.1 * box.height)
            if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
        }
        path.closeSubpath()
        return path
    }

    private func drawBolt(in canvas: inout GraphicsContext, sleeve: CGRect) {
        let side = sleeve.width * 0.50
        let box = CGRect(x: sleeve.midX - side / 2 - 0.5, y: sleeve.midY - side * 0.62, width: side, height: side * 1.24)
        let bolt = Self.boltPath(in: box)
        var glow = canvas
        glow.addFilter(.blur(radius: 2.2))
        glow.fill(bolt, with: .color(Theme.volt.opacity(0.5)))
        canvas.fill(bolt, with: .linearGradient(
            Gradient(colors: [Spec.dropLight, Theme.volt, Spec.dropDark]),
            startPoint: CGPoint(x: box.minX, y: box.minY), endPoint: CGPoint(x: box.maxX, y: box.maxY)))
    }

    /// The lid seen a little from above: a silver ellipse with the pull-tab ring and, when pouring, the dark opening.
    private func drawLid(in canvas: inout GraphicsContext, size: CGSize) {
        func local(_ u: CGFloat) -> CGFloat { -size.width + u * size.width }
        let lid = CGRect(x: local(0.12), y: -size.height - 2.2, width: size.width * 0.76, height: 4.4)
        canvas.fill(Path(ellipseIn: lid), with: .linearGradient(
            Gradient(colors: [Color(red: 0.98, green: 0.99, blue: 1.0), Color(red: 0.62, green: 0.66, blue: 0.72)]),
            startPoint: CGPoint(x: lid.minX, y: lid.minY), endPoint: CGPoint(x: lid.maxX, y: lid.maxY)))
        canvas.stroke(Path(ellipseIn: lid), with: .color(.black.opacity(0.4)), lineWidth: 0.6)

        // Pull-tab ring, on the side away from the mouth
        let ring = CGRect(x: local(0.20), y: -size.height - 1.2, width: size.width * 0.22, height: 2.4)
        canvas.stroke(Path(ellipseIn: ring), with: .color(Color(red: 0.38, green: 0.42, blue: 0.48)), lineWidth: 1.1)
        canvas.stroke(Path(ellipseIn: ring.insetBy(dx: -0.4, dy: -0.4)), with: .color(.white.opacity(0.7)), lineWidth: 0.4)

        // The opening: a slit at rest, a wide dark ellipse with a lime glint while pouring
        let mouth = CGPoint(x: local(Spec.mouthU), y: -size.height)
        let width = size.width * (isPouring ? 0.19 : 0.10)
        let opening = CGRect(x: mouth.x - width / 2, y: mouth.y - (isPouring ? 1.3 : 0.6), width: width, height: isPouring ? 2.6 : 1.2)
        canvas.fill(Path(ellipseIn: opening), with: .color(Spec.navyInk.opacity(0.9)))
        if isPouring {
            canvas.fill(Path(ellipseIn: opening.insetBy(dx: width * 0.25, dy: 0.7)), with: .color(Theme.volt.opacity(0.85)))
        }
    }
}
