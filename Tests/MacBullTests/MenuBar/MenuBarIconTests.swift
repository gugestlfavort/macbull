import AppKit
import Testing
@testable import MacBull

@MainActor
struct MenuBarIconTests {
    // MARK: - State mapping

    @Test func nothingOnAndNoCutoffIsOff() {
        #expect(MenuBarIcon.State(AppState().menuIconBase) == .off)
    }

    @Test func manualOnIsOn() {
        let state = AppState()
        state.manual = ManualSession(minutes: 30, startedAt: Date(), endsAt: nil)
        #expect(MenuBarIcon.State(state.menuIconBase) == .on)
    }

    @Test func agentsAloneShowTheTippedCan() {
        let state = AppState()
        state.agentHold = true
        #expect(MenuBarIcon.State(state.menuIconBase) == .agents)
    }

    @Test func manualBeatsAgents() {
        let state = AppState()
        state.agentHold = true
        state.manual = ManualSession(minutes: 30, startedAt: Date(), endsAt: nil)
        #expect(MenuBarIcon.State(state.menuIconBase) == .on)
    }

    @Test func cutoffWhileAsleepIsCrushedAndForgottenOnceAwake() {
        let state = AppState()
        state.cutoff = .heat
        #expect(MenuBarIcon.State(state.menuIconBase) == .cutoff)
        state.cutoff = .battery
        #expect(MenuBarIcon.State(state.menuIconBase) == .cutoff)
        state.manual = ManualSession(minutes: 30, startedAt: Date(), endsAt: nil)
        #expect(MenuBarIcon.State(state.menuIconBase) == .on)
    }

    // MARK: - Images

    @Test func allStatesShareOneSizeAndAreTemplates() {
        for state in MenuBarIcon.State.allCases {
            let image = MenuBarIcon.image(state)
            #expect(image.size == MenuBarIcon.size, "\(state)")
            #expect(image.isTemplate, "\(state)")
        }
        #expect(MenuBarIcon.size.height <= 18)
    }

    @Test func transitionFramesEndExactlyOnTheTarget() {
        let from = MenuBarIcon.look(for: .off)
        let target = MenuBarIcon.look(for: .agents)
        let frames = MenuBarIcon.frames(from: from, to: target)
        #expect(frames.count == MenuBarIcon.Metrics.transitionFrames)
        #expect(frames.last == target)
        let rotations = frames.map(\.rotation)
        #expect(rotations == rotations.sorted(by: <), "the tilt only ever grows")
    }

    @Test func everyStateStaysInsideTheCanvas() throws {
        let badges: [MenuBarIcon.Badge?] = [nil, MenuBarIcon.Badge(text: nil), MenuBarIcon.Badge(text: "3"), MenuBarIcon.Badge(text: "9+")]
        for state in MenuBarIcon.State.allCases {
            for badge in badges {
                let bitmap = try IconBitmaps.bitmap(of: MenuBarIcon.image(state, badge: badge), scale: 4)
                let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
                let label = "\(state) with badge \(String(describing: badge))"
                for step in 0..<width {
                    #expect((bitmap.colorAt(x: step, y: 0)?.alphaComponent ?? 0) == 0, "\(label) touches the top edge")
                    #expect((bitmap.colorAt(x: step, y: height - 1)?.alphaComponent ?? 0) == 0, "\(label) touches the bottom edge")
                }
                for step in 0..<height {
                    #expect((bitmap.colorAt(x: 0, y: step)?.alphaComponent ?? 0) == 0, "\(label) touches the left edge")
                    #expect((bitmap.colorAt(x: width - 1, y: step)?.alphaComponent ?? 0) == 0, "\(label) touches the right edge")
                }
            }
        }
    }

    // MARK: - Badge

    @Test func badgeTextCapsAtNinePlus() {
        #expect((1...9).map { MenuBarIcon.badgeText(count: $0) } == ["1", "2", "3", "4", "5", "6", "7", "8", "9"])
        #expect(MenuBarIcon.badgeText(count: 10) == "9+")
        #expect(MenuBarIcon.badgeText(count: 250) == "9+")
    }

    @Test func badgeNeedsAWaitingSessionAndLosesToTheCutoffLook() {
        #expect(MenuBarIcon.badge(base: .off, waiting: 0, showCount: true) == nil)
        #expect(MenuBarIcon.badge(base: .on, waiting: 2, showCount: false) == MenuBarIcon.Badge(text: nil))
        #expect(MenuBarIcon.badge(base: .agents, waiting: 2, showCount: true) == MenuBarIcon.Badge(text: "2"))
        #expect(MenuBarIcon.badge(base: .off, waiting: 12, showCount: true) == MenuBarIcon.Badge(text: "9+"))
        #expect(MenuBarIcon.badge(base: .cutoff, waiting: 3, showCount: true) == nil)
    }

