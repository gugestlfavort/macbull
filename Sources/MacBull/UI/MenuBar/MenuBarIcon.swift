import AppKit
import CoreText

/// The menu bar icon: a can seen as a cylinder from slightly above (the lid is a full ellipse with the
/// pull-tab on it, the base is a curved arc), always leaning a little so it never reads as a battery.
/// Each state has its own shape, not just a fill: off is an outline, on is solid with the lid ring, tab and
/// an energy stripe knocked out, agents is solid and tipped with drops falling from the mouth, cutoff is a
/// crushed outline with creases. A template image, so macOS tints it for light, dark and the selected state.
///
/// Everything is drawn from a `Look`, a handful of numbers (tilt, fill, squash ...). A state is one fixed
/// look; a transition is a run of looks in between, drawn by the same code.
enum MenuBarIcon {
    enum State: CaseIterable, Equatable {
        case off, on, agents, cutoff

        /// The contract's base look maps one to one onto a drawn state.
        init(_ base: MenuIconBase) {
            switch base {
            case .off: self = .off
            case .on: self = .on
            case .agents: self = .agents
            case .cutoff: self = .cutoff
            }
        }
    }

    /// The Your Turn badge: a filled dot at the top right, with the count inside when there is text.
    struct Badge: Equatable {
        var text: String?
    }

    /// The badge for a base look. It outranks every look except the cutoff one, and is gone with no waiting session.
    static func badge(base: MenuIconBase, waiting: Int, showCount: Bool) -> Badge? {
        guard base != .cutoff, waiting > 0 else { return nil }
        return Badge(text: showCount ? badgeText(count: waiting) : nil)
    }

    /// 1 to 9, then "9+".
    static func badgeText(count: Int) -> String {
        count > 9 ? "9+" : "\(max(count, 1))"
    }

    /// Apple's own menu bar icons are at most 18 pt tall. All four states share this size, so the
    /// status item never changes width.
    static let size = NSSize(width: 18, height: 18)

    /// One instant of the icon. Every field is a plain number, so two looks can be mixed.
    struct Look: Equatable {
        /// Clockwise degrees: about 12 leaning right, 120 tipped with the mouth down and to the right.
        var rotation: CGFloat
        /// 0 outline only, 1 solid. Rises from the base.
        var fill: CGFloat
        /// 0 intact, 1 crushed (pinched waist, shorter, creases).
        var squash: CGFloat
        /// 0 nothing, 1 three drops below the mouth.
        var stream: CGFloat
        /// Size of the pull-tab and rivet on the lid.
        var tab: CGFloat
        /// Size of the energy stripe across the body.
        var stripe: CGFloat

