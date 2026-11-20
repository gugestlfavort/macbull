// Draws the MacBull app icon: the energy can, slightly tilted, on a navy-to-blue rounded square.
// AppKit and CoreGraphics only. Run from the repo root:
//   swift scripts/make-icon.swift Resources/AppIcon.png
import AppKit

let canvasSize = 1024
// macOS icon grid: an 824 pt rounded square centred in the 1024 pt canvas
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185

// Palette, the same as Theme.swift
let navy = NSColor(red: 0.043, green: 0.122, blue: 0.302, alpha: 1)
let navyDeep = NSColor(red: 0.024, green: 0.071, blue: 0.200, alpha: 1)
let electric = NSColor(red: 0.12, green: 0.40, blue: 1.0, alpha: 1)
let volt = NSColor(red: 0.84, green: 0.95, blue: 0.20, alpha: 1)

func gray(_ value: CGFloat, alpha: CGFloat = 1) -> NSColor {
    NSColor(white: value, alpha: alpha)
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: r, green: g, blue: b, alpha: a)
}

/// The can in its own space: width `canWidth`, height `canHeight`, origin in the middle, y up.
let canWidth: CGFloat = 270
let canHeight: CGFloat = 648

/// A point on the can from fractions of its width (0 left ... 1 right) and height (0 top ... 1 bottom).
func p(_ fx: CGFloat, _ fy: CGFloat) -> NSPoint {
    NSPoint(x: (fx - 0.5) * canWidth, y: (0.5 - fy) * canHeight)
}

func rect(_ fx0: CGFloat, _ fy0: CGFloat, _ fx1: CGFloat, _ fy1: CGFloat) -> NSRect {
    let a = p(fx0, fy1), b = p(fx1, fy0)
    return NSRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
}

func silhouette() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: p(0.10, 0.012))
    path.line(to: p(0.90, 0.012))
    path.line(to: p(0.90, 0.04))
    path.curve(to: p(1, 0.11), controlPoint1: p(0.90, 0.075), controlPoint2: p(1, 0.07))
    path.line(to: p(1, 0.90))
    path.curve(to: p(0.92, 0.965), controlPoint1: p(1, 0.935), controlPoint2: p(0.97, 0.955))
    path.line(to: p(0.92, 0.99))
    path.curve(to: p(0.90, 1), controlPoint1: p(0.92, 0.997), controlPoint2: p(0.915, 1))
    path.line(to: p(0.10, 1))
    path.curve(to: p(0.08, 0.99), controlPoint1: p(0.085, 1), controlPoint2: p(0.08, 0.997))
    path.line(to: p(0.08, 0.965))
    path.curve(to: p(0, 0.90), controlPoint1: p(0.03, 0.955), controlPoint2: p(0, 0.935))
    path.line(to: p(0, 0.11))
    path.curve(to: p(0.10, 0.04), controlPoint1: p(0, 0.07), controlPoint2: p(0.10, 0.075))
    path.close()
    return path
}

/// A horizontal gradient across the can (left to right).
func fillAcross(_ area: NSRect, _ stops: [(NSColor, CGFloat)]) {
    let gradient = NSGradient(colors: stops.map(\.0), atLocations: stops.map(\.1), colorSpace: .deviceRGB)
    gradient?.draw(in: area, angle: 0)
}

/// A vertical gradient (top to bottom).
func fillDown(_ area: NSRect, _ colors: [NSColor]) {
    NSGradient(colors: colors)?.draw(in: area, angle: -90)
}

