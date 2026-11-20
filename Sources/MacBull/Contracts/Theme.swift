import SwiftUI
import os

/// The energy-can palette.
enum Theme {
    static let navy = Color(hex: 0x0B1F4D)
    static let navyDeep = Color(hex: 0x061233)
    static let electric = Color(hex: 0x1F66FF)
    static let volt = Color(hex: 0xD6F233)
    static let frost = Color(hex: 0xEDF5FF)
    static let sceneInk = Color(hex: 0x080D1A)
    static let dropLight = Color(hex: 0xEDFF73)
    static let dropDark = Color(hex: 0x8CCC14)
    /// Liquid tint when the Mac runs hot or low (Live Carbonation).
    static let amber = Color(hex: 0xFFB020)

    /// The accent used as text: dark olive in light mode, volt in dark mode.
    static let voltInk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(Color(hex: 0xD6F233))
            : NSColor(Color(hex: 0x4F6B00))
    })

    enum Radius {
        static let panel: CGFloat = 22
        static let hero: CGFloat = 18
        static let box: CGFloat = 14
        static let banner: CGFloat = 10
        static let chip: CGFloat = 8
        static let button: CGFloat = 6
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Unified logging, subsystem app.macbull.MacBull.
enum Log {
    private static let subsystem = "app.macbull.MacBull"
    static let engine = Logger(subsystem: subsystem, category: "Engine")
    static let power = Logger(subsystem: subsystem, category: "Power")
    static let lid = Logger(subsystem: subsystem, category: "Lid")
    static let agents = Logger(subsystem: subsystem, category: "Agents")
    static let journal = Logger(subsystem: subsystem, category: "Journal")
    static let ui = Logger(subsystem: subsystem, category: "UI")
}