    @Test func badgeIsSolidAtTheTopRightAndCountIsKnockedOut() throws {
        let scale = 4
        let plain = try IconBitmaps.bitmap(of: MenuBarIcon.image(.off, badge: MenuBarIcon.Badge(text: nil)), scale: scale)
        let counted = try IconBitmaps.bitmap(of: MenuBarIcon.image(.off, badge: MenuBarIcon.Badge(text: "3")), scale: scale)
        // The dot's centre sits 3.6 pt in from the top right corner of the canvas (y counts from the top)
        let centreX = Int((18 - 0.4 - MenuBarIcon.Metrics.badgeDot / 2) * CGFloat(scale))
        let centreY = Int((0.4 + MenuBarIcon.Metrics.badgeDot / 2) * CGFloat(scale))
        #expect((plain.colorAt(x: centreX, y: centreY)?.alphaComponent ?? 0) > 0.9, "the plain badge is solid")
        // A counted badge has transparent pixels inside it (the digit), a plain one has none
        let countedBox = badgeBox(width: MenuBarIcon.Metrics.badgeDigitWidth, height: MenuBarIcon.Metrics.badgeHeight, scale: scale)
        let holes = transparentPixels(in: counted, box: countedBox, shrinkBy: 4)
        #expect(holes > 4, "the count is knocked out of the dot")
        let plainBox = badgeBox(width: MenuBarIcon.Metrics.badgeDot, height: MenuBarIcon.Metrics.badgeDot, scale: scale)
        #expect(transparentPixels(in: plain, box: plainBox, shrinkBy: 6) == 0)
    }

    @Test func badgeLeavesAGapAroundItselfInTheCan() throws {
        let scale = 4
        let plain = try IconBitmaps.bitmap(of: MenuBarIcon.image(.on), scale: scale)
        let badged = try IconBitmaps.bitmap(of: MenuBarIcon.image(.on, badge: MenuBarIcon.Badge(text: nil)), scale: scale)
        var cleared = 0
        for y in 0..<plain.pixelsHigh {
            for x in 0..<plain.pixelsWide {
                let before = plain.colorAt(x: x, y: y)?.alphaComponent ?? 0
                let after = badged.colorAt(x: x, y: y)?.alphaComponent ?? 0
                if before > 0.5, after < 0.1 { cleared += 1 }
            }
        }
        #expect(cleared > 0, "the badge knocks a ring out of the can so the two never merge")
    }

    private func badgeBox(width: CGFloat, height: CGFloat, scale: Int) -> (x: Range<Int>, y: Range<Int>) {
        let left = Int((18 - 0.4 - width) * CGFloat(scale))
        let right = Int((18 - 0.4) * CGFloat(scale))
        let top = Int(0.4 * CGFloat(scale))
        let bottom = Int((0.4 + height) * CGFloat(scale))
        return (left..<right, top..<bottom)
    }