func drawAluminium() {
    let area = rect(0, 0, 1, 1)
    fillAcross(area, [
        (rgb(0.55, 0.59, 0.64), 0), (rgb(0.91, 0.93, 0.95), 0.2), (rgb(0.76, 0.79, 0.83), 0.45),
        (rgb(0.66, 0.70, 0.75), 0.75), (rgb(0.43, 0.47, 0.53), 1),
    ])
    // Brushed grain
    var y = area.minY
    var index = 0
    while y < area.maxY {
        let strength = abs(sin(Double(index) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
        (index.isMultiple(of: 2) ? gray(1, alpha: 0.05 + strength * 0.10) : gray(0, alpha: 0.05 + strength * 0.10)).setFill()
        NSBezierPath(rect: NSRect(x: area.minX, y: y, width: area.width, height: 1.1)).fill()
        y += 3
        index += 1
    }
}

func drawSleeve() {
    let sleeve = rect(0, 0.115, 1, 0.885)
    fillAcross(sleeve, [
        (rgb(0.13, 0.33, 0.78), 0), (rgb(0.07, 0.20, 0.50), 0.28), (navy, 0.62), (navyDeep, 1),
    ])
    let streak = NSBezierPath()
    streak.move(to: p(0, 0.74))
    streak.line(to: p(1, 0.60))
    streak.line(to: p(1, 0.66))
    streak.line(to: p(0, 0.80))
    streak.close()
    electric.withAlphaComponent(0.45).setFill()
    streak.fill()
    volt.setFill()
    NSBezierPath(rect: NSRect(x: sleeve.minX, y: sleeve.maxY - 3.4, width: sleeve.width, height: 3.4)).fill()
    NSBezierPath(rect: NSRect(x: sleeve.minX, y: sleeve.minY, width: sleeve.width, height: 3.4)).fill()
}

func applePath(in box: NSRect) -> NSBezierPath {
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: box.minX + x * box.width, y: box.maxY - y * box.height)
    }
    let path = NSBezierPath()
    path.move(to: pt(0.50, 0.36))
    path.curve(to: pt(0.03, 0.60), controlPoint1: pt(0.44, 0.10), controlPoint2: pt(0.03, 0.12))
    path.curve(to: pt(0.50, 0.97), controlPoint1: pt(0.03, 0.84), controlPoint2: pt(0.28, 1.0))
    path.curve(to: pt(0.97, 0.60), controlPoint1: pt(0.72, 1.0), controlPoint2: pt(0.97, 0.84))
    path.curve(to: pt(0.50, 0.36), controlPoint1: pt(0.97, 0.12), controlPoint2: pt(0.56, 0.10))
    path.close()
    return path
}

func drawEmblem() {
    let side = canWidth * 0.46
    let center = p(0.47, 0.34)
    let box = NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: box.minX + x * box.width, y: box.maxY - y * box.height)
    }

    // Glow, then the fruit
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = volt.withAlphaComponent(0.7)
    glow.shadowBlurRadius = 26
    glow.shadowOffset = .zero
    glow.set()
    volt.setFill()
    applePath(in: box).fill()
    NSGraphicsContext.restoreGraphicsState()

    let leaf = NSBezierPath()
    leaf.move(to: pt(0.50, 0.20))
    leaf.curve(to: pt(0.12, 0.02), controlPoint1: pt(0.44, 0.04), controlPoint2: pt(0.26, 0.0))
    leaf.curve(to: pt(0.50, 0.20), controlPoint1: pt(0.14, 0.20), controlPoint2: pt(0.34, 0.26))
    leaf.close()
    rgb(0.45, 0.82, 0.20).setFill()
    leaf.fill()

    let stem = NSBezierPath()
    stem.move(to: pt(0.50, 0.38))
    stem.curve(to: pt(0.55, 0.08), controlPoint1: pt(0.47, 0.26), controlPoint2: pt(0.50, 0.16))
    stem.lineWidth = side * 0.075
    stem.lineCapStyle = .round
    rgb(0.72, 0.80, 0.22).setStroke()
    stem.stroke()

    NSGraphicsContext.saveGraphicsState()
    applePath(in: box).addClip()
    NSGradient(colors: [rgb(0.93, 1.0, 0.45), volt, rgb(0.62, 0.84, 0.10)])?.draw(in: box, angle: -45)
    NSGraphicsContext.restoreGraphicsState()

    // The bolt
    let boltBox = box.insetBy(dx: box.width * 0.30, dy: box.height * 0.28).offsetBy(dx: 0, dy: -box.height * 0.08)
    let unit: [(CGFloat, CGFloat)] = [(0.62, 0), (0.12, 0.56), (0.45, 0.56), (0.36, 1), (0.90, 0.38), (0.55, 0.38)]
    let bolt = NSBezierPath()
    for (index, point) in unit.enumerated() {
        let mapped = NSPoint(x: boltBox.minX + point.0 * boltBox.width, y: boltBox.maxY - point.1 * boltBox.height)
        if index == 0 { bolt.move(to: mapped) } else { bolt.line(to: mapped) }
    }
    bolt.close()
    navyDeep.setFill()
    bolt.fill()
}