        func mixed(with other: Look, by amount: CGFloat) -> Look {
            func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * amount }
            return Look(rotation: mix(rotation, other.rotation), fill: mix(fill, other.fill), squash: mix(squash, other.squash),
                        stream: mix(stream, other.stream), tab: mix(tab, other.tab), stripe: mix(stripe, other.stripe))
        }
    }

    static func look(for state: State) -> Look {
        switch state {
        case .off: Look(rotation: Metrics.leanRotation, fill: 0, squash: 0, stream: 0, tab: 1, stripe: 1)
        case .on: Look(rotation: Metrics.leanRotation, fill: 1, squash: 0, stream: 0, tab: 1, stripe: 1)
        case .agents: Look(rotation: Metrics.tippedRotation, fill: 1, squash: 0, stream: 1, tab: 0, stripe: 1)
        case .cutoff: Look(rotation: Metrics.crushedLean, fill: 0, squash: 1, stream: 0, tab: 0, stripe: 0)
        }
    }

    static func image(_ state: State, badge: Badge? = nil) -> NSImage {
        image(look(for: state), badge: badge)
    }

    static func image(_ look: Look, badge: Badge? = nil) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw(look)
            if let badge { drawBadge(badge) }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The looks between two others, eased, the last one exactly `to`. At least one.
    static func frames(from: Look, to: Look, count: Int = Metrics.transitionFrames) -> [Look] {
        let total = max(count, 1)
        return (1...total).map { index in
            let progress = CGFloat(index) / CGFloat(total)
            return from.mixed(with: to, by: progress * progress * (3 - 2 * progress))
        }
    }

    // MARK: - Metrics

    /// Sizes in points on the 18 pt canvas.
    enum Metrics {
        static let transitionFrames = 8
        /// Whole transition, so one frame lasts a seventh of it (the first frame shows at once).
        static let transitionDuration: TimeInterval = 0.35

        static let canWidth: CGFloat = 9.0
        static let canHeight: CGFloat = 14.6
        static let outline: CGFloat = 1.2
        /// Half the lid ellipse's height: the "from above" angle. A flat lid is what makes a battery.
        static let lidRadiusY: CGFloat = 1.65
        /// Thickness of the lid's front edge.
        static let crescent: CGFloat = 0.8
        static let profileSteps = 40

        /// Upright states lean right, tipped is the agents pose, crushed leans the other way.
        static let leanRotation: CGFloat = 12
        static let tippedRotation: CGFloat = 120
        static let crushedLean: CGFloat = -20
        static let crushedHeight: CGFloat = 0.84
        static let pinchDepth: CGFloat = 0.45
        static let pinchCentre: CGFloat = 0.50
        static let pinchSpread: CGFloat = 0.25
        /// The right flank gives way less than the left, so it reads as crushed and not as an hourglass.
        static let rightPinchShare: CGFloat = 0.60
        /// Slants the lid, as if its top corner was pressed down.
        static let lidSlant: CGFloat = 1.2
        /// Two creases above and below the waist, where the can is still wide enough for a zigzag.
        static let creaseDepths: [CGFloat] = [0.25, 0.75]
        static let creaseCorners = 3
        static let creaseZig: CGFloat = 0.6
        static let creaseThickness: CGFloat = 0.85
        static let creaseMargin: CGFloat = 1.0

        static let tippedScale: CGFloat = 0.86
        /// Where the can's centre sits on the canvas, leaning and tipped: the tipped can moves up and left
        /// to leave room for the drops under its mouth.
        static let uprightCentre = CGPoint(x: 9, y: 9)
        static let tippedCentre = CGPoint(x: 7.6, y: 10.4)

        static let tabSize = CGSize(width: 2.4, height: 0.95)
        static let tabCentreX: CGFloat = 0.7
        static let rivetRadius: CGFloat = 0.45
        static let rivetCentreX: CGFloat = -1.6

        static let stripeHalfHeight: CGFloat = 2.3
        static let stripeReach: CGFloat = 1.9
        static let stripeThickness: CGFloat = 1.1

        /// Drops below the mouth: distance under it, sideways drift, radius. Over 1.5 pt wide, to show at 1x.
        static let drops: [(down: CGFloat, drift: CGFloat, radius: CGFloat)] = [(3.0, 0.1, 1.2), (6.0, 0.2, 1.0)]

        /// Your Turn badge. A plain dot is 6.4 pt, a counted one 8.4 pt tall so a digit stays legible at 1x.
        static let badgeDot: CGFloat = 6.4
        static let badgeHeight: CGFloat = 8.4
        static let badgeDigitWidth: CGFloat = 8.4
        static let badgeWideWidth: CGFloat = 10.8
        static let badgeFontSize: CGFloat = 7.4
        /// Gap knocked out of the can around the badge, so the badge never merges with it.
        static let badgeHalo: CGFloat = 1.3
        /// Distance of the badge from the canvas edge.
        static let badgeInset: CGFloat = 0.4
    }

    // MARK: - Geometry (local: can centre at the origin, y up)

    private static var bodyHalf: CGFloat { (Metrics.canWidth - Metrics.outline) / 2 }

    private static func height(_ look: Look) -> CGFloat {
        let intact = Metrics.canHeight - Metrics.outline
        return intact * (1 - (1 - Metrics.crushedHeight) * look.squash)
    }

    /// Where the straight sides start and end: the centres of the lid ellipse and of the base arc.
    private static func sideRange(_ look: Look) -> (top: CGFloat, bottom: CGFloat) {
        let tall = height(look)
        return (tall / 2 - Metrics.lidRadiusY, -tall / 2 + Metrics.lidRadiusY)
    }

    /// Half width (left, right) along the sides, `s` from 0 at the lid to 1 at the base.
    private static func sideHalves(at s: CGFloat, look: Look) -> (left: CGFloat, right: CGFloat) {
        let spread = (s - Metrics.pinchCentre) / Metrics.pinchSpread
        let pinch = look.squash * Metrics.pinchDepth * exp(-spread * spread)
        return (bodyHalf * (1 - pinch), bodyHalf * (1 - pinch * Metrics.rightPinchShare))
    }

    private static func sideY(_ s: CGFloat, look: Look) -> CGFloat {
        let range = sideRange(look)
        return range.top + (range.bottom - range.top) * s
    }

    /// The lid's high corner stays, the other is pressed down; it fades out down the side.
    private static func lidDrop(_ unitX: CGFloat, s: CGFloat, look: Look) -> CGFloat {
        -look.squash * Metrics.lidSlant * 0.5 * unitX * max(1 - s * 4, 0)
    }

    private static func canPath(_ look: Look) -> NSBezierPath {
        let range = sideRange(look)
        let steps = Metrics.profileSteps
        let unit = (0...steps).map { CGFloat($0) / CGFloat(steps) }
        let path = NSBezierPath()
        // Over the top of the lid, left to right
        for (index, t) in unit.enumerated() {
            let angle = CGFloat.pi * (1 - t)
            let point = NSPoint(x: bodyHalf * cos(angle),
                                y: range.top + Metrics.lidRadiusY * sin(angle) + lidDrop(cos(angle), s: 0, look: look))
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        for s in unit {
            path.line(to: NSPoint(x: sideHalves(at: s, look: look).right, y: sideY(s, look: look) + lidDrop(1, s: s, look: look)))
        }
        // Under the base, right to left
        for t in unit {
            let angle = -CGFloat.pi * t
            path.line(to: NSPoint(x: bodyHalf * cos(angle), y: range.bottom + Metrics.lidRadiusY * sin(angle)))
        }
        for s in unit.reversed() {
            path.line(to: NSPoint(x: -sideHalves(at: s, look: look).left, y: sideY(s, look: look) + lidDrop(-1, s: s, look: look)))
        }
        path.close()
        return path
    }

    /// Everything that is black on an outline and a hole in a solid can: the front edge of the lid, the pull-tab
    /// with its rivet, and the energy stripe.
    private static func detailPath(_ look: Look) -> NSBezierPath {
        let path = NSBezierPath()
        let range = sideRange(look)
        let unit = (0...Metrics.profileSteps).map { CGFloat($0) / CGFloat(Metrics.profileSteps) }
        let innerRadius = Metrics.lidRadiusY - Metrics.crescent

        // The lid's front edge, a crescent between two arcs
        for (index, t) in unit.enumerated() {
            let angle = -CGFloat.pi * t
            let point = NSPoint(x: bodyHalf * cos(angle),
                                y: range.top + Metrics.lidRadiusY * sin(angle) + lidDrop(cos(angle), s: 0, look: look))
            if index == 0 { path.move(to: point) } else { path.line(to: point) }
        }
        for t in unit.reversed() {
            let angle = -CGFloat.pi * t
            path.line(to: NSPoint(x: bodyHalf * cos(angle), y: range.top + innerRadius * sin(angle) + lidDrop(cos(angle), s: 0, look: look)))
        }
        path.close()

        if look.tab > 0.05 {
            let size = CGSize(width: Metrics.tabSize.width * look.tab, height: Metrics.tabSize.height * look.tab)
            let lidY = range.top + Metrics.crescent / 2
            let pill = CGRect(x: Metrics.tabCentreX - size.width / 2, y: lidY - size.height / 2, width: size.width, height: size.height)
            path.append(NSBezierPath(roundedRect: pill, xRadius: size.height / 2, yRadius: size.height / 2))
            let dot = Metrics.rivetRadius * look.tab
            path.append(NSBezierPath(ovalIn: CGRect(x: Metrics.rivetCentreX - dot, y: lidY - dot, width: dot * 2, height: dot * 2)))
        }

        if look.stripe > 0.05 {
            let middle = (range.top - Metrics.lidRadiusY + range.bottom) / 2 - 0.2
            let halfHeight = Metrics.stripeHalfHeight * look.stripe
            let reach = Metrics.stripeReach * look.stripe
            let half = Metrics.stripeThickness / 2
            path.move(to: NSPoint(x: -reach - half, y: middle - halfHeight))
            path.line(to: NSPoint(x: -reach + half, y: middle - halfHeight))
            path.line(to: NSPoint(x: reach + half, y: middle + halfHeight))
            path.line(to: NSPoint(x: reach - half, y: middle + halfHeight))
            path.close()
        }
        return path
    }

    /// Zigzag creases across the waist of a crushed can.
    private static func creasePath(_ look: Look) -> NSBezierPath {
        let path = NSBezierPath()
        guard look.squash > 0.2 else { return path }
        let corners = Metrics.creaseCorners
        for depth in Metrics.creaseDepths {
            let sides = sideHalves(at: depth, look: look)
            let reach = min(sides.left, sides.right) - Metrics.creaseMargin
            guard reach > 0 else { continue }
            let y = sideY(depth, look: look)
            let zig = Metrics.creaseZig * look.squash
            for step in 0...corners {
                let x = -reach + reach * 2 * CGFloat(step) / CGFloat(corners)
                let point = NSPoint(x: x, y: step.isMultiple(of: 2) ? y - zig : y + zig)
                if step == 0 { path.move(to: point) } else { path.line(to: point) }
            }
        }
        return path
    }

    // MARK: - Placement

    /// 0 while leaning or crushed, 1 fully tipped.
    private static func tip(_ look: Look) -> CGFloat {
        min(max((look.rotation - Metrics.leanRotation) / (Metrics.tippedRotation - Metrics.leanRotation), 0), 1)
    }

    private static func scale(_ look: Look) -> CGFloat {
        1 + (Metrics.tippedScale - 1) * tip(look)
    }

    /// Local can coordinates to the canvas: scale, tip about the centre, then move.
    private static func placement(_ look: Look) -> AffineTransform {
        let amount = tip(look)
        let centre = CGPoint(x: Metrics.uprightCentre.x + (Metrics.tippedCentre.x - Metrics.uprightCentre.x) * amount,
                             y: Metrics.uprightCentre.y + (Metrics.tippedCentre.y - Metrics.uprightCentre.y) * amount)
        var transform = AffineTransform()
        transform.translate(x: centre.x, y: centre.y)
        transform.rotate(byDegrees: -look.rotation)
        transform.scale(scale(look))
        return transform
    }

    // MARK: - Drawing

    private static func draw(_ look: Look) {
        NSColor.black.set()
        let transform = placement(look)
        let tall = height(look)
        let outline = canPath(look)
        outline.lineWidth = Metrics.outline / scale(look)
        outline.lineJoinStyle = .round
        let details = detailPath(look)
        let creases = creasePath(look)
        creases.lineWidth = Metrics.creaseThickness / scale(look)
        creases.lineJoinStyle = .round

        NSGraphicsContext.saveGraphicsState()
        NSAffineTransform(transform: transform).concat()

        // Solid part, rising from the base, with the details as holes
        let reach = Metrics.canWidth
        let floor = -tall / 2 - Metrics.outline
        let waterline = floor + look.fill * (tall + Metrics.outline * 2)
        if look.fill > 0.001 {
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            NSBezierPath(rect: CGRect(x: -reach, y: floor, width: reach * 2, height: waterline - floor)).addClip()
            let solid = NSBezierPath()
            solid.append(outline)
            solid.append(details)
            solid.windingRule = .evenOdd
            solid.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        // Details above the waterline stay black
        if look.fill < 0.999 {
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            NSBezierPath(rect: CGRect(x: -reach, y: waterline, width: reach * 2, height: tall + Metrics.outline * 2)).addClip()
            details.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        outline.stroke()
        creases.stroke()
        NSGraphicsContext.restoreGraphicsState()

        drawDrops(look, transform: transform)
    }

    /// Drops fall straight down from the mouth, whatever the can's tilt.
    private static func drawDrops(_ look: Look, transform: AffineTransform) {
        guard look.stream > 0.02 else { return }
        let mouth = transform.transform(NSPoint(x: 0, y: sideRange(look).top))
        for (index, drop) in Metrics.drops.enumerated() {
            let grown = min(max(look.stream * CGFloat(Metrics.drops.count) - CGFloat(index), 0), 1)
            guard grown > 0.05 else { continue }
            let radius = drop.radius * grown
            let centre = CGPoint(x: mouth.x + drop.drift, y: mouth.y - drop.down)
            NSBezierPath(ovalIn: CGRect(x: centre.x - radius * 0.9, y: centre.y - radius * 1.1, width: radius * 1.8, height: radius * 2.2)).fill()
        }
    }

    // MARK: - Badge

    private static func badgeRect(_ badge: Badge) -> CGRect {
        let width: CGFloat
        let height: CGFloat
        switch badge.text {
        case nil:
            width = Metrics.badgeDot
            height = Metrics.badgeDot
        case let text? where text.count > 1:
            width = Metrics.badgeWideWidth
            height = Metrics.badgeHeight
        default:
            width = Metrics.badgeDigitWidth
            height = Metrics.badgeHeight
        }
        return CGRect(x: size.width - Metrics.badgeInset - width, y: size.height - Metrics.badgeInset - height,
                      width: width, height: height)
    }

    /// The outline of a string's glyphs, centred on a point. Used as a hole in the badge, so the count is
    /// knocked out of the dot the way the can's details are.
    private static func glyphPath(_ text: String, centredOn centre: CGPoint) -> NSBezierPath {
        let font = NSFont.systemFont(ofSize: Metrics.badgeFontSize, weight: .heavy) as CTFont
        let characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count) else { return NSBezierPath() }
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, glyphs.count)
        let combined = CGMutablePath()
        var x: CGFloat = 0
        for (glyph, advance) in zip(glyphs, advances) {
            if let outline = CTFontCreatePathForGlyph(font, glyph, nil) {
                combined.addPath(outline, transform: CGAffineTransform(translationX: x, y: 0))
            }
            x += advance.width
        }
        let bounds = combined.boundingBoxOfPath
        guard !bounds.isNull else { return NSBezierPath() }
        let move = CGAffineTransform(translationX: centre.x - bounds.midX, y: centre.y - bounds.midY)
        return NSBezierPath(cgPath: combined.copy(using: [move]) ?? combined)
    }

    private static func drawBadge(_ badge: Badge) {
        let rect = badgeRect(badge)
        let halo = rect.insetBy(dx: -Metrics.badgeHalo, dy: -Metrics.badgeHalo)
        let context = NSGraphicsContext.current
        context?.saveGraphicsState()
        context?.compositingOperation = .clear
        NSBezierPath(roundedRect: halo, xRadius: halo.height / 2, yRadius: halo.height / 2).fill()
        context?.restoreGraphicsState()

        NSColor.black.set()
        let dot = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        if let text = badge.text {
            dot.append(glyphPath(text, centredOn: CGPoint(x: rect.midX, y: rect.midY)))
            dot.windingRule = .evenOdd
        }
        dot.fill()
    }
}