    private func transparentPixels(in bitmap: NSBitmapImageRep, box: (x: Range<Int>, y: Range<Int>), shrinkBy margin: Int) -> Int {
        var count = 0
        for y in (box.y.lowerBound + margin)..<(box.y.upperBound - margin) {
            for x in (box.x.lowerBound + margin)..<(box.x.upperBound - margin) where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) < 0.1 {
                count += 1
            }
        }
        return count
    }

    // MARK: - Renders (only when MACBULL_RENDER_DIR is set)

    @Test func iconRenderPreviews() throws {
        guard let directory = ProcessInfo.processInfo.environment["MACBULL_RENDER_DIR"], !directory.isEmpty else { return }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let light = NSColor(white: 0.86, alpha: 1)
        let navy = NSColor(red: 0.04, green: 0.10, blue: 0.24, alpha: 1)
        let states = MenuBarIcon.State.allCases.map { MenuBarIcon.image($0) }
        let rows = [
            try IconBitmaps.sheet(states, scale: 4, ink: .black, background: light),
            try IconBitmaps.sheet(states, scale: 4, ink: .white, background: navy),
            try IconBitmaps.sheet(states, scale: 1, ink: .black, background: light, enlargedBy: 4),
        ]
        try IconBitmaps.write(IconBitmaps.stack(rows), to: folder.appendingPathComponent("menubar-states.png"))

        let from = MenuBarIcon.look(for: .off)
        let frames = MenuBarIcon.frames(from: from, to: MenuBarIcon.look(for: .agents))
        let strip = frames.map { MenuBarIcon.image($0) }
        try IconBitmaps.write(IconBitmaps.stack([
            try IconBitmaps.sheet([MenuBarIcon.image(from)] + strip, scale: 4, ink: .black, background: light),
            try IconBitmaps.sheet([MenuBarIcon.image(from)] + strip, scale: 4, ink: .white, background: navy),
        ]), to: folder.appendingPathComponent("menubar-transition.png"))

        // The Your Turn badge on each look: a plain dot, 1, 3, 9+; at 4x, 1x enlarged 4x, on dark
        let badges: [MenuBarIcon.Badge] = [MenuBarIcon.Badge(text: nil), MenuBarIcon.Badge(text: "1"), MenuBarIcon.Badge(text: "3"), MenuBarIcon.Badge(text: "9+")]
        let badged = [MenuBarIcon.State.off, .on, .agents].flatMap { state in badges.map { MenuBarIcon.image(state, badge: $0) } }
        try IconBitmaps.write(IconBitmaps.stack([
            try IconBitmaps.sheet(badged, scale: 4, ink: .black, background: light),
            try IconBitmaps.sheet(badged, scale: 4, ink: .white, background: navy),
            try IconBitmaps.sheet(badged, scale: 1, ink: .black, background: light, enlargedBy: 4),
            try IconBitmaps.sheet(badged, scale: 2, ink: .black, background: light, enlargedBy: 2),
        ]), to: folder.appendingPathComponent("menubar-badge.png"))
    }
}

/// Bitmap helpers for the icon tests and renders.
@MainActor
enum IconBitmaps {
    static let gutter = 6

    static func makeBitmap(width: Int, height: Int) throws -> NSBitmapImageRep {
        try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0))
    }

    static func draw(into bitmap: NSBitmapImageRep, _ body: () -> Void) throws {
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The image alone on a transparent background, `scale` pixels per point.
    static func bitmap(of image: NSImage, scale: Int) throws -> NSBitmapImageRep {
        let bitmap = try makeBitmap(width: Int(image.size.width) * scale, height: Int(image.size.height) * scale)
        try draw(into: bitmap) {
            image.draw(in: NSRect(origin: .zero, size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)))
        }
        return bitmap
    }

    /// A copy of the template in one flat colour, the way the menu bar tints it.
    static func tinted(_ image: NSImage, _ ink: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            ink.set()
            rect.fill(using: .sourceIn)
            return true
        }
    }

    /// The images side by side on a flat background. With `enlargedBy`, drawn at `scale` and then blown up
    /// without smoothing, so the pixels a 1x display would show can be seen.
    static func sheet(_ images: [NSImage], scale: Int, ink: NSColor, background: NSColor, enlargedBy zoom: Int = 1) throws -> NSBitmapImageRep {
        let cell = Int(MenuBarIcon.size.width) * scale
        let width = (cell + gutter * scale) * images.count + gutter * scale
        let height = cell + gutter * scale * 2
        let flat = try makeBitmap(width: width, height: height)
        try draw(into: flat) {
            background.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            for (index, image) in images.enumerated() {
                let x = gutter * scale + index * (cell + gutter * scale)
                tinted(image, ink).draw(in: NSRect(x: x, y: gutter * scale, width: cell, height: cell))
            }
        }
        guard zoom > 1 else { return flat }
        let big = try makeBitmap(width: width * zoom, height: height * zoom)
        try draw(into: big) {
            NSGraphicsContext.current?.imageInterpolation = .none
            image(of: flat).draw(in: NSRect(x: 0, y: 0, width: width * zoom, height: height * zoom))
        }
        return big
    }

    static func image(of bitmap: NSBitmapImageRep) -> NSImage {
        let image = NSImage(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        image.addRepresentation(bitmap)
        return image
    }

    static func stack(_ rows: [NSBitmapImageRep]) throws -> NSBitmapImageRep {
        let width = rows.map(\.pixelsWide).max() ?? 0
        let height = rows.map(\.pixelsHigh).reduce(0, +)
        let bitmap = try makeBitmap(width: width, height: height)
        try draw(into: bitmap) {
            var top = height
            for row in rows {
                top -= row.pixelsHigh
                image(of: row).draw(in: NSRect(x: 0, y: top, width: row.pixelsWide, height: row.pixelsHigh))
            }
        }
        return bitmap
    }

    static func write(_ bitmap: NSBitmapImageRep, to url: URL) throws {
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