func drawWindow(level: CGFloat) {
    let slot = rect(0.74, 0.17, 0.91, 0.85)
    let radius = slot.width / 2
    let bezel = NSBezierPath(roundedRect: slot.insetBy(dx: -6, dy: -6), xRadius: radius + 6, yRadius: radius + 6)
    NSGradient(colors: [rgb(0.55, 0.59, 0.65), rgb(0.92, 0.94, 0.97)])?.draw(in: bezel, angle: 45)
    let recess = NSBezierPath(roundedRect: slot, xRadius: radius, yRadius: radius)
    navyDeep.setFill()
    recess.fill()

    NSGraphicsContext.saveGraphicsState()
    recess.addClip()
    let inner = slot.insetBy(dx: 4.5, dy: 4.5)
    let top = inner.minY + inner.height * level
    let drink = NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: top - inner.minY)
    fillDown(drink, [rgb(0.93, 1.0, 0.40), volt, rgb(0.55, 0.80, 0.08)])
    gray(1, alpha: 0.65).setFill()
    NSBezierPath(rect: NSRect(x: inner.minX, y: top - 4, width: inner.width, height: 5)).fill()
    // Bubbles
    let bubbles: [(CGFloat, CGFloat, CGFloat)] = [(0.30, 0.10, 6), (0.66, 0.24, 4.5), (0.45, 0.40, 7), (0.25, 0.58, 4), (0.70, 0.72, 6), (0.50, 0.88, 4.5)]
    for (fx, fy, r) in bubbles {
        let center = NSPoint(x: inner.minX + inner.width * fx, y: inner.minY + 8 + (top - inner.minY - 16) * fy)
        let dot = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        gray(1, alpha: 0.85).setFill()
        dot.fill()
        navyDeep.withAlphaComponent(0.35).setStroke()
        dot.lineWidth = 1.5
        dot.stroke()
    }
    // Shade at the top, glint down the left
    NSGradient(colors: [gray(0, alpha: 0.45), gray(0, alpha: 0)])?.draw(in: NSRect(x: slot.minX, y: slot.maxY - 18, width: slot.width, height: 18), angle: -90)
    gray(1, alpha: 0.30).setFill()
    NSBezierPath(rect: NSRect(x: slot.minX + 5, y: slot.minY + 12, width: 5, height: slot.height - 24)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Gauge ticks to the left
    gray(1, alpha: 0.55).setFill()
    for fraction in [0.25, 0.5, 0.75] as [CGFloat] {
        let y = slot.minY + slot.height * fraction
        NSBezierPath(rect: NSRect(x: slot.minX - 30, y: y - 2, width: fraction == 0.5 ? 18 : 12, height: 4)).fill()
    }
}

func drawLidAndBase() {
    let rim = rect(0.10, 0.012, 0.90, 0.04)
    NSGradient(colors: [rgb(0.98, 0.99, 1.0), rgb(0.62, 0.66, 0.72)])?.draw(in: NSBezierPath(roundedRect: rim, xRadius: 5, yRadius: 5), angle: -90)
    gray(0, alpha: 0.25).setFill()
    NSBezierPath(rect: NSRect(x: rect(0, 0, 1, 1).minX, y: rim.minY - 3, width: canWidth, height: 3)).fill()
    let base = rect(0, 0.935, 1, 1)
    fillDown(base, [rgb(0.80, 0.83, 0.87), rgb(0.40, 0.44, 0.50)])
    gray(0, alpha: 0.3).setFill()
    NSBezierPath(rect: NSRect(x: base.minX, y: base.maxY - 3, width: base.width, height: 3)).fill()
}

func drawCylinderShading() {
    let area = rect(0, 0, 1, 1)
    fillAcross(area, [(gray(0, alpha: 0.28), 0), (gray(0, alpha: 0), 0.14), (gray(0, alpha: 0), 0.72), (gray(0, alpha: 0.34), 1)])
    let highlight = rect(0.12, 0.13, 0.18, 0.87)
    NSGradient(colors: [gray(1, alpha: 0), gray(1, alpha: 0.42), gray(1, alpha: 0)])?
        .draw(in: NSBezierPath(roundedRect: highlight, xRadius: 6, yRadius: 6), angle: 90)
}

func drawPullTab() {
    let tab = rect(0.31, 0, 0.65, 0.026)
    let shape = NSBezierPath(roundedRect: tab, xRadius: tab.height / 2, yRadius: tab.height / 2)
    NSGradient(colors: [rgb(0.66, 0.70, 0.76), rgb(0.98, 0.99, 1.0)])?.draw(in: shape, angle: 90)
    gray(0, alpha: 0.35).setStroke()
    shape.lineWidth = 2
    shape.stroke()
    gray(0, alpha: 0.45).setFill()
    NSBezierPath(ovalIn: NSRect(x: tab.minX + tab.width * 0.14, y: tab.midY - tab.height * 0.22, width: tab.width * 0.34, height: tab.height * 0.44)).fill()
}

func drawCan() {
    // Shadow on the tile
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = gray(0, alpha: 0.5)
    shadow.shadowBlurRadius = 36
    shadow.shadowOffset = NSSize(width: 14, height: -26)
    shadow.set()
    gray(0, alpha: 1).setFill()
    silhouette().fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    silhouette().addClip()
    drawAluminium()
    drawSleeve()
    drawEmblem()
    drawWindow(level: 0.62)
    drawLidAndBase()
    drawCylinderShading()
    NSGraphicsContext.restoreGraphicsState()
    gray(0, alpha: 0.35).setStroke()
    let outline = silhouette()
    outline.lineWidth = 2.5
    outline.stroke()
    drawPullTab()
}

func drawTile() {
    let shape = NSBezierPath(roundedRect: tile, xRadius: tileRadius, yRadius: tileRadius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = gray(0, alpha: 0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    navy.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [navyDeep, navy, rgb(0.10, 0.28, 0.80)], atLocations: [0, 0.45, 1], colorSpace: .deviceRGB)?
        .draw(in: tile, angle: -60)
    // A soft electric blue glow behind the can
    NSGradient(colors: [rgb(0.35, 0.60, 1.0, 0.38), rgb(0.35, 0.60, 1.0, 0)])?
        .draw(fromCenter: NSPoint(x: tile.midX, y: tile.midY), radius: 0, toCenter: NSPoint(x: tile.midX, y: tile.midY), radius: 380, options: [])
    // A light edge along the top of the tile
    gray(1, alpha: 0.10).setStroke()
    shape.lineWidth = 3
    shape.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: canvasSize, pixelsHigh: canvasSize, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Could not create the icon bitmap")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

drawTile()
let tilt = NSAffineTransform()
tilt.translateX(by: tile.midX, yBy: tile.midY - 6)
tilt.rotate(byDegrees: -13)
tilt.scaleX(by: 1.06, yBy: 1.06)
tilt.concat()
drawCan()

NSGraphicsContext.restoreGraphicsState()

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the icon")
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("Wrote \(outPath)")
} catch {
    fatalError("Could not write \(outPath): \(error)")
}
